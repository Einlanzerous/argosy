import 'dart:async';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../api/api_providers.dart';
import '../../api/stream_urls.dart';
import '../../platform/device_capabilities.dart';
import '../browse/media_card.dart';
import 'downloader.dart';
import 'offline_progress_queue.dart';
import 'stow_store.dart';
import 'stowed_item.dart';

/// Drives the whole stow flow for the device: ask the server how this item will
/// come down, wait for a package if one is being made, pull the bytes, fetch the
/// subtitles alongside them, and record the result so it plays with no network.
///
/// Held as a single controller rather than one per item because the Stowed
/// screen, the detail-screen button, and the player all need to agree on what is
/// in flight, and because cancelling has to reach a download the screen that
/// started it may have long since disposed.
class StowController extends Notifier<Map<String, StowStatus>> {
  StowController();

  final Map<String, DownloadHandle> _handles = {};
  final Map<String, String> _jobs = {}; // itemId -> server job id

  @override
  Map<String, StowStatus> build() => const {};

  StowStore get _store => ref.read(stowStoreProvider);
  StowApi get _stowApi => ref.read(stowApiProvider);
  LibraryApi get _libraryApi => ref.read(libraryApiProvider);
  StreamUrls get _urls => ref.read(streamUrlsProvider);

  /// Live status for an item: the in-flight phase if there is one, else
  /// [StowPhase.stowed] when it is already on the device.
  StowStatus statusFor(String itemId) {
    final live = state[itemId];
    if (live != null) return live;
    if (_store.has(itemId)) {
      return StowStatus(
        phase: StowPhase.stowed,
        totalBytes: _store.get(itemId)?.bytes ?? 0,
      );
    }
    // In-flight status lives in memory, so after a restart a stow that failed
    // partway would otherwise read as "never started" — offering Stow with no
    // hint that gigabytes are sitting underneath it. The unfinished index entry
    // is what survives, so report from that.
    final partial = _store.partial(itemId);
    if (partial != null) {
      return StowStatus(
        phase: StowPhase.failed,
        receivedBytes: partial.bytes,
        message: 'Download stopped partway — it resumes where it left off.',
      );
    }
    return const StowStatus.none();
  }

  void _set(String itemId, StowStatus status) {
    state = {...state, itemId: status};
  }

  void _clear(String itemId) {
    final next = {...state}..remove(itemId);
    state = next;
  }

  /// Stows an item known only by id — the episode-row case, where the screen
  /// holds an [EpisodeSummary] rather than a full detail. Fetches the detail
  /// first, since the stow record has to stand on its own offline.
  Future<void> stowById(String itemId, {String? subtitleLine}) async {
    if (statusFor(itemId).isBusy) return;
    _set(itemId, const StowStatus(phase: StowPhase.requesting));
    try {
      final detail = await _libraryApi.getMediaItem(itemId);
      if (detail == null) {
        throw const ApiFailure('That item is no longer in the library.');
      }
      // stow() re-checks isBusy, so clear the placeholder status first.
      _clear(itemId);
      await stow(detail, subtitleLine: subtitleLine);
    } catch (e) {
      _set(
        itemId,
        StowStatus(
          phase: StowPhase.failed,
          message: e is ApiFailure ? e.message : mapApiError(e).message,
        ),
      );
    }
  }

  /// Packs [item] away for offline viewing. Safe to call again for an item
  /// already in flight — it is a no-op rather than a second download.
  Future<void> stow(MediaItemDetail item, {String? subtitleLine}) async {
    final itemId = item.id;
    if (statusFor(itemId).isBusy) return;

    final handle = DownloadHandle();
    _handles[itemId] = handle;
    _set(itemId, const StowStatus(phase: StowPhase.requesting));

    // Kept outside the try so the failure path can record how far the download
    // actually got. The index is only reconciled against disk at load(), which
    // early-returns once the index is in memory — so without this the row would
    // report 0 bytes for the rest of the session, and The Hold would offer to
    // free "0 B" while deleting gigabytes.
    StowedItem? started;

    try {
      final job = await _requestPackage(itemId, handle);
      if (job == null) return; // cancelled
      final url = job.downloadUrl;
      if (url == null || url.isEmpty) {
        throw const ApiFailure(
          'The server did not say where to download from.',
        );
      }

      final fileName = _videoFileName(job, item);
      final dir = await _store.itemDir(itemId);
      final target = File('${dir.path}/$fileName');

      // Bytes an earlier attempt already fetched. This is a retry as often as
      // not, and the row must not be rewritten to zero on the way in: a failure
      // before the first chunk arrives (the link that just died dropping again,
      // a 401 on a revoked token, a 404 on a moved source) would otherwise
      // persist that zero, and the failure path would write it straight back.
      final partialFile = File('${target.path}.part');
      final resumeFrom = await partialFile.exists()
          ? await partialFile.length()
          : 0;

      // Record the entry before a byte lands, marked unfinished. The bytes are
      // about to exist on the device whether or not the download completes, and
      // a row is what makes them visible in the storage total, listable, and
      // deletable — a failed 12 GB stow would otherwise sit there unreachable.
      final entry = started = StowedItem(
        itemId: itemId,
        title: item.title,
        subtitleLine: subtitleLine ?? _defaultSubtitleLine(item),
        fileName: fileName,
        bytes: resumeFrom,
        durationSeconds: (item.durationSeconds ?? 0).toDouble(),
        stowedAt: DateTime.now(),
        posterUrl: item.posterUrl,
        // The catalog says `episode`, not `series` — a playable item is never
        // the series itself. Anything episode-shaped rows as series so the
        // offline list labels it the way the rest of the app does.
        kind: item.kind == 'episode' || item.episodeNumber != null
            ? MediaKind.series
            : MediaKind.movie,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        incomplete: true,
      );
      await _store.put(entry);
      // stowedItemsProvider caches, and The Hold reads it — without this the
      // row exists on disk but no surface shows it until something else
      // invalidates.
      ref.invalidate(stowedItemsProvider);
      var lastSized = DateTime.now();

      _set(
        itemId,
        StowStatus(
          phase: StowPhase.downloading,
          totalBytes: job.bytes ?? 0,
          durationSeconds: job.durationSeconds ?? 0,
        ),
      );
      await downloadFile(
        url: _absolute(url),
        target: target,
        handle: handle,
        headers: _authHeaders,
        onProgress: (p) {
          _set(
            itemId,
            StowStatus(
              phase: StowPhase.downloading,
              receivedBytes: p.received,
              totalBytes: p.total > 0 ? p.total : (job.bytes ?? 0),
            ),
          );
          // Keep the persisted size roughly current so The Hold, opened mid
          // download, reports real numbers. Throttled well below the progress
          // tick rate — this rewrites the index file, and the UI reads the live
          // status anyway.
          final now = DateTime.now();
          if (now.difference(lastSized) >= const Duration(seconds: 3)) {
            lastSized = now;
            unawaited(
              _store
                  .put(entry.copyWith(bytes: p.received))
                  .then((_) => ref.invalidate(stowedItemsProvider)),
            );
          }
        },
      );

      final subtitles = await _downloadSubtitles(itemId, dir.path, handle);

      // Finished: flip the entry to playable, with its real size and tracks.
      await _store.put(
        entry.copyWith(
          bytes: await target.length(),
          incomplete: false,
          subtitles: subtitles,
        ),
      );

      // The bytes are ours now; let the server reclaim its copy immediately
      // rather than waiting out the retention clock.
      await _releaseJob(itemId);
      // Drop the in-flight status: statusFor falls back to the index, which now
      // reports this item stowed with its real size on disk.
      _clear(itemId);
      ref.invalidate(stowedItemsProvider);
    } on DownloadCancelled {
      // An explicit cancel means "I don't want this" — free the space.
      await _cleanUp(itemId);
      _clear(itemId);
    } catch (e) {
      // A *failure* deliberately keeps the partial. Wiping it here would make
      // the resumable downloader pointless: the case it exists for is a
      // transfer dying partway, and the retry that follows resumes from these
      // bytes (validated by the stored ETag) instead of starting a 2 GB
      // download over. The server-side job is kept for the same reason — a
      // retry then reuses the finished package rather than re-encoding it.
      //
      // The row does need its size written now, though: nothing else will until
      // the next launch reconciles against disk, and until then the storage view
      // and the delete dialog would both quote 0 B for bytes that are really
      // there.
      final row = started;
      if (row != null) {
        // Size it from the filesystem, never the progress counter: the
        // download may have restarted from zero on the way through (a changed
        // ETag, an unvalidated partial discarded, a 416), and those paths
        // delete the partial *before* reconnecting — so a failure in that
        // window leaves the counter describing bytes that are already gone.
        // Falling back to it would quote gigabytes that aren't there.
        await _store.put(row.copyWith(bytes: await _bytesOnDisk(row)));
        ref.invalidate(stowedItemsProvider);
      }
      _set(
        itemId,
        StowStatus(
          phase: StowPhase.failed,
          message: e is ApiFailure ? e.message : mapApiError(e).message,
        ),
      );
    } finally {
      _handles.remove(itemId);
    }
  }

  /// Asks the server for a plan and, when it is packaging, waits for it. Returns
  /// null if the stow was cancelled while waiting.
  Future<StowJob?> _requestPackage(String itemId, DownloadHandle handle) async {
    final job = await _stowApi.stowItem(
      itemId,
      stowRequest: StowRequest(
        hevc: await DeviceCapabilities.supportsHevc4k(),
        // ExoPlayer opens Matroska; AVPlayer does not. Answering honestly is
        // what lets most of an mkv library stow without an encode on Android.
        matroska: Platform.isAndroid,
      ),
    );
    if (job == null) {
      throw const ApiFailure("The server couldn't prepare this download.");
    }
    if (job.state == StowJobStateEnum.ready) return job;

    final jobId = job.id;
    if (jobId == null) {
      throw const ApiFailure('The server started a package without an id.');
    }
    _jobs[itemId] = jobId;
    _set(
      itemId,
      StowStatus(
        phase: StowPhase.packaging,
        durationSeconds: job.durationSeconds ?? 0,
        message: job.reason,
      ),
    );

    // Poll until the encode finishes. No timeout: a feature-length film on a
    // software encoder legitimately takes a long time, and the user can cancel.
    while (true) {
      if (handle.isCancelled) return null;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (handle.isCancelled) return null;

      final polled = await _stowApi.getStowJob(jobId);
      if (polled == null) {
        throw const ApiFailure('The packaging job disappeared.');
      }
      switch (polled.state) {
        case StowJobStateEnum.ready:
          return polled;
        case StowJobStateEnum.failed:
          throw ApiFailure(polled.error ?? 'Packaging failed.');
        default:
          _set(
            itemId,
            StowStatus(
              phase: StowPhase.packaging,
              packagedSeconds: polled.progressSeconds ?? 0,
              durationSeconds: polled.durationSeconds ?? 0,
            ),
          );
      }
    }
  }

  /// Pulls every listed subtitle track down beside the video. Failures are
  /// tolerated one track at a time — missing captions are a smaller loss than a
  /// stow that refuses to finish because OpenSubtitles was slow.
  Future<List<StowedSubtitle>> _downloadSubtitles(
    String itemId,
    String dirPath,
    DownloadHandle handle,
  ) async {
    List<SubtitleTrack>? tracks;
    try {
      tracks = await _libraryApi.listSubtitles(itemId);
    } catch (_) {
      return const [];
    }
    if (tracks == null || tracks.isEmpty) return const [];

    final out = <StowedSubtitle>[];
    for (final track in tracks) {
      if (handle.isCancelled) break;
      final fileName = 'sub-${_safeName(track.id)}.vtt';
      try {
        final res = await http.get(
          _urls.subtitle(itemId, track.id),
          headers: _authHeaders,
        );
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        await File('$dirPath/$fileName').writeAsBytes(res.bodyBytes);
        out.add(
          StowedSubtitle(
            id: track.id,
            label: track.label,
            language: track.language,
            fileName: fileName,
          ),
        );
      } catch (_) {
        /* skip this track */
      }
    }
    return out;
  }

  /// How much of an item is actually on disk right now: the partial if one is
  /// there, the finished file if the rename already landed, else nothing.
  Future<int> _bytesOnDisk(StowedItem row) async {
    final video = File(await _store.videoPath(row));
    final part = File('${video.path}.part');
    if (await part.exists()) return part.length();
    if (await video.exists()) return video.length();
    return 0;
  }

  /// Cancels an in-flight stow and clears whatever it had written.
  Future<void> cancel(String itemId) async {
    _handles[itemId]?.cancel();
    await _cleanUp(itemId);
    _clear(itemId);
  }

  /// Removes a stowed item from the device.
  Future<void> remove(String itemId) async {
    _handles[itemId]?.cancel();
    await _releaseJob(itemId);
    await _store.remove(itemId);
    _clear(itemId);
    ref.invalidate(stowedItemsProvider);
  }

  Future<void> _cleanUp(String itemId) async {
    await _releaseJob(itemId);
    await _store.discardPartial(itemId);
  }

  /// Tells the server it can drop its copy. Best-effort: the server's retention
  /// sweep is the backstop if this never lands.
  Future<void> _releaseJob(String itemId) async {
    final jobId = _jobs.remove(itemId);
    if (jobId == null) return;
    try {
      await _stowApi.deleteStowJob(jobId);
    } catch (_) {
      /* the retention sweep will get it */
    }
  }

  Map<String, String> get _authHeaders {
    final token = ref.read(tokenStoreProvider).token;
    return (token != null && token.isNotEmpty)
        ? {'Authorization': 'Bearer $token'}
        : const {};
  }

  /// Turns the server's relative download URL into an absolute one carrying the
  /// per-device token, since the transfer runs outside the API client.
  Uri _absolute(String path) {
    final base = ref.read(baseUrlProvider);
    final token = ref.read(tokenStoreProvider).token;
    final uri = Uri.parse('$base$path');
    if (token == null || token.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'token': token},
    );
  }

  /// A package is always MP4. A passthrough keeps the source's own container,
  /// because that is literally the file being copied — handing ExoPlayer an
  /// `.mp4` that is really Matroska works by sniffing, but only by luck.
  String _videoFileName(StowJob job, MediaItemDetail item) {
    if (job.method == StowJobMethodEnum.package) return 'video.mp4';
    final ext = (item.container ?? '').replaceAll('.', '').toLowerCase();
    return ext.isEmpty ? 'video.mp4' : 'video.$ext';
  }

  String? _defaultSubtitleLine(MediaItemDetail item) {
    if (item.seasonNumber != null && item.episodeNumber != null) {
      final code = 'S${item.seasonNumber} · E${item.episodeNumber}';
      final title = item.episodeTitle;
      return title == null || title.isEmpty ? code : '$code · $title';
    }
    return item.year?.toString();
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}

/// The device's stow index. Callers `await store.load()` before reading; it is
/// idempotent, so every entry point can do so without coordinating.
final stowStoreProvider = Provider<StowStore>((ref) => StowStore());

/// Resume positions recorded while the server was unreachable, waiting to be
/// sent. Drained whenever a progress report succeeds, and once at startup.
final offlineProgressQueueProvider = Provider<OfflineProgressQueue>(
  (ref) => OfflineProgressQueue(),
);

/// Sends anything the device recorded offline. Called once after sign-in, so a
/// flight's worth of watching lands without waiting for the next play.
Future<int> flushOfflineProgress(Ref ref) async {
  try {
    return await ref
        .read(offlineProgressQueueProvider)
        .flush(ref.read(libraryApiProvider));
  } catch (_) {
    return 0; // Still offline; the next attempt will get it.
  }
}

final stowApiProvider = Provider<StowApi>(
  (ref) => StowApi(ref.watch(apiClientProvider)),
);

final stowControllerProvider =
    NotifierProvider<StowController, Map<String, StowStatus>>(
      StowController.new,
    );

/// Everything currently stowed on the device. Invalidated by the controller
/// whenever the index changes.
final stowedItemsProvider = FutureProvider<List<StowedItem>>((ref) async {
  final store = ref.watch(stowStoreProvider);
  await store.load();
  return store.list();
});

/// Whether a given item is playable from local storage right now — the player
/// consults this before reaching for the network.
final stowedItemProvider = FutureProvider.family<StowedItem?, String>((
  ref,
  itemId,
) async {
  final store = ref.watch(stowStoreProvider);
  await store.load();
  return store.get(itemId);
});
