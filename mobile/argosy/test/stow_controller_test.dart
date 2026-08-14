import 'dart:async';
import 'dart:io';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/stow/stow_controller.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/features/stow/stowed_item.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves the "package" bytes with range support, and can be told to fail
/// before sending anything — the shape of a retry on the link that just died.
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
/// needs no packaging job, so the test exercises the download and the bookkeeping
/// rather than the queue.
class _FakeStowApi extends StowApi {
  _FakeStowApi(this.itemId);

  final String itemId;

  @override
  Future<StowJob?> stowItem(
    String id, {
    StowRequest? stowRequest,
    Future<void>? abortTrigger,
  }) async => StowJob(
    itemId: itemId,
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

void main() {
  const itemId = '11111111-2222-3333-4444-555555555555';
  final body = List<int>.generate(2048, (i) => i % 256);

  late Directory root;
  late _FileServer server;
  late StowStore store;
  late ProviderContainer container;

  MediaItemDetail detail() => MediaItemDetail(
    id: itemId,
    kind: 'movie',
    title: 'Test Film',
    filePath: 'film.mp4',
    container: 'mp4',
    durationSeconds: 120,
    reviewRequired: false,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-stow-ctrl');
    server = _FileServer(body);
    await server.start();
    store = StowStore(root: root);
    container = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(store),
        stowApiProvider.overrideWithValue(_FakeStowApi(itemId)),
        libraryApiProvider.overrideWithValue(_FakeLibraryApi()),
        baseUrlProvider.overrideWith(() => _StaticBaseUrl(server.base)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await server.stop();
    if (await root.exists()) await root.delete(recursive: true);
  });

  StowController controller() =>
      container.read(stowControllerProvider.notifier);

  test('a successful stow lands a complete, playable row', () async {
    await controller().stow(detail());

    await store.load();
    final entry = store.get(itemId);
    expect(entry, isNotNull, reason: 'the item should be playable offline');
    expect(entry!.incomplete, isFalse);
    expect(entry.bytes, body.length);
    expect(store.totalBytes(), body.length);
    expect(await File(await store.videoPath(entry)).readAsBytes(), body);
  });

  test('a failure keeps the bytes it fetched, and says so', () async {
    // Leave a partial from an earlier attempt, then fail before a byte arrives.
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
    server.status = HttpStatus.unauthorized;

    await controller().stow(detail());

    await store.load();
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
    expect(controller().statusFor(itemId).phase, StowPhase.failed);
  });

  test('a partial survives a restart and is reported for retry', () async {
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
    server.status = HttpStatus.unauthorized;
    await controller().stow(detail());

    // A fresh store + controller, as a relaunch would build.
    final reopened = StowStore(root: root);
    final fresh = ProviderContainer(
      overrides: [
        stowStoreProvider.overrideWithValue(reopened),
        stowApiProvider.overrideWithValue(_FakeStowApi(itemId)),
        libraryApiProvider.overrideWithValue(_FakeLibraryApi()),
        baseUrlProvider.overrideWith(() => _StaticBaseUrl(server.base)),
      ],
    );
    addTearDown(fresh.dispose);
    await reopened.load();

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

  test('a retry resumes and completes over its own unfinished row', () async {
    final dir = await store.itemDir(itemId);
    await File('${dir.path}/video.mp4.part').writeAsBytes(body.sublist(0, 900));
    await File('${dir.path}/video.mp4.part.etag').writeAsString('"v1"');
    server.status = HttpStatus.unauthorized;
    await controller().stow(detail());

    server.status = HttpStatus.ok;
    await controller().stow(detail());

    await store.load();
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
    await controller().stow(detail());

    await controller().cancel(itemId);

    await store.load();
    expect(store.list(), isEmpty);
    expect(store.totalBytes(), 0);
    expect(await Directory('${root.path}/$itemId').exists(), isFalse);
  });
}

/// Pins the base URL at the test server, standing in for a paired household.
class _StaticBaseUrl extends BaseUrlController {
  _StaticBaseUrl(this._url);
  final String _url;
  @override
  String build() => _url;
}
