import 'dart:async';
import 'dart:io';

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

  String get base => 'http://${_server.address.host}:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final req in _server) {
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
    downloadUrl: '/file',
    bytes: 0,
  );
}

class _FakeLibraryApi extends LibraryApi {
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
  late ProviderContainer container;

  MediaItemDetail detail() => MediaItemDetail(
    id: itemId,
    kind: 'movie',
    title: 'Test Film',
    filePath: 'movies/Test Film (2026).mp4',
    container: 'mov,mp4,m4a,3gp,3g2,mj2',
    durationSeconds: 120,
    reviewRequired: false,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-stow-ctrl');
    server = _FileServer(body);
    await server.start();
    store = StowStore(root: root);
    engine = LocalStowEngine(
      store: store,
      connect: () async => StowSession(
        stow: _FakeStowApi(),
        library: _FakeLibraryApi(),
        urls: StreamUrls(server.base),
        baseUrl: server.base,
      ),
    );
    container = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(store),
        stowEngineProvider.overrideWithValue(engine),
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
}
