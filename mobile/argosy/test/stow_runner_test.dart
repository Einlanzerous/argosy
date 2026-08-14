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

  /// Held before answering, to keep a job running long enough for another to
  /// queue up behind it.
  Duration delay = Duration.zero;

  String get base => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in _server) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
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
    bytes: 0,
  );
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

  StowRunner runner({StowQueueStore? queue}) => StowRunner(
    store: store,
    queue: queue,
    onEvent: events.add,
    connect: () async => StowSession(
      stow: _FakeStowApi(),
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
