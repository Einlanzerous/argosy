import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quality stamp read the plugin's video size, which better_player_plus
/// reports once, at the first frame — so on a ladder it froze at the opening
/// rung for the rest of the episode (ARGY-282). The start response now carries
/// the session's planned rungs; a single rung is what the picture is.
class _Server extends TranscodeApi {
  _Server() : super(ApiClient());

  /// Rungs the next start answers with; the default is a TV-shaped session.
  List<int> rungs = const [1080];

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    final at = transcodeStartRequest?.startAt ?? 0;
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
      rungs: rungs,
      progress: TranscodeProgress(outTimeMs: 0, speed: 1, fps: 30),
    );
  }

  @override
  Future<void> stopTranscode(
    String sessionId, {
    Future<void>? abortTrigger,
  }) async {}
}

PlaybackController _controller(_Server server) {
  final c = PlaybackController(
    libraryApi: LibraryApi(ApiClient()),
    transcodeApi: server,
    authApi: AuthApi(ApiClient()),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'Futurama',
    catalogDuration: 1320,
    isTranscode: true,
    hevc: false,
    hevcHardware: false,
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

  group('qualityLabelFor', () {
    test('a single rung is the stamp, whatever the first frame said', () {
      // The Sony opens a laddered title at the bottom rung for one segment;
      // with the ladder pinned to one rung, that rung is all it can play.
      expect(PlaybackController.qualityLabelFor([1080], 480), '1080p');
      expect(PlaybackController.qualityLabelFor([2160], 720), '4K');
      expect(PlaybackController.qualityLabelFor([1080], null), '1080p');
    });

    test('a ladder falls back to the plugin size', () {
      expect(PlaybackController.qualityLabelFor([1080, 720, 480], 480), '480p');
      expect(
        PlaybackController.qualityLabelFor([1080, 720, 480], null),
        isNull,
      );
    });

    test('a copy or direct play has no rungs and reads the plugin size', () {
      expect(PlaybackController.qualityLabelFor(const [], 2160), '4K');
      expect(PlaybackController.qualityLabelFor(const [], 1080), '1080p');
      expect(PlaybackController.qualityLabelFor(const [], 0), isNull);
      expect(PlaybackController.qualityLabelFor(const [], null), isNull);
    });

    test('a zero rung is not a height', () {
      expect(PlaybackController.qualityLabelFor([0], 720), '720p');
    });
  });

  group('PlaybackController', () {
    test('stamps a single-rung session from the start response', () async {
      final server = _Server()..rungs = const [1080];
      final c = _controller(server);
      addTearDown(c.dispose);

      await c.seekTo(100);

      expect(c.debugSessionRungs, [1080]);
      // No plugin size is ever reported in this rig; the rung alone decides.
      expect(c.qualityLabel, '1080p');
    });

    test('a restart adopts the new session\'s rungs', () async {
      final server = _Server()..rungs = const [2160];
      final c = _controller(server);
      addTearDown(c.dispose);

      await c.seekTo(100);
      expect(c.qualityLabel, '4K');

      // A different hint, or a hardware→software fallback, changes the plan.
      server.rungs = const [1080, 720, 480];
      await c.seekTo(200);
      expect(c.debugSessionRungs, [1080, 720, 480]);
      // Three rungs and no reported size: nothing to say yet.
      expect(c.qualityLabel, isNull);
    });

    test('a session without rungs leaves the stamp to the plugin', () async {
      final server = _Server()..rungs = const [];
      final c = _controller(server);
      addTearDown(c.dispose);

      await c.seekTo(100);

      expect(c.debugSessionRungs, isEmpty);
      expect(c.qualityLabel, isNull);
    });
  });
}
