import 'dart:async';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../api/api_providers.dart';
import '../../api/stream_urls.dart';
import '../browse/media_card.dart';
import 'downloader.dart';
import 'stow_store.dart';
import 'stowed_item.dart';

/// One item's stow, described completely enough to be executed by something
/// that has never seen the catalog.
///
/// Everything the transfer needs is captured here rather than resolved later,
/// because the code that runs it lives in another isolate (ARGY-201) and, after
/// a service restart, in another *process* — where there is no widget tree, no
/// Riverpod container, and no device-capability channel to ask. In particular
/// [hevc] and [matroska] are answered by the UI while it is alive and carried
/// along: the capability channel is registered on the main engine only, so a
/// background isolate that asked would get "no" and package a file the phone
/// could have taken as-is.
class StowJobRequest {
  const StowJobRequest({
    required this.itemId,
    required this.title,
    required this.sourcePath,
    this.subtitleLine,
    this.posterUrl,
    this.durationSeconds = 0,
    this.isEpisode = false,
    this.seasonNumber,
    this.episodeNumber,
    this.hevc = false,
    this.matroska = false,
  });

  final String itemId;
  final String title;

  /// The library-relative path of the source file. Only its extension is used —
  /// see [StowRunner._videoFileName].
  final String sourcePath;

  final String? subtitleLine;
  final String? posterUrl;
  final double durationSeconds;
  final bool isEpisode;
  final int? seasonNumber;
  final int? episodeNumber;

  /// What this device can play without re-encoding, as answered by the UI.
  final bool hevc;
  final bool matroska;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'title': title,
    'sourcePath': sourcePath,
    'subtitleLine': subtitleLine,
    'posterUrl': posterUrl,
    'durationSeconds': durationSeconds,
    'isEpisode': isEpisode,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
    'hevc': hevc,
    'matroska': matroska,
  };

  static StowJobRequest fromJson(Map<String, dynamic> json) => StowJobRequest(
    itemId: json['itemId'] as String,
    title: json['title'] as String? ?? 'Untitled',
    sourcePath: json['sourcePath'] as String? ?? '',
    subtitleLine: json['subtitleLine'] as String?,
    posterUrl: json['posterUrl'] as String?,
    durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
    isEpisode: json['isEpisode'] as bool? ?? false,
    seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
    episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
    hevc: json['hevc'] as bool? ?? false,
    matroska: json['matroska'] as bool? ?? false,
  );
}

/// Something a stow did, on its way to whoever is showing it.
///
/// [indexChanged] is separate from [status] because the two travel differently:
/// a progress tick is live state the UI holds in memory, while an index change
/// means the file on disk that *both* isolates read has been rewritten, and the
/// reader has to reload it rather than trust its own copy.
class StowEvent {
  const StowEvent({
    required this.itemId,
    this.status,
    this.indexChanged = false,
  }) : assert(itemId != null || status == null);

  /// Signals the runner has nothing left to do — the cue to shut a foreground
  /// service down rather than leave a notification sitting there.
  const StowEvent.idle() : itemId = null, status = null, indexChanged = false;

  /// The item this concerns, or null for [StowEvent.idle].
  final String? itemId;

  /// The item's live status, or null to say it no longer has one (finished,
  /// cancelled, removed) and the reader should fall back to the index.
  final StowStatus? status;

  /// Whether the on-disk index changed and must be re-read.
  final bool indexChanged;

  bool get isIdle => itemId == null;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'status': status?.toJson(),
    'indexChanged': indexChanged,
  };

  static StowEvent fromJson(Map<String, dynamic> json) {
    final itemId = json['itemId'] as String?;
    if (itemId == null) return const StowEvent.idle();
    final status = json['status'] as Map<String, dynamic>?;
    return StowEvent(
      itemId: itemId,
      status: status == null ? null : StowStatus.fromJson(status),
      indexChanged: json['indexChanged'] as bool? ?? false,
    );
  }
}

/// A connection to the household server for the duration of one stow.
///
/// Built per run rather than shared, because the runner may be executing in a
/// service isolate that outlives — or never sees — the app's provider graph.
class StowSession {
  StowSession({
    required this.stow,
    required this.library,
    required this.urls,
    required this.baseUrl,
    this.token,
    http.Client? client,
  }) : client = client ?? http.Client();

  /// Connects to [baseUrl] with the device [token].
  ///
  /// The transport carries the same bounded connect timeout as the app's client
  /// (ARGY-49): a host that routes but has nothing listening otherwise hangs for
  /// the OS connect timeout, and here that would hold a foreground service — and
  /// its notification — open for minutes over a server that is simply off.
  factory StowSession.connect({required String baseUrl, String? token}) {
    final transport = IOClient(
      HttpClient()..connectionTimeout = const Duration(seconds: 6),
    );
    final auth = HttpBearerAuth()..accessToken = () => token ?? '';
    final api = ApiClient(basePath: baseUrl, authentication: auth)
      ..client = transport;
    return StowSession(
      stow: StowApi(api),
      library: LibraryApi(api),
      urls: StreamUrls(baseUrl, token),
      baseUrl: baseUrl,
      token: token,
      client: transport,
    );
  }

  final StowApi stow;
  final LibraryApi library;
  final StreamUrls urls;
  final String baseUrl;
  final String? token;
  final http.Client client;

  Map<String, String> get authHeaders {
    final value = token;
    return (value != null && value.isNotEmpty)
        ? {'Authorization': 'Bearer $value'}
        : const {};
  }

  /// Turns the server's relative download URL into an absolute one carrying the
  /// per-device token, since the transfer runs outside the API client.
  Uri absolute(String path) {
    final uri = Uri.parse('$baseUrl$path');
    final value = token;
    if (value == null || value.isEmpty) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'token': value},
    );
  }

  void close() => client.close();
}

/// Where a runner keeps the jobs it still owes, so they survive it.
///
/// Only the service-backed runner has anything to persist; in-app runs die with
/// the app either way, which is what [MemoryStowQueue] models.
abstract class StowQueueStore {
  Future<List<StowJobRequest>> load();
  Future<void> save(List<StowJobRequest> jobs);
}

/// A queue that remembers nothing across a restart.
class MemoryStowQueue implements StowQueueStore {
  @override
  Future<List<StowJobRequest>> load() async => const [];

  @override
  Future<void> save(List<StowJobRequest> jobs) async {}
}

/// Executes stows one at a time: ask the server how the item will come down,
/// wait for a package if one is being made, pull the bytes, fetch the subtitles
/// alongside them, and record the result so it plays with no network.
///
/// Deliberately free of Flutter, Riverpod and the widget tree. The whole point
/// of ARGY-201 is that this can run somewhere the UI isn't — a foreground
/// service's isolate, which keeps going after the app is backgrounded or swiped
/// away — so its only contact with the outside world is [onEvent] and the store.
///
/// Sequential rather than parallel: the server packages one item at a time
/// anyway, and two large transfers sharing a phone's link mostly means both
/// finish late.
class StowRunner {
  StowRunner({
    required this.store,
    required this.connect,
    required this.onEvent,
    StowQueueStore? queue,
  }) : _queue = queue ?? MemoryStowQueue();

  final StowStore store;

  /// Opens a connection to the server. Called per job so a run that starts an
  /// hour after it was queued does not hold a stale token.
  final Future<StowSession> Function() connect;

  final void Function(StowEvent) onEvent;
  final StowQueueStore _queue;

  final List<StowJobRequest> _pending = [];
  final Map<String, StowStatus> _statuses = {};
  final Map<String, DownloadHandle> _handles = {};
  final Map<String, String> _serverJobs = {}; // itemId -> server job id

  StowJobRequest? _active;
  Completer<void>? _activeDone;
  Future<void>? _pump;

  /// Live status per item, for a UI attaching to a run already in progress.
  Map<String, StowStatus> get statuses => Map.unmodifiable(_statuses);

  /// The job being worked on right now, if any — what a notification names.
  StowJobRequest? get activeJob => _active;

  /// How many jobs are waiting behind the active one.
  int get pendingCount => _pending.length;

  bool get isIdle => _active == null && _pending.isEmpty;

  /// Queues [job]. A second call for an item already in flight starts no second
  /// download — but it does answer.
  ///
  /// Answering matters because the caller may be a UI that cannot see this
  /// queue. An app relaunched while a stow sits *queued* behind another has no
  /// live status for it and no index row either — a row is only written once a
  /// job becomes active — so it offers a plain Stow button, and a tap lands
  /// here. Returning in silence is indistinguishable from the message never
  /// arriving, which is exactly what the service handshake reads it as: it
  /// retries, times out, and pins a "the download service didn't pick this up"
  /// failure on something that is queued and perfectly healthy.
  Future<void> enqueue(StowJobRequest job) async {
    if (_active?.itemId == job.itemId ||
        _pending.any((j) => j.itemId == job.itemId)) {
      _emit(
        job.itemId,
        _statuses[job.itemId] ?? const StowStatus(phase: StowPhase.requesting),
      );
      return;
    }
    _pending.add(job);
    _emit(job.itemId, const StowStatus(phase: StowPhase.requesting));
    await _persistQueue();
    _start();
  }

  /// Picks up jobs left behind by a previous run of this runner — the service
  /// having been restarted after the system reclaimed it mid-download.
  Future<void> restore() async {
    final saved = await _queue.load();
    if (saved.isEmpty) return;
    for (final job in saved) {
      if (_active?.itemId == job.itemId) continue;
      if (_pending.any((j) => j.itemId == job.itemId)) continue;
      _pending.add(job);
      _emit(job.itemId, const StowStatus(phase: StowPhase.requesting));
    }
    _start();
  }

  /// Stops a stow and frees whatever it had written. Safe for an item that is
  /// queued, running, or neither.
  Future<void> cancel(String itemId) async {
    _pending.removeWhere((j) => j.itemId == itemId);
    await _persistQueue();

    if (_active?.itemId == itemId) {
      // Let the run unwind and clean up after itself. Deleting the directory
      // from here would race the download's own sink, which is still flushing
      // the chunk it was writing when the socket closed — and could recreate
      // the file moments after it was removed.
      _handles[itemId]?.cancel();
      await _activeDone?.future;
      return;
    }
    await _cleanUp(itemId);
    _clear(itemId);
  }

  /// Removes an item from the device entirely, cancelling it first if it is
  /// still coming down.
  Future<void> remove(String itemId) async {
    await cancel(itemId);
    await store.remove(itemId);
    _statuses.remove(itemId);
    onEvent(StowEvent(itemId: itemId, indexChanged: true));
  }

  /// Waits for the queue to drain. Used by tests and by the in-app runner;
  /// the service leaves this to its own lifecycle.
  Future<void> get done => _pump ?? Future<void>.value();

  void _start() {
    _pump ??= _drain().whenComplete(() {
      _pump = null;
      onEvent(const StowEvent.idle());
    });
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      _active = job;
      _activeDone = Completer<void>();
      await _persistQueue();
      try {
        await _run(job);
      } finally {
        _active = null;
        _activeDone?.complete();
        _activeDone = null;
        await _persistQueue();
      }
    }
  }

  /// The queue as it stands, including whatever is running — a job interrupted
  /// halfway is exactly the one that must be picked up again.
  Future<void> _persistQueue() => _queue.save([?_active, ..._pending]);

  Future<void> _run(StowJobRequest job) async {
    final itemId = job.itemId;
    final handle = DownloadHandle();
    _handles[itemId] = handle;
    _emit(itemId, const StowStatus(phase: StowPhase.requesting));

    // Kept outside the try so the failure path can record how far the download
    // actually got. The index is only reconciled against disk at load(), which
    // early-returns once the index is in memory — so without this the row would
    // report 0 bytes for the rest of the session, and The Hold would offer to
    // free "0 B" while deleting gigabytes.
    StowedItem? started;
    StowSession? session;

    try {
      session = await connect();
      final packaged = await _requestPackage(session, job, handle);
      final url = packaged.downloadUrl;
      if (url == null || url.isEmpty) {
        throw const ApiFailure(
          'The server did not say where to download from.',
        );
      }

      final fileName = _videoFileName(packaged, job);
      final dir = await store.itemDir(itemId);
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
        title: job.title,
        subtitleLine: job.subtitleLine,
        fileName: fileName,
        bytes: resumeFrom,
        durationSeconds: job.durationSeconds,
        stowedAt: DateTime.now(),
        posterUrl: job.posterUrl,
        kind: job.isEpisode ? MediaKind.series : MediaKind.movie,
        seasonNumber: job.seasonNumber,
        episodeNumber: job.episodeNumber,
        incomplete: true,
      );
      await store.put(entry);
      _emit(
        itemId,
        StowStatus(
          phase: StowPhase.downloading,
          totalBytes: packaged.bytes ?? 0,
          durationSeconds: packaged.durationSeconds ?? 0,
        ),
        indexChanged: true,
      );

      var lastSized = DateTime.now();
      await downloadFile(
        url: session.absolute(url),
        target: target,
        handle: handle,
        headers: session.authHeaders,
        onProgress: (p) {
          // Keep the persisted size roughly current so The Hold, opened mid
          // download, reports real numbers. Throttled well below the progress
          // tick rate — this rewrites the index file, and readers have the live
          // status anyway.
          final now = DateTime.now();
          final sized = now.difference(lastSized) >= const Duration(seconds: 3);
          if (sized) {
            lastSized = now;
            unawaited(store.put(entry.copyWith(bytes: p.received)));
          }
          _emit(
            itemId,
            StowStatus(
              phase: StowPhase.downloading,
              receivedBytes: p.received,
              totalBytes: p.total > 0 ? p.total : (packaged.bytes ?? 0),
            ),
            indexChanged: sized,
          );
        },
      );

      final subtitles = await _downloadSubtitles(session, itemId, dir, handle);

      // Finished: flip the entry to playable, with its real size and tracks.
      await store.put(
        entry.copyWith(
          bytes: await target.length(),
          incomplete: false,
          subtitles: subtitles,
        ),
      );

      // The bytes are ours now; let the server reclaim its copy immediately
      // rather than waiting out the retention clock.
      await _releaseJob(session, itemId);
      // Drop the live status: readers fall back to the index, which now reports
      // this item stowed with its real size on disk.
      _clear(itemId);
    } on DownloadCancelled {
      // An explicit cancel means "I don't want this" — free the space.
      await _cleanUp(itemId, session);
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
        await store.put(row.copyWith(bytes: await _bytesOnDisk(row)));
      }
      _emit(
        itemId,
        StowStatus(
          phase: StowPhase.failed,
          message: e is ApiFailure ? e.message : mapApiError(e).message,
        ),
        indexChanged: row != null,
      );
    } finally {
      _handles.remove(itemId);
      session?.close();
    }
  }

  /// Asks the server for a plan and, when it is packaging, waits for it.
  ///
  /// Throws [DownloadCancelled] if the stow is cancelled while waiting, rather
  /// than reporting it some other way: cancelling has to release the server's
  /// job, and a second way out of here is a second path that has to remember
  /// to. It didn't — cancelling during packaging used to return quietly, so the
  /// phone stopped polling while the server carried on encoding a 39 GB film to
  /// the end, with nothing left to collect it.
  Future<StowJob> _requestPackage(
    StowSession session,
    StowJobRequest job,
    DownloadHandle handle,
  ) async {
    final itemId = job.itemId;
    final planned = await session.stow.stowItem(
      itemId,
      stowRequest: StowRequest(hevc: job.hevc, matroska: job.matroska),
    );
    if (planned == null) {
      throw const ApiFailure("The server couldn't prepare this download.");
    }
    if (planned.state == StowJobStateEnum.ready) return planned;

    final jobId = planned.id;
    if (jobId == null) {
      throw const ApiFailure('The server started a package without an id.');
    }
    _serverJobs[itemId] = jobId;
    _emit(
      itemId,
      StowStatus(
        phase: StowPhase.packaging,
        durationSeconds: planned.durationSeconds ?? 0,
        message: planned.reason,
      ),
    );

    // Poll until the encode finishes. No timeout: a feature-length film on a
    // software encoder legitimately takes a long time, and the user can cancel.
    while (true) {
      if (handle.isCancelled) throw const DownloadCancelled();
      await Future<void>.delayed(const Duration(seconds: 2));
      if (handle.isCancelled) throw const DownloadCancelled();

      final polled = await session.stow.getStowJob(jobId);
      if (polled == null) {
        throw const ApiFailure('The packaging job disappeared.');
      }
      switch (polled.state) {
        case StowJobStateEnum.ready:
          return polled;
        case StowJobStateEnum.failed:
          throw ApiFailure(polled.error ?? 'Packaging failed.');
        default:
          _emit(
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
    StowSession session,
    String itemId,
    Directory dir,
    DownloadHandle handle,
  ) async {
    List<SubtitleTrack>? tracks;
    try {
      tracks = await session.library.listSubtitles(itemId);
    } catch (_) {
      return const [];
    }
    if (tracks == null || tracks.isEmpty) return const [];

    final out = <StowedSubtitle>[];
    for (final track in tracks) {
      if (handle.isCancelled) break;
      // Image subtitles have no WebVTT form (ARGY-59). Fetching one costs a
      // request and a 30-second timeout to earn a refusal, and there is nothing
      // an offline copy could do with it — the burn-in happens server-side, at
      // playback.
      if (track.burnIn == true) continue;
      final fileName = 'sub-${_safeName(track.id)}.vtt';
      try {
        // Bounded: a caption fetch that hangs would hold the whole stow — and,
        // in the service, its notification — open indefinitely. A VTT is a few
        // tens of kilobytes.
        final res = await session.client
            .get(
              session.urls.subtitle(itemId, track.id),
              headers: session.authHeaders,
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        await File('${dir.path}/$fileName').writeAsBytes(res.bodyBytes);
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
    final video = File(await store.videoPath(row));
    final part = File('${video.path}.part');
    if (await part.exists()) return part.length();
    if (await video.exists()) return video.length();
    return 0;
  }

  Future<void> _cleanUp(String itemId, [StowSession? session]) async {
    if (session != null) {
      await _releaseJob(session, itemId);
    } else {
      _serverJobs.remove(itemId);
    }
    await store.discardPartial(itemId);
  }

  /// Tells the server it can drop its copy. Best-effort: the server's retention
  /// sweep is the backstop if this never lands.
  Future<void> _releaseJob(StowSession session, String itemId) async {
    final jobId = _serverJobs.remove(itemId);
    if (jobId == null) return;
    try {
      await session.stow.deleteStowJob(jobId);
    } catch (_) {
      /* the retention sweep will get it */
    }
  }

  void _emit(String itemId, StowStatus status, {bool indexChanged = false}) {
    _statuses[itemId] = status;
    onEvent(
      StowEvent(itemId: itemId, status: status, indexChanged: indexChanged),
    );
  }

  void _clear(String itemId) {
    _statuses.remove(itemId);
    onEvent(StowEvent(itemId: itemId, indexChanged: true));
  }

  /// A package is always MP4. A passthrough keeps the source's own container,
  /// because that is literally the file being copied — handing ExoPlayer an
  /// `.mp4` that is really Matroska works by sniffing, but only by luck.
  ///
  /// The extension comes from the source *path*, not from the item's
  /// `container`, which is ffprobe's `format_name`: it names the demuxer rather
  /// than the file (an mp4 reports `mov,mp4,m4a,3gp,3g2,mj2`, an mkv reports
  /// `matroska,webm`). Using it produced real files called
  /// `video.mov,mp4,m4a,3gp,3g2,mj2` on device.
  static String _videoFileName(StowJob job, StowJobRequest request) {
    if (job.method == StowJobMethodEnum.package) return 'video.mp4';
    final ext = sourceExtension(request.sourcePath);
    return ext.isEmpty ? 'video.mp4' : 'video.$ext';
  }

  /// The extension of a library-relative source path, lowercased and without
  /// the dot. Empty when the path has none, or when what follows the dot isn't
  /// extension-shaped — a filename like "Film (2026). Directors Cut" must not
  /// become part of the name we write to disk.
  static String sourceExtension(String filePath) {
    final slash = filePath.lastIndexOf('/');
    final dot = filePath.lastIndexOf('.');
    if (dot <= slash || dot == filePath.length - 1) return '';
    final ext = filePath.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : '';
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}
