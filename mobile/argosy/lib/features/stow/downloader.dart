import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Progress of one file download.
class DownloadProgress {
  const DownloadProgress(this.received, this.total);

  /// Bytes on disk so far, including anything a previous attempt left behind.
  final int received;

  /// Total expected bytes, or 0 when the server didn't say.
  final int total;
}

/// Thrown when a download is cancelled through its [DownloadHandle].
class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Download cancelled';
}

/// A cancellable handle on a running download.
class DownloadHandle {
  bool _cancelled = false;
  http.Client? _client;

  bool get isCancelled => _cancelled;

  /// Aborts the transfer. The partial file is left on disk deliberately — the
  /// next attempt resumes from it rather than re-fetching what already arrived.
  void cancel() {
    _cancelled = true;
    _client?.close();
  }
}

/// Downloads [url] to [target], resuming from whatever a previous attempt left
/// behind.
///
/// Resume is the point of this rather than a plain `http.get`: a package can run
/// to a couple of gigabytes over home Wi-Fi, and a transfer that restarts from
/// byte zero every time the phone changes network, sleeps, or the app is swapped
/// out will, in practice, never finish. Bytes land in a `.part` file and are only
/// renamed into place once the transfer completes, so a partial download is never
/// mistaken for a playable file.
///
/// The server serves these with `Accept-Ranges: bytes` (both the stream endpoint
/// and the package endpoint go through `http.ServeContent`), so a resume is a
/// `Range: bytes=N-` away.
Future<void> downloadFile({
  required Uri url,
  required File target,
  required DownloadHandle handle,
  Map<String, String> headers = const {},
  void Function(DownloadProgress)? onProgress,
}) async {
  final partial = File('${target.path}.part');
  // The validator the partial bytes were fetched against, stored beside them.
  final validatorFile = File('${target.path}.part.etag');

  var existing = 0;
  String? validator;
  if (await partial.exists()) {
    if (await validatorFile.exists()) {
      validator = (await validatorFile.readAsString()).trim();
    }
    if (validator != null && validator.isNotEmpty) {
      existing = await partial.length();
    } else {
      // Bytes with no validator can't be proven to belong to the file we're
      // about to fetch, and a wrong guess splices two files into one that plays
      // until the seam. Cheaper to re-download than to ship that.
      await partial.delete();
    }
  }

  final client = http.Client();
  handle._client = client;
  IOSink? sink;
  try {
    if (handle.isCancelled) throw const DownloadCancelled();

    final request = http.Request('GET', url);
    request.headers.addAll(headers);
    if (existing > 0) {
      request.headers['Range'] = 'bytes=$existing-';
      // If-Range is what makes the resume safe. Without it the server honours
      // the range against whatever the file is *now*, and a re-encoded package
      // (a new job, a different encoder, a changed height cap) or a rescanned
      // source appends onto bytes from a different file. The length check can't
      // catch that — `total` is derived from the new response, so the spliced
      // file satisfies it and gets renamed into place as playable.
      // On a mismatch the server answers 200 with the whole file instead of
      // 206, which the branch below already handles by starting over.
      request.headers['If-Range'] = validator!;
    }
    final response = await client.send(request);

    // 206 means the server honoured the range and we append. 200 means it sent
    // the whole file regardless (no resume, or If-Range said the file changed),
    // so anything already on disk is stale and the write starts over.
    var received = existing;
    var append = true;
    if (response.statusCode == HttpStatus.ok) {
      append = false;
      received = 0;
    } else if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // The partial is already at or past the end of the file — which happens
      // if the process died between the final flush and the rename, leaving a
      // complete `.part`. Since a failure now keeps the partial, treating this
      // as an error would wedge the item: every retry asks for a range past
      // EOF, gets 416, and keeps the partial that caused it. Start over from
      // zero instead; it terminates, and the window is one rename wide.
      await partial.delete();
      return downloadFile(
        url: url,
        target: target,
        handle: handle,
        headers: headers,
        onProgress: onProgress,
      );
    } else if (response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Download failed (${response.statusCode})', uri: url);
    }

    // Record the validator for whatever we're about to write, so a later resume
    // can prove it is continuing the same file. Both endpoints set an ETag; a
    // server that sends none leaves this empty and the next attempt restarts.
    final etag = response.headers[HttpHeaders.etagHeader] ?? '';
    if (!append || etag.isNotEmpty) {
      await validatorFile.writeAsString(etag, flush: true);
    }

    final contentLength = response.contentLength ?? 0;
    final total = contentLength > 0 ? received + contentLength : 0;
    onProgress?.call(DownloadProgress(received, total));

    sink = partial.openWrite(mode: append ? FileMode.append : FileMode.write);
    // Report at most a few times a second: the UI can't use more, and every
    // notification rebuilds a widget tree.
    var lastReport = DateTime.now();
    await for (final chunk in response.stream) {
      if (handle.isCancelled) throw const DownloadCancelled();
      sink.add(chunk);
      received += chunk.length;
      final now = DateTime.now();
      if (now.difference(lastReport) > const Duration(milliseconds: 250)) {
        lastReport = now;
        onProgress?.call(DownloadProgress(received, total));
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (handle.isCancelled) throw const DownloadCancelled();

    // A truncated transfer that ended without an error would otherwise be
    // renamed into place and play as a file that stops halfway.
    if (total > 0 && await partial.length() != total) {
      throw HttpException(
        'Download ended early (${await partial.length()} of $total bytes)',
        uri: url,
      );
    }

    if (await target.exists()) {
      await target.delete();
    }
    await partial.rename(target.path);
    // The validator only guards a partial; once the file is whole it is noise.
    if (await validatorFile.exists()) {
      await validatorFile.delete();
    }
    onProgress?.call(DownloadProgress(received, total));
  } on http.ClientException catch (_) {
    // Closing the client to cancel surfaces here; report the cancellation the
    // caller asked for rather than a transport error it didn't cause.
    if (handle.isCancelled) throw const DownloadCancelled();
    rethrow;
  } finally {
    // Only close the sink on the error path — the success path already closed
    // it, and closing twice throws.
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {
        /* already broken; the partial file is what matters */
      }
    }
    handle._client = null;
    client.close();
  }
}
