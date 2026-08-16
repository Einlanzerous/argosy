import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Up Next countdown is a timer started when the card opens, not a function
/// of the playhead (ARGY-207). The old formula — `remaining - tailSeconds` —
/// only produced the intended 15s on a straight playthrough, where the card
/// happens to open exactly that far ahead of the roll-over point. Seeking into
/// the window handed out whatever was left of the difference: 14s, 5s, 1s, and
/// past the roll-over point no card at all, just an unexplained jump into the
/// next episode.
///
/// `catalogDuration - position` is what decides the window, and with no player
/// attached `position` collapses to `baseOffset` — so these drive the playhead by
/// setting it, the same way a seek would.
const _duration = 1320.0; // 22 min

PlaybackController _controller() {
  final client = ApiClient();
  final c = PlaybackController(
    libraryApi: LibraryApi(client),
    transcodeApi: TranscodeApi(client),
    authApi: AuthApi(client),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'The Series Has Landed',
    catalogDuration: _duration,
    isTranscode: true,
    hevc: false,
    subtitles: const [],
    preferredLanguages: const [],
    prefs: null,
  );
  c.nextEpisode = OnDeckItem(
    id: 'next-1',
    seriesId: 'series-1',
    seriesTitle: 'Futurama',
    seasonNumber: 1,
    episodeNumber: 2,
  );
  return c;
}

/// Puts the playhead [remaining] seconds from the end and runs the tick that
/// each player's repaint loop drives.
void _seekToRemaining(PlaybackController c, double remaining) {
  c.baseOffset = _duration - remaining;
  c.maybeAdvance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the card opens with a full countdown wherever you land in the window', () {
    // 39s used to give 14s, 26s gave 1s, and anything at or past 25s gave no
    // card at all — it advanced on the spot.
    for (final remaining in <double>[39, 30, 26, 25, 20, 2]) {
      final c = _controller();
      addTearDown(c.dispose);

      _seekToRemaining(c, remaining);

      expect(c.upNextOpen, isTrue, reason: 'no card at ${remaining}s remaining');
      expect(
        c.upNextCountdown,
        PlaybackController.upNextCountdownSeconds,
        reason: 'truncated countdown at ${remaining}s remaining',
      );
    }
  });

  test('landing past the end of the file still prompts rather than jumping', () {
    final c = _controller();
    addTearDown(c.dispose);

    _seekToRemaining(c, 0);

    expect(c.upNextOpen, isTrue);
    expect(c.upNextCountdown, PlaybackController.upNextCountdownSeconds);
  });

  test('outside the window there is no card', () {
    final c = _controller();
    addTearDown(c.dispose);

    _seekToRemaining(c, PlaybackController.upNextLeadSeconds + 1);

    expect(c.upNextOpen, isFalse);
  });

  test('seeking back out of the window retracts it', () {
    final c = _controller();
    addTearDown(c.dispose);

    _seekToRemaining(c, 20);
    expect(c.upNextOpen, isTrue);

    _seekToRemaining(c, 600);
    expect(c.upNextOpen, isFalse);
  });

  test('the countdown holds while playback is not running', () async {
    final c = _controller();
    addTearDown(c.dispose);

    _seekToRemaining(c, 20);
    expect(c.upNextCountdown, PlaybackController.upNextCountdownSeconds);

    // Real elapsed time, well past the 250ms tick. The old countdown froze on
    // pause for free by being position-derived; a wall-clock timer that ignored
    // playback state would roll the episode over while the viewer was away.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(c.upNextCountdown, PlaybackController.upNextCountdownSeconds);
    expect(c.upNextOpen, isTrue);
  });

  test('cancel closes the card and keeps it closed', () {
    final c = _controller();
    addTearDown(c.dispose);

    _seekToRemaining(c, 30);
    expect(c.upNextOpen, isTrue);

    c.cancelUpNext();
    expect(c.upNextOpen, isFalse);

    _seekToRemaining(c, 20);
    expect(c.upNextOpen, isFalse);
  });

  test('auto-advance off means no card at all', () {
    final c = _controller()
      ..prefs = DevicePreferences(
        subtitleEnabled: false,
        seriesAutoAdvance: false,
      );
    addTearDown(c.dispose);

    _seekToRemaining(c, 20);

    expect(c.upNextOpen, isFalse);
  });
}
