import 'dart:async';
import 'dart:io';

import 'package:argosy/features/stow/downloader.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny HTTP server that serves a fixed body with byte-range support, so the
/// resume path is exercised against something that behaves like the real
/// endpoint (both stow endpoints go through Go's http.ServeContent).
class _RangeServer {
  _RangeServer(this.body);

  final List<int> body;
  late HttpServer _server;

  /// Requests seen, as the raw Range header (null when absent).
  final List<String?> ranges = [];

  /// `If-Range` values seen, in request order (null when absent).
  final List<String?> ifRanges = [];

  /// The entity tag served, and matched against `If-Range`.
  String etag = '"v1"';

  /// When set, the connection is dropped after this many bytes — standing in
  /// for a transfer interrupted mid-flight.
  int? cutAfter;

  Uri get url => Uri.parse('http://${_server.address.host}:${_server.port}/f');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    await for (final req in _server) {
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final ifRange = req.headers.value(HttpHeaders.ifRangeHeader);
      ranges.add(range);
      ifRanges.add(ifRange);
      req.response.headers.set(HttpHeaders.etagHeader, etag);

      // Mirrors http.ServeContent: a range whose If-Range no longer matches is
      // answered with the whole file (200), not a partial.
      final honourRange =
          range != null &&
          range.startsWith('bytes=') &&
          (ifRange == null || ifRange == etag);

      var start = 0;
      if (honourRange) {
        start = int.parse(range.substring(6).split('-').first);
        // Mirrors http.ServeContent: a start at or past EOF is unsatisfiable.
        if (start >= body.length) {
          req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await req.response.close();
          continue;
        }
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${body.length - 1}/${body.length}',
        );
      } else {
        req.response.statusCode = HttpStatus.ok;
      }
      final slice = body.sublist(start);
      final cut = cutAfter;
      if (cut != null) {
        // Announce the full length, then send less and hang up.
        req.response.contentLength = slice.length;
        req.response.add(slice.sublist(0, cut));
        await req.response.flush();
        await req.response.close().catchError((_) {});
        await _server.close(force: true);
        return;
      }
      req.response.contentLength = slice.length;
      req.response.add(slice);
      await req.response.close();
    }
  }

  Future<void> stop() async => _server.close(force: true);
}

void main() {
  late Directory dir;
  final body = List<int>.generate(4096, (i) => i % 256);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('argosy-dl-test');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('downloads a file and reports progress', () async {
    final server = _RangeServer(body);
    await server.start();
    addTearDown(server.stop);

    final target = File('${dir.path}/video.mp4');
    final seen = <int>[];
    await downloadFile(
      url: server.url,
      target: target,
      handle: DownloadHandle(),
      onProgress: (p) => seen.add(p.received),
    );

    expect(await target.readAsBytes(), body);
    expect(seen.last, body.length);
    expect(
      await File('${target.path}.part').exists(),
      isFalse,
      reason: 'the partial file is renamed into place, not left beside it',
    );
  });

  test('resumes from a partial instead of refetching', () async {
    // Leave the first 1000 bytes on disk, as an interrupted attempt would,
    // alongside the validator they were fetched against.
    final target = File('${dir.path}/video.mp4');
    await File('${target.path}.part').writeAsBytes(body.sublist(0, 1000));
    await File('${target.path}.part.etag').writeAsString('"v1"');

    final server = _RangeServer(body);
    await server.start();
    addTearDown(server.stop);

    await downloadFile(
      url: server.url,
      target: target,
      handle: DownloadHandle(),
    );

    expect(server.ranges.single, 'bytes=1000-');
    expect(server.ifRanges.single, '"v1"');
    expect(
      await target.readAsBytes(),
      body,
      reason: 'the resumed half must join the existing half exactly',
    );
    expect(
      await File('${target.path}.part.etag').exists(),
      isFalse,
      reason: 'the validator only guards a partial',
    );
  });

  test('a changed file restarts the download instead of splicing', () async {
    // A partial from an earlier, different file: same offset, stale validator.
    final target = File('${dir.path}/video.mp4');
    await File('${target.path}.part').writeAsBytes(List.filled(1000, 0xAA));
    await File('${target.path}.part.etag').writeAsString('"v1"');

    // The server now holds a re-encoded package under a new tag — a new job, a
    // different encoder, or a rescanned source.
    final server = _RangeServer(body)..etag = '"v2"';
    await server.start();
    addTearDown(server.stop);

    await downloadFile(
      url: server.url,
      target: target,
      handle: DownloadHandle(),
    );

    expect(server.ifRanges.single, '"v1"');
    expect(
      await target.readAsBytes(),
      body,
      reason: 'a spliced file would play until the seam and then stop',
    );
  });

  test(
    'a partial with no validator is discarded rather than resumed',
    () async {
      // Bytes left by a version that recorded no validator can't be proven to
      // belong to this file, so they must not be appended to.
      final target = File('${dir.path}/video.mp4');
      await File('${target.path}.part').writeAsBytes(List.filled(1000, 0xBB));

      final server = _RangeServer(body);
      await server.start();
      addTearDown(server.stop);

      await downloadFile(
        url: server.url,
        target: target,
        handle: DownloadHandle(),
      );

      expect(server.ranges.single, isNull, reason: 'no resume was attempted');
      expect(await target.readAsBytes(), body);
    },
  );

  test('a truncated transfer is not renamed into place', () async {
    final server = _RangeServer(body)..cutAfter = 512;
    await server.start();
    addTearDown(server.stop);

    final target = File('${dir.path}/video.mp4');
    await expectLater(
      downloadFile(url: server.url, target: target, handle: DownloadHandle()),
      throwsA(anything),
    );

    expect(
      await target.exists(),
      isFalse,
      reason: 'a half-file that plays and then stops is worse than no file',
    );
    expect(
      await File('${target.path}.part').exists(),
      isTrue,
      reason: 'the partial is kept so the next attempt resumes from it',
    );
  });

  test('cancelling throws DownloadCancelled and keeps the partial', () async {
    final server = _RangeServer(body);
    await server.start();
    addTearDown(server.stop);

    final handle = DownloadHandle()..cancel();
    final target = File('${dir.path}/video.mp4');

    await expectLater(
      downloadFile(url: server.url, target: target, handle: handle),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await target.exists(), isFalse);
  });

  test('a complete partial (416) restarts instead of wedging', () async {
    // The window between the final flush and the rename: the .part holds the
    // whole file. Asking to resume past EOF gets a 416, and since a failure now
    // keeps the partial, treating that as an error would loop forever.
    final target = File('${dir.path}/video.mp4');
    await File('${target.path}.part').writeAsBytes(body);
    await File('${target.path}.part.etag').writeAsString('"v1"');

    final server = _RangeServer(body);
    await server.start();
    addTearDown(server.stop);

    await downloadFile(
      url: server.url,
      target: target,
      handle: DownloadHandle(),
    );

    expect(await target.readAsBytes(), body);
    expect(
      server.ranges.length,
      2,
      reason: 'the 416 attempt, then a clean restart from zero',
    );
    expect(server.ranges.last, isNull, reason: 'the retry asks for everything');
  });

  test('a server error surfaces rather than writing a body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(() async {
      await for (final req in server) {
        req.response.statusCode = HttpStatus.conflict;
        await req.response.close();
      }
    }());

    final target = File('${dir.path}/video.mp4');
    await expectLater(
      downloadFile(
        url: Uri.parse('http://${server.address.host}:${server.port}/f'),
        target: target,
        handle: DownloadHandle(),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await target.exists(), isFalse);
  });
}
