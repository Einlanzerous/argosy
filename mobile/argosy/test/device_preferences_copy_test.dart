import 'package:argosy/api/device_preferences_copy.dart';
import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_test/flutter_test.dart';

/// `setDevicePreferences` is last-wins over the whole object, so a partial save
/// that forgets a field writes `null` over it rather than leaving it alone.
/// `_savePreferredSubtitle` forgot `captionPosition`, so changing subtitle track
/// mid-playback wiped the viewer's caption placement and persisted the loss
/// (ARGY-208). Both player saves now clone the current preferences and set only
/// what they own.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi();

  final List<DevicePreferences> saved = <DevicePreferences>[];

  @override
  Future<DevicePreferences?> setDevicePreferences(
    DevicePreferences devicePreferences, {
    Future<void>? abortTrigger,
  }) async {
    saved.add(devicePreferences);
    return devicePreferences;
  }
}

/// Every field non-default, so a dropped one is visible as a null rather than
/// coinciding with the value it should have had.
DevicePreferences _fullPrefs() => DevicePreferences(
  subtitleEnabled: true,
  subtitleLanguage: 'ja',
  audioLanguage: 'en',
  captionScale: 1.5,
  captionColor: '#ff0000',
  captionBackground: DevicePreferencesCaptionBackgroundEnum.solid,
  captionPosition: DevicePreferencesCaptionPositionEnum.higher,
  seriesAutoAdvance: false,
);

SubtitleTrack _track(String id, String language) => SubtitleTrack(
  id: id,
  source_: SubtitleTrackSource_Enum.embedded,
  language: language,
  label: language.toUpperCase(),
  forced: false,
  default_: false,
);

PlaybackController _controller(_FakeAuthApi auth, DevicePreferences? prefs) {
  final client = ApiClient();
  return PlaybackController(
    libraryApi: LibraryApi(client),
    transcodeApi: TranscodeApi(client),
    authApi: auth,
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'Redline',
    catalogDuration: 1320,
    isTranscode: true,
    hevc: false,
    subtitles: <SubtitleTrack>[
      _track('embedded:2', 'en'),
      _track('embedded:3', 'ja'),
    ],
    preferredLanguages: const <String>[],
    prefs: prefs,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copy()', () {
    test('carries every field', () {
      final original = _fullPrefs();
      final clone = original.copy();

      expect(clone.subtitleEnabled, isTrue);
      expect(clone.subtitleLanguage, 'ja');
      expect(clone.audioLanguage, 'en');
      expect(clone.captionScale, 1.5);
      expect(clone.captionColor, '#ff0000');
      expect(
        clone.captionBackground,
        DevicePreferencesCaptionBackgroundEnum.solid,
      );
      expect(
        clone.captionPosition,
        DevicePreferencesCaptionPositionEnum.higher,
      );
      expect(clone.seriesAutoAdvance, isFalse);
      expect(clone, original); // the generated model compares field-wise
    });

    test(
      'is a clone, not an alias — mutating it leaves the original alone',
      () {
        final original = _fullPrefs();
        final clone = original.copy()..captionScale = 2.0;

        expect(clone.captionScale, 2.0);
        expect(original.captionScale, 1.5);
      },
    );

    test(
      'a cascade can clear a nullable field, which copyWith could not express',
      () {
        final cleared = _fullPrefs().copy()..subtitleLanguage = null;

        expect(cleared.subtitleLanguage, isNull);
        expect(
          cleared.captionPosition,
          DevicePreferencesCaptionPositionEnum.higher,
        );
      },
    );
  });

  group('selectSubtitle persistence', () {
    test(
      'preserves caption position and every other unrelated field',
      () async {
        final auth = _FakeAuthApi();
        final c = _controller(auth, _fullPrefs());
        addTearDown(c.dispose);

        await c.selectSubtitle('embedded:2');
        await pumpEventQueue();

        expect(auth.saved, hasLength(1));
        final saved = auth.saved.single;
        // The regression: this was null before ARGY-208.
        expect(
          saved.captionPosition,
          DevicePreferencesCaptionPositionEnum.higher,
        );
        // Everything else the save does not own rides along too.
        expect(saved.captionScale, 1.5);
        expect(saved.captionColor, '#ff0000');
        expect(
          saved.captionBackground,
          DevicePreferencesCaptionBackgroundEnum.solid,
        );
        expect(saved.audioLanguage, 'en');
        expect(saved.seriesAutoAdvance, isFalse);
        // ...and what it does own is written.
        expect(saved.subtitleEnabled, isTrue);
        expect(saved.subtitleLanguage, 'en');
      },
    );

    test(
      'turning subtitles off keeps the caption position for next time',
      () async {
        final auth = _FakeAuthApi();
        final c = _controller(auth, _fullPrefs());
        addTearDown(c.dispose);

        await c.selectSubtitle(null);
        await pumpEventQueue();

        final saved = auth.saved.single;
        expect(saved.subtitleEnabled, isFalse);
        expect(
          saved.captionPosition,
          DevicePreferencesCaptionPositionEnum.higher,
        );
        // An unknown track leaves the remembered language in place.
        expect(saved.subtitleLanguage, 'ja');
      },
    );

    test('survives having no stored preferences at all', () async {
      final auth = _FakeAuthApi();
      final c = _controller(auth, null);
      addTearDown(c.dispose);

      await c.selectSubtitle('embedded:3');
      await pumpEventQueue();

      final saved = auth.saved.single;
      expect(saved.subtitleEnabled, isTrue);
      expect(saved.subtitleLanguage, 'ja');
      expect(saved.captionPosition, isNull);
    });
  });
}
