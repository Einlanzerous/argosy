import 'dart:async';
import 'dart:io';

import 'package:argosy/api/stream_urls.dart';
import 'package:argosy/features/stow/stow_runner.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/features/stow/stowed_item.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the "package" bytes with range support, and can be told to fail
/// before sending anything — the shape of a retry on the link that just died.
class _FileServer {
  _FileServer(this.body);

  final List<int> body;
  late HttpServer _server;
  int status = HttpStatus.ok;

  /// Statuses to answer with before serving properly, one per request: a link
  /// that drops for a moment and comes back.
  final failures = <int>[];

  /// How many requests have arrived — how many attempts were actually made.
  int requests = 0;

  /// Held before answering, to keep a job running long enough for another to
  /// queue up behind it.
  Duration delay = Duration.zero;

  String get base => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in _server) {
        requests++;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        if (failures.isNotEmpty) {
          req.response.statusCode = failures.removeAt(0);
          await req.response.close();
          continue;
        }
        if (status != HttpStatus.ok) {
          req.response.statusCode = status;
          await req.response.close();
          continue;
        }
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        final range = req.headers.value(HttpHeaders.rangeHeader);
        var start = 0;
        if (range != null && range.startsWith('bytes=')) {
          start = int.parse(range.substring(6).split('-').first);
          req.response.statusCode = HttpStatus.partialContent;
        }
        final slice = body.sublist(start);
        req.response.contentLength = slice.length;
        req.response.add(slice);
        await req.response.close();
      }
    }());
  }

  Future<void> stop() => _server.close(force: true);
}

/// A stow endpoint that always answers "passthrough, ready" — the branch that
/// needs no packaging job, so the test exercises the download and the
/// bookkeeping rather than the queue.
class _FakeStowApi extends StowApi {
  _FakeStowApi({this.bytes = 0});

  /// What the server says the download weighs — 0 for "it didn't say", which
  /// is what turns the free-space precheck off.
  final int bytes;

  @override
  Future<StowJob?> stowItem(
    String id, {
    StowRequest? stowRequest,
    Future<void>? abortTrigger,
  }) async => StowJob(
    itemId: id,
    method: StowJobMethodEnum.passthrough,
    state: StowJobStateEnum.ready,
    downloadUrl: '/file',
    bytes: bytes,
  );
}

/// The shape a dropped link arrives in.
///
/// Not a bare [SocketException]: the generated client catches transport faults
/// and re-throws them as `ApiException(400)` with the original tucked inside
/// (`api_client.dart`), so anything reading the code alone sees a 4xx. Getting
/// this fixture wrong would test a failure mode the app never actually meets.
ApiException _transportFailure() => ApiException.withInner(
  HttpStatus.badRequest,
  'Socket operation failed: GET /api/v1/stow',
  const SocketException('Connection reset by peer'),
  StackTrace.current,
);

/// A stow endpoint that packages, and can be made to misbehave on the way.
///
/// Records how many times it was asked to package and whether the job was ever
/// released, which is how the tests tell "collected on retry" from "orphaned in
/// the spool".
class _PackagingStowApi extends StowApi {
  _PackagingStowApi(
    this.jobId, {
    this.readyAfterPolls = 1 << 30,
    this.bytes = 0,
    List<Object> pollFailures = const [],
  }) : pollFailures = [...pollFailures];

  final String jobId;

  /// The poll at which the package is reported ready. Left effectively
  /// infinite, the job packages forever — what the cancel test needs.
  final int readyAfterPolls;
  final int bytes;

  /// Thrown, one per poll, before any of the above applies.
  final List<Object> pollFailures;

  int requests = 0;
  int polls = 0;
  bool released = false;

  @override
  Future<StowJob?> stowItem(
    String id, {
    StowRequest? stowRequest,
    Future<void>? abortTrigger,
  }) async {
    requests++;
    return StowJob(
      id: jobId,
      itemId: id,
      method: StowJobMethodEnum.package,
      state: StowJobStateEnum.packaging,
      durationSeconds: 600,
    );
  }

  @override
  Future<StowJob?> getStowJob(String id, {Future<void>? abortTrigger}) async {
    polls++;
    if (pollFailures.isNotEmpty) throw pollFailures.removeAt(0);
    final ready = polls >= readyAfterPolls;
    return StowJob(
      id: jobId,
      itemId: 'x',
      method: StowJobMethodEnum.package,
      state: ready ? StowJobStateEnum.ready : StowJobStateEnum.packaging,
      downloadUrl: ready ? '/file' : null,
      bytes: ready ? bytes : null,
      progressSeconds: 12,
      durationSeconds: 600,
    );
  }

  @override
  Future<void> deleteStowJob(String id, {Future<void>? abortTrigger}) async {
    released = true;
  }
}

/// No subtitle tracks — the sidecar fetch is not what these tests are about.
class _FakeLibraryApi extends LibraryApi {
  @override
  Future<List<SubtitleTrack>?> listSubtitles(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => const [];
}

/// A queue that lives in memory but, unlike [MemoryStowQueue], actually
/// remembers — standing in for the service's persisted queue across a restart.
class _RecordingQueue implements StowQueueStore {
  List<StowJobRequest> saved = const [];

  @override
  Future<List<StowJobRequest>> load() async => saved;

  @override
  Future<void> save(List<StowJobRequest> jobs) async => saved = jobs;
}

void main() {
  const itemId = '11111111-2222-3333-4444-555555555555';
  final body = List<int>.generate(2048, (i) => i % 256);

  late Directory root;
  late _FileServer server;
  late StowStore store;
  late List<StowEvent> events;

  // `sourcePath` is what a passthrough's filename is built from. It is
  // deliberately not the item's `container`, which is ffprobe's format_name — a
  // comma-joined list of every format sharing the demuxer, not an extension. An
  // earlier version used it and wrote `video.mov,mp4,m4a,3gp,3g2,mj2` to a real
  // device.
  StowJobRequest job({String sourcePath = 'movies/Test Film (2026).mp4'}) =>
      StowJobRequest(
        itemId: itemId,
        title: 'Test Film',
        sourcePath: sourcePath,
        durationSeconds: 120,
      );

  // Three passes with no real waiting between them: the backoff's timing is
  // [StowRetryPolicy.delayFor]'s business, and sitting through it here would
  // buy nothing but a slower suite.
  const fastRetry = StowRetryPolicy(
    maxAttempts: 3,
    firstDelay: Duration(milliseconds: 1),
    maxDelay: Duration(milliseconds: 1),
  );

  StowRunner runner({
    StowQueueStore? queue,
    StowApi? stow,
    StowRetryPolicy retry = fastRetry,
    FreeSpaceProbe? freeSpace,
  }) => StowRunner(
    store: store,
    queue: queue,
    retry: retry,
    // "Can't tell" by default, so the precheck stays out of the way of tests
    // that aren't about it — and so no test forks a `df`.
    freeSpace: freeSpace ?? (_) async => null,
    onEvent: events.add,
    connect: () async => StowSession(
      stow: stow ?? _FakeStowApi(),
      library: _FakeLibraryApi(),
      urls: StreamUrls(server.base),
      baseUrl: server.base,
    ),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-stow-runner');
    server = _FileServer(body);
    await server.start();
    store = StowStore(root: root);
    events = [];
  });

  tearDown(() async {
    await server.stop();
    if (await root.exists()) await root.delete(recursive: true);
  });

  StowStatus? statusOf(String id) =>
      events.lastWhere((e) => e.itemId == id).status;

  test('a successful stow lands a complete, playable row', () async {
    final r = runner();
    await r.enqueue(job());
    await r.done;

    await store.reload();
    final entry = store.get(itemId);
    expect(entry, isNotNull, reason: 'the item should be playable offline');
    expect(entry!.incomplete, isFalse);
    expect(entry.bytes, body.length);
    expect(store.totalBytes(), body.length);
    expect(await File(await store.videoPath(entry)).readAsBytes(), body);
    expect(
      events.last.isIdle,
      isTrue,
      reason: 'the last word is "nothing left to do" — what stops the service',
    );
  });

  group('passthrough filename', () {
    test(
      'takes the extension from the source path, not the demuxer list',
      () async {
        final r = runner();
        await r.enqueue(job());
        await r.done;

        await store.reload();
        expect(
          store.get(itemId)!.fileName,
          'video.mp4',
          reason: 'container is a format_name list, never a file extension',
        );
      },
    );

    test('keeps a Matroska source as .mkv', () async {
      final r = runner();
      await r.enqueue(job(sourcePath: 'shows/Some Show/S01E01.mkv'));
      await r.done;

      await store.reload();
      expect(store.get(itemId)!.fileName, 'video.mkv');
    });

    test('falls back to mp4 when the path has no usable extension', () async {
      final r = runner();
      await r.enqueue(job(sourcePath: 'movies/Film (2026)'));
      await r.done;

      await store.reload();
      expect(store.get(itemId)!.fileName, 'video.mp4');
    });
  });

  test('a failure keeps the bytes it fetched, and says so', () async {
    // Leave a partial from an earlier attempt, then fail before a byte arrives.
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
    server.status = HttpStatus.unauthorized;

    final r = runner();
    await r.enqueue(job());
    await r.done;

    await store.reload();
    final partial = store.partial(itemId);
    expect(
      partial,
      isNotNull,
      reason: 'the bytes are on the device, so a row must account for them',
    );
    expect(
      partial!.bytes,
      900,
      reason: 'a retry that fails early must not rewrite the size to zero',
    );
    expect(store.totalBytes(), 900);
    expect(store.has(itemId), isFalse, reason: 'nothing playable yet');
    expect(statusOf(itemId)?.phase, StowPhase.failed);
  });

  test('a retry resumes and completes over its own unfinished row', () async {
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
    server.status = HttpStatus.unauthorized;
    final first = runner();
    await first.enqueue(job());
    await first.done;

    server.status = HttpStatus.ok;
    final second = runner();
    await second.enqueue(job());
    await second.done;

    await store.reload();
    expect(store.list().length, 1, reason: 'one row, not two');
    expect(store.has(itemId), isTrue);
    expect(store.get(itemId)!.bytes, body.length);
    expect(
      await File(await store.videoPath(store.get(itemId)!)).readAsBytes(),
      body,
      reason: 'the resumed half must join the existing half exactly',
    );
  });

  test('cancelling during packaging releases the job on the server', () async {
    // Otherwise the phone stops polling and the server keeps encoding to the
    // end — on a 39 GB remux that is twenty minutes of GPU for a file nobody
    // will collect. Verified on device: the cancel had no DELETE behind it.
    final stowApi = _PackagingStowApi('job-1');
    final r = runner(stow: stowApi);

    await r.enqueue(job());
    // Let it reach the polling loop.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      r.statuses[itemId]?.phase,
      StowPhase.packaging,
      reason: 'the test needs it parked in the packaging wait',
    );

    await r.cancel(itemId);

    expect(
      stowApi.released,
      isTrue,
      reason: "the server's job must be released, not abandoned mid-encode",
    );
    expect(r.isIdle, isTrue);
    await store.reload();
    expect(store.list(), isEmpty, reason: 'nothing half-written left behind');
  });

  test('cancel frees the bytes and leaves no row', () async {
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    server.status = HttpStatus.unauthorized;
    final r = runner();
    await r.enqueue(job());
    await r.done;

    await r.cancel(itemId);

    await store.reload();
    expect(store.list(), isEmpty);
    expect(store.totalBytes(), 0);
    expect(await Directory('${root.path}/$itemId').exists(), isFalse);
  });

  // A transient network fault used to fail a job outright, and the queue behind
  // it with it: Bleach S17 lost E14–E18 to about forty seconds of dead air,
  // with E19 onward landing normally (ARGY-231).
  group('a blip on the link', () {
    bool sawPhase(StowPhase phase) => events.any(
      (e) => e.itemId == itemId && e.status?.phase == phase,
    );

    test('is ridden out, and the stow completes', () async {
      server.failures.addAll([
        HttpStatus.serviceUnavailable,
        HttpStatus.badGateway,
      ]);

      final r = runner();
      await r.enqueue(job());
      await r.done;

      await store.reload();
      expect(store.has(itemId), isTrue, reason: 'the third attempt landed');
      expect(store.get(itemId)!.bytes, body.length);
      expect(
        sawPhase(StowPhase.retrying),
        isTrue,
        reason: 'and it said so rather than sitting on "Preparing…"',
      );
      expect(sawPhase(StowPhase.failed), isFalse);
    });

    test('during packaging is retried, and the package collected', () async {
      // E14 exactly: the poll died on a transport error while the server
      // carried on encoding. The retry re-POSTs, is handed the same job back —
      // the server keys them by (account, item) — and collects the package that
      // was made while the phone wasn't looking.
      final stowApi = _PackagingStowApi(
        'job-poll',
        readyAfterPolls: 2,
        bytes: body.length,
        pollFailures: [_transportFailure()],
      );

      final r = runner(stow: stowApi);
      await r.enqueue(job());
      await r.done;

      await store.reload();
      expect(store.has(itemId), isTrue);
      expect(stowApi.requests, 2, reason: 'the retry asks again');
      expect(
        stowApi.released,
        isTrue,
        reason: 'collected, then released — no 1.1 GB orphan in the spool',
      );
    });

    test('that never lifts gives up after a bounded number of goes', () async {
      server.status = HttpStatus.serviceUnavailable;

      final r = runner();
      await r.enqueue(job());
      await r.done;

      expect(
        server.requests,
        3,
        reason: 'three attempts and no more — a dead link is not a reason to '
            'hold a foreground service open all afternoon',
      );
      expect(statusOf(itemId)?.phase, StowPhase.failed);
    });

    test('is told apart from a refusal, which fails at once', () async {
      // A revoked token answers the same way every time; retrying it only
      // delays the message that the device needs to pair again.
      server.status = HttpStatus.unauthorized;

      final r = runner();
      await r.enqueue(job());
      await r.done;

      expect(server.requests, 1);
      expect(statusOf(itemId)?.phase, StowPhase.failed);
    });

    test('can be cancelled mid-backoff without waiting it out', () async {
      server.status = HttpStatus.serviceUnavailable;
      final r = runner(
        retry: const StowRetryPolicy(
          maxAttempts: 3,
          firstDelay: Duration(minutes: 5),
          maxDelay: Duration(minutes: 5),
        ),
      );
      await r.enqueue(job());
      while (r.statuses[itemId]?.phase != StowPhase.retrying) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // If the wait weren't interruptible this would sit here for five
      // minutes and the test would time out.
      await r.cancel(itemId);
      await r.done;

      expect(r.isIdle, isTrue);
      await store.reload();
      expect(store.list(), isEmpty);
    });
  });

  group('a failure that sticks', () {
    test('is written to the index, and survives a relaunch', () async {
      // The packaging phase is where this mattered most: `started` is only
      // assigned once a download URL comes back, so a failure before that wrote
      // no row at all — and after a relaunch the season button offered a plain
      // "Stow season" over episodes that had silently failed.
      final stowApi = _PackagingStowApi(
        'job-gone',
        pollFailures: [ApiException(HttpStatus.notFound, 'not found')],
      );

      final r = runner(stow: stowApi);
      await r.enqueue(job());
      await r.done;

      expect(
        stowApi.released,
        isTrue,
        reason: 'nothing is coming back for it, so it must not be left behind',
      );

      // A fresh store over the same directory, as a relaunch would build.
      final reopened = StowStore(root: root);
      await reopened.load();
      final row = reopened.partial(itemId);
      expect(
        row,
        isNotNull,
        reason: 'a failure with no bytes behind it is still a failure',
      );
      expect(row!.failure, 'Not found.');
      expect(row.bytes, 0);
      expect(reopened.has(itemId), isFalse, reason: 'nothing playable');
    });

    test('records why, alongside the bytes it did fetch', () async {
      final dir = await store.itemDir(itemId);
      await File(
        '${dir.path}/video.mp4.part',
      ).writeAsBytes(body.sublist(0, 900));
      await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
      server.status = HttpStatus.unauthorized;

      final r = runner();
      await r.enqueue(job());
      await r.done;

      final reopened = StowStore(root: root);
      await reopened.load();
      final row = reopened.partial(itemId)!;
      expect(row.bytes, 900, reason: 'the partial is kept for the retry');
      expect(row.failure, isNotNull);
    });

    test('is cleared by the retry that works', () async {
      server.status = HttpStatus.unauthorized;
      final first = runner();
      await first.enqueue(job());
      await first.done;
      expect(store.partial(itemId)?.failure, isNotNull);

      server.status = HttpStatus.ok;
      final second = runner();
      await second.enqueue(job());
      await second.done;

      await store.reload();
      expect(store.has(itemId), isTrue);
      expect(store.get(itemId)!.failure, isNull);
    });
  });

  group('free space', () {
    test('is checked before a byte is written, and says the numbers', () async {
      final r = runner(
        stow: _FakeStowApi(bytes: body.length),
        freeSpace: (_) async => 4096,
      );
      await r.enqueue(job());
      await r.done;

      expect(server.requests, 0, reason: 'it never got as far as the transfer');
      final status = statusOf(itemId);
      expect(status?.phase, StowPhase.failed);
      expect(status?.message, contains('Not enough space'));
      expect(status?.message, contains('4.0 KB free'));

      await store.reload();
      expect(store.partial(itemId)?.failure, contains('Not enough space'));
      expect(
        await File('${root.path}/$itemId/video.mp4.part').exists(),
        isFalse,
      );
    });

    test('being unanswerable is never a reason not to download', () async {
      final r = runner(
        stow: _FakeStowApi(bytes: body.length),
        freeSpace: (_) async => null,
      );
      await r.enqueue(job());
      await r.done;

      await store.reload();
      expect(store.has(itemId), isTrue);
    });

    test('is read off df where there is one to read', () async {
      final free = await probeFreeSpace(root);
      // Elsewhere — iOS refuses to run a subprocess at all — null is the right
      // answer and the caller proceeds unchecked.
      if (!Platform.isLinux && !Platform.isMacOS) return;
      expect(free, isNotNull);
      expect(free, greaterThan(0));
    });
  });

  group('the queue', () {
    const otherId = '99999999-8888-7777-6666-555555555555';

    test('runs jobs one after another', () async {
      final r = runner();
      await r.enqueue(job());
      await r.enqueue(
        StowJobRequest(
          itemId: otherId,
          title: 'Second Film',
          sourcePath: 'movies/Second.mkv',
        ),
      );
      await r.done;

      await store.reload();
      expect(store.has(itemId), isTrue);
      expect(store.has(otherId), isTrue);
    });

    test('starts no second download for something already queued', () async {
      final r = runner();
      await r.enqueue(job());
      await r.enqueue(job());
      await r.done;

      await store.reload();
      expect(store.list().length, 1);
    });

    test('but does answer that request, rather than going quiet', () async {
      // Silence here is indistinguishable, to the service handshake, from the
      // message never arriving — so it retries, times out twice, and reports a
      // failure for a download that is queued and perfectly healthy. The window
      // is a relaunch while something sits queued: no live status, and no index
      // row either, so the button offers a plain Stow.
      server.delay = const Duration(milliseconds: 300);
      final second = StowJobRequest(
        itemId: otherId,
        title: 'Second Film',
        sourcePath: 'movies/Second.mkv',
      );
      final r = runner();
      await r.enqueue(job()); // becomes active, and stays there a while
      await r.enqueue(second); // queued behind it

      // Counted per item, not overall: the *active* job is emitting progress
      // the whole time, and those ticks would satisfy a looser assertion
      // without the queued one ever being answered.
      int answers() => events.where((e) => e.itemId == otherId).length;
      final before = answers();
      await r.enqueue(second);
      expect(
        answers(),
        greaterThan(before),
        reason: 'a duplicate must be acknowledged, not swallowed',
      );
      expect(
        events.lastWhere((e) => e.itemId == otherId).status?.phase,
        StowPhase.requesting,
      );

      server.delay = Duration.zero;
      await r.done;
    });

    test('empties itself once the work is done', () async {
      final queue = _RecordingQueue();
      final r = runner(queue: queue);
      await r.enqueue(job());
      await r.done;

      expect(
        queue.saved,
        isEmpty,
        reason: 'a finished job must not be resumed by the next restart',
      );
    });

    test('is picked up again by a runner that restarts', () async {
      // What the service leaves behind when the system reclaims it mid-download.
      final queue = _RecordingQueue()..saved = [job()];

      final restarted = runner(queue: queue);
      await restarted.restore();
      await restarted.done;

      await store.reload();
      expect(
        store.has(itemId),
        isTrue,
        reason: 'an interrupted download resumes without being asked again',
      );
      expect(queue.saved, isEmpty);
    });
  });
}
