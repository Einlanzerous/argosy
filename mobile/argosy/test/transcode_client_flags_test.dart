import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// The transcode request carries the client's capability flags and ladder
/// hints (ARGY-275, item 1 of the ARGY-179 plan). They are constructor-final on
/// the controller and sent from the one POST builder, so every restart — seek,
/// recovery, next episode — negotiates the same output and the same session
/// key as the first start.
class _Server extends TranscodeApi {
  _Server() : super(ApiClient());

  final requests = <TranscodeStartRequest>[];

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    requests.add(transcodeStartRequest!);
    final at = transcodeStartRequest.startAt ?? 0;
    await Future<void>.delayed(Duration.zero);
    final id = 's${at.floor()}';
    return TranscodeSession(
      id: id,
      itemId: itemId,
      encoder: 'x264',
      method: TranscodeSessionMethodEnum.transcode,
      state: TranscodeSessionStateEnum.running,
      startAt: at,
      startedAt: DateTime.now(),
      playlistUrl: '/p/$id',
      progress: TranscodeProgress(outTimeMs: 0, speed: 1, fps: 30),
    );
  }

  @override
  Future<void> stopTranscode(
    String sessionId, {
    Future<void>? abortTrigger,
  }) async {}
}

PlaybackController _controller(
  _Server server, {
  required bool hevcHardware,
  int? minHeight,
  int? maxHeight,
}) {
  final c = PlaybackController(
    libraryApi: LibraryApi(ApiClient()),
    transcodeApi: server,
    authApi: AuthApi(ApiClient()),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'Scrubs',
    catalogDuration: 1440,
    isTranscode: true,
    hevc: true,
    hevcHardware: hevcHardware,
    minHeight: minHeight,
    maxHeight: maxHeight,
    subtitles: const [],
    preferredLanguages: const [],
    prefs: null,
  );
  c.debugProbe = (url, cancelled) async => true;
  c.debugAttach = (url) async {};
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit flags and hints ride the first request and a restart',
    () async {
      final server = _Server();
      final c = _controller(
        server,
        hevcHardware: true,
        minHeight: 1080,
        maxHeight: 1080,
      );
      addTearDown(c.dispose);

      await c.seekTo(100);
      expect(server.requests, hasLength(1));
      final first = server.requests.single;
      expect(first.startAt, 100);
      expect(first.hevc, isTrue);
      expect(first.hevcHardware, isTrue);
      expect(first.minHeight, 1080);
      expect(first.maxHeight, 1080);

      // A seek past the encoded range tears the session down and POSTs again;
      // the restart must negotiate exactly what the first start did.
      await c.seekTo(500);
      expect(server.requests, hasLength(2));
      final restart = server.requests.last;
      expect(restart.startAt, 500);
      expect(restart.hevc, isTrue);
      expect(restart.hevcHardware, isTrue);
      expect(restart.minHeight, 1080);
      expect(restart.maxHeight, 1080);
    },
  );

  test('false and null leave the hints unset', () async {
    final server = _Server();
    final c = _controller(server, hevcHardware: false);
    addTearDown(c.dispose);

    await c.seekTo(100);
    final req = server.requests.single;
    expect(req.hevc, isTrue);
    expect(req.hevcHardware, isFalse);
    // The generated toJson serialises these as JSON null, which the server
    // reads as absent — so the check is on the model, not on key absence.
    expect(req.minHeight, isNull);
    expect(req.maxHeight, isNull);
  });
}
