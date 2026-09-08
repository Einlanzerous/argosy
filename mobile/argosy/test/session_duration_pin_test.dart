import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
// DurationRange is not re-exported by the package barrel; the plugin's own
// VideoPlayerController is just a ValueNotifier<VideoPlayerValue> over it.
// ignore: implementation_imports
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart'
    show DurationRange;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// better_player_plus reads ExoPlayer's duration once, on `initialized`, and
/// clamps every later seek to it — posting `finished` for the attempt. Against
/// an `event` playlist that reading is the few segments ffmpeg had written when
/// the first frame came up, so a skip-ahead a minute into a transcode snapped
/// to ~16 s and rolled into the next episode (ARGY-230). The controller now
/// overwrites that reading with the session's real length and keeps the
/// encoded-so-far estimate off it.
PlaybackController _controller({
  required bool isTranscode,
  double catalogDuration = 1431,
  String? localPath,
}) {
  final client = ApiClient();
  return PlaybackController(
    libraryApi: LibraryApi(client),
    transcodeApi: TranscodeApi(client),
    authApi: AuthApi(client),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'The Last 9 Days',
    catalogDuration: catalogDuration,
    isTranscode: isTranscode,
    hevc: false,
    subtitles: const [],
    preferredLanguages: const [],
    prefs: null,
    localPath: localPath,
  );
}

/// The plugin's value holder with no native side, seeded with the duration the
/// `initialized` event would have left in it.
ValueNotifier<VideoPlayerValue> _plugin(Duration duration) =>
    ValueNotifier(VideoPlayerValue(duration: duration));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a transcode session takes the catalog length, not the first window',
    () {
      final c = _controller(isTranscode: true);
      addTearDown(c.dispose);
      final vpc = _plugin(const Duration(seconds: 16));

      c.pinSessionDuration(vpc);

      expect(vpc.value.duration, const Duration(seconds: 1431));
    },
  );

  test('a restarted session is measured from its offset', () {
    final c = _controller(isTranscode: true)..baseOffset = 600;
    addTearDown(c.dispose);
    final vpc = _plugin(const Duration(seconds: 16));

    c.pinSessionDuration(vpc);

    expect(vpc.value.duration, const Duration(seconds: 831));
  });

  test('never shortens a session the encoder already finished', () {
    // The catalog runtime can undershoot the file by a fraction of a second;
    // trusting it over a complete playlist would chop the ending off.
    final c = _controller(isTranscode: true);
    addTearDown(c.dispose);
    final vpc = _plugin(const Duration(milliseconds: 1431200));

    c.pinSessionDuration(vpc);

    expect(vpc.value.duration, const Duration(milliseconds: 1431200));
  });

  test('an unknown catalog runtime leaves the plugin alone', () {
    final c = _controller(isTranscode: true, catalogDuration: 0);
    addTearDown(c.dispose);
    final vpc = _plugin(const Duration(seconds: 16));

    c.pinSessionDuration(vpc);

    expect(vpc.value.duration, const Duration(seconds: 16));
  });

  test('direct play and stowed files keep the reading of the whole file', () {
    for (final c in [
      _controller(isTranscode: false),
      _controller(isTranscode: true, localPath: '/stow/item-1/video.mp4'),
    ]) {
      addTearDown(c.dispose);
      final vpc = _plugin(const Duration(seconds: 1400));

      c.pinSessionDuration(vpc);

      expect(vpc.value.duration, const Duration(seconds: 1400));
    }
  });

  test('encoded-so-far floors at the first window and follows the buffer', () {
    final c = _controller(isTranscode: true);
    addTearDown(c.dispose);
    final vpc = _plugin(const Duration(seconds: 16));
    c.pinSessionDuration(vpc);

    // Nothing buffered yet: only what was written at init is known to exist.
    expect(c.encodedSoFarFrom(vpc.value), 16);

    // The buffer runs ahead; the pinned duration must not leak in as "encoded".
    vpc.value = vpc.value.copyWith(
      buffered: [DurationRange(Duration.zero, const Duration(seconds: 120))],
    );
    expect(c.encodedSoFarFrom(vpc.value), 120);
    expect(c.encodedSoFarFrom(vpc.value), lessThan(1431));
  });

  test('no player yet means nothing is encoded', () {
    final c = _controller(isTranscode: true);
    addTearDown(c.dispose);

    expect(c.encodedSoFarFrom(null), 0);
    c.pinSessionDuration(null);
  });
}
