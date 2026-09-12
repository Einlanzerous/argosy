import 'dart:async';
import 'dart:io';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/api/stream_urls.dart';
import 'package:argosy/features/stow/stow_controller.dart';
import 'package:argosy/features/stow/stow_runner.dart';
import 'package:argosy/features/stow/stow_service.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/features/stow/stowed_item.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the bytes a stow downloads, and can be told to fail outright.
class _FileServer {
  _FileServer(this.body);

  final List<int> body;
  late HttpServer _server;
  int status = HttpStatus.ok;

  /// Every path requested, in order — which items were fetched, and when.
  final hits = <String>[];

  String get base => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in _server) {
        hits.add(req.uri.path);
        if (status != HttpStatus.ok) {
          req.response.statusCode = status;
          await req.response.close();
          continue;
        }
        req.response.headers.set(HttpHeaders.etagHeader, '"v1"');
        req.response.contentLength = body.length;
        req.response.add(body);
        await req.response.close();
      }
    }());
  }

  Future<void> stop() => _server.close(force: true);
}

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
    downloadUrl: '/file/$id',
    bytes: 0,
  );
}

MediaItemDetail _detailFor(String id) => MediaItemDetail(
  id: id,
  kind: 'movie',
  title: 'Test Film',
  filePath: 'movies/Test Film (2026).mp4',
  container: 'mov,mp4,m4a,3gp,3g2,mj2',
  durationSeconds: 120,
  reviewRequired: false,
);

class _FakeLibraryApi extends LibraryApi {
  /// Ids the catalog no longer has.
  final missing = <String>{};

  /// When set, the detail fetch for [gatedId] waits until [gate] completes —
  /// a way to hold a season stow between two of its episodes.
  String? gatedId;
  Completer<void>? gate;

  @override
  Future<MediaItemDetail?> getMediaItem(
    String itemId, {
    Future<void>? abortTrigger,
  }) async {
    if (itemId == gatedId) await gate?.future;
    return missing.contains(itemId) ? null : _detailFor(itemId);
  }

  @override
  Future<List<SubtitleTrack>?> listSubtitles(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => const [];
}

void main() {
  const itemId = '11111111-2222-3333-4444-555555555555';
  final body = List<int>.generate(2048, (i) => i % 256);

  late Directory root;
  late _FileServer server;
  late StowStore store;
  late LocalStowEngine engine;
  late _FakeLibraryApi library;
  late ProviderContainer container;

  MediaItemDetail detail() => _detailFor(itemId);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-stow-ctrl');
    server = _FileServer(body);
    await server.start();
    store = StowStore(root: root);
    library = _FakeLibraryApi();
    engine = LocalStowEngine(
      store: store,
      connect: () async => StowSession(
        stow: _FakeStowApi(),
        library: library,
        urls: StreamUrls(server.base),
        baseUrl: server.base,
      ),
    );
    container = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(store),
        stowEngineProvider.overrideWithValue(engine),
        libraryApiProvider.overrideWithValue(library),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    // The controller reloads the index off the event stream; let that settle
    // before the directory underneath it is removed.
    await pumpEventQueue();
    await server.stop();
    if (await root.exists()) await root.delete(recursive: true);
  });

  StowController controller() =>
      container.read(stowControllerProvider.notifier);

  test('a finished stow leaves the item reading as stowed', () async {
    await controller().stow(detail());
    await engine.done;
    await pumpEventQueue();

    expect(controller().statusFor(itemId).phase, StowPhase.stowed);
    expect(
      (await container.read(stowedItemsProvider.future)).single.itemId,
      itemId,
      reason: 'the index the download service rewrote must be re-read',
    );
  });

  test('a failure is reported where the button will see it', () async {
    server.status = HttpStatus.unauthorized;

    await controller().stow(detail());
    await engine.done;
    await pumpEventQueue();

    expect(controller().statusFor(itemId).phase, StowPhase.failed);
  });

  test('a partial survives a restart and is reported for retry', () async {
    // What a download interrupted partway leaves behind: bytes on disk and an
    // unfinished row pointing at them.
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await store.put(
      StowedItem(
        itemId: itemId,
        title: 'Test Film',
        fileName: 'video.mp4',
        bytes: 900,
        stowedAt: DateTime.now(),
        incomplete: true,
      ),
    );

    // A fresh store + container, as a relaunch would build.
    final reopened = StowStore(root: root);
    await reopened.load();
    final fresh = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(reopened),
        stowEngineProvider.overrideWithValue(
          LocalStowEngine(store: reopened, connect: () async => throw 'unused'),
        ),
      ],
    );
    addTearDown(fresh.dispose);

    final status = fresh
        .read(stowControllerProvider.notifier)
        .statusFor(itemId);
    expect(
      status.phase,
      StowPhase.failed,
      reason: 'the button must offer Retry, not a bare Stow over hidden bytes',
    );
    expect(status.receivedBytes, 900);
  });

  test('a failure with no bytes behind it still offers Retry, and why', () async {
    // What a stow that died while the server was packaging leaves behind
    // (ARGY-231). There is nothing on disk to point at — the live status died
    // with the service — so the recorded reason is the whole trace, and without
    // it the button reads "Stow" as though nothing had ever been asked for.
    await store.put(
      StowedItem(
        itemId: itemId,
        title: 'Test Film',
        fileName: '',
        bytes: 0,
        stowedAt: DateTime.now(),
        incomplete: true,
        failure: 'The server had a problem. Try again shortly.',
      ),
    );

    final reopened = StowStore(root: root);
    await reopened.load();
    final fresh = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(reopened),
        stowEngineProvider.overrideWithValue(
          LocalStowEngine(store: reopened, connect: () async => throw 'unused'),
        ),
      ],
    );
    addTearDown(fresh.dispose);

    final status = fresh
        .read(stowControllerProvider.notifier)
        .statusFor(itemId);
    expect(status.phase, StowPhase.failed);
    expect(status.message, 'The server had a problem. Try again shortly.');
  });

  group('stowMany (ARGY-229)', () {
    const a = 'aaaaaaaa-0000-0000-0000-000000000001';
    const b = 'aaaaaaaa-0000-0000-0000-000000000002';
    const c = 'aaaaaaaa-0000-0000-0000-000000000003';
    StowEntry entry(String id) => (itemId: id, subtitleLine: 'S1 · $id');

    /// The items the server was asked for, in first-request order.
    List<String> fetched() {
      final out = <String>[];
      for (final path in server.hits) {
        if (!path.startsWith('/file/')) continue;
        final id = path.substring('/file/'.length);
        if (!out.contains(id)) out.add(id);
      }
      return out;
    }

    test('queues each file once, in order, skipping what is stowed', () async {
      await controller().stow(_detailFor(c));
      await engine.done;
      await pumpEventQueue();
      server.hits.clear();

      await controller().stowMany([
        entry(b),
        entry(a),
        entry(a), // a combined rip lists one file under several rows
        entry(c), // already on the device
      ]);
      await engine.done;
      await pumpEventQueue();

      expect(fetched(), [b, a], reason: 'once each, in the order given');
      for (final id in [a, b, c]) {
        expect(controller().statusFor(id).phase, StowPhase.stowed);
      }
      expect((await container.read(stowedItemsProvider.future)).length, 3);
    });

    test('retries an episode that failed', () async {
      server.status = HttpStatus.unauthorized;
      await controller().stow(_detailFor(a));
      await engine.done;
      await pumpEventQueue();
      expect(controller().statusFor(a).phase, StowPhase.failed);

      server.status = HttpStatus.ok;
      await controller().stowMany([entry(a), entry(b)]);
      await engine.done;
      await pumpEventQueue();

      expect(controller().statusFor(a).phase, StowPhase.stowed);
      expect(controller().statusFor(b).phase, StowPhase.stowed);
    });

    test('one missing episode fails alone; the rest of the season lands', () async {
      library.missing.add(b);

      await controller().stowMany([entry(a), entry(b), entry(c)]);
      await engine.done;
      await pumpEventQueue();

      expect(controller().statusFor(a).phase, StowPhase.stowed);
      expect(controller().statusFor(c).phase, StowPhase.stowed);
      final failed = controller().statusFor(b);
      expect(failed.phase, StowPhase.failed);
      expect(failed.message, 'That item is no longer in the library.');
      expect(fetched(), [a, c]);
    });

    test('every episode reads as in flight before the first is handed over', () async {
      library.gatedId = a;
      library.gate = Completer<void>();

      final run = controller().stowMany([entry(a), entry(b), entry(c)]);
      await pumpEventQueue();

      for (final id in [a, b, c]) {
        expect(
          controller().statusFor(id).phase,
          StowPhase.requesting,
          reason: 'a row still offering Stow looks like the button missed it',
        );
      }

      library.gate!.complete();
      await run;
      await engine.done;
      await pumpEventQueue();
      expect(fetched(), [a, b, c]);
    });

    test('an episode cancelled during its own detail fetch is not handed over', () async {
      library.gatedId = a;
      library.gate = Completer<void>();

      final run = controller().stowMany([entry(a), entry(b)]);
      await pumpEventQueue();
      await controller().cancel(a);
      await pumpEventQueue();
      expect(controller().statusFor(a).phase, StowPhase.none);

      library.gate!.complete();
      await run;
      await engine.done;
      await pumpEventQueue();

      expect(controller().statusFor(a).phase, StowPhase.none);
      expect(controller().statusFor(b).phase, StowPhase.stowed);
      expect(fetched(), [b], reason: 'the refused download must stay refused');
    });

    test('a single row cancelled during its detail fetch is not handed over', () async {
      library.gatedId = a;
      library.gate = Completer<void>();

      final run = controller().stowById(a);
      await pumpEventQueue();
      expect(controller().statusFor(a).phase, StowPhase.requesting);
      await controller().cancel(a);
      await pumpEventQueue();

      library.gate!.complete();
      await run;
      await engine.done;
      await pumpEventQueue();

      expect(controller().statusFor(a).phase, StowPhase.none);
      expect(fetched(), isEmpty);
    });

    test('an episode cancelled while waiting its turn is not handed over', () async {
      library.gatedId = a;
      library.gate = Completer<void>();

      final run = controller().stowMany([entry(a), entry(b)]);
      await pumpEventQueue();
      await controller().cancel(b);
      await pumpEventQueue();
      expect(controller().statusFor(b).phase, StowPhase.none);

      library.gate!.complete();
      await run;
      await engine.done;
      await pumpEventQueue();

      expect(controller().statusFor(a).phase, StowPhase.stowed);
      expect(controller().statusFor(b).phase, StowPhase.none);
      expect(fetched(), [a], reason: 'the refused download must stay refused');
    });
  });
}
