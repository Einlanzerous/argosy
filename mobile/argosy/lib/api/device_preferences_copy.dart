import 'package:argosy_api/api.dart';

/// A field-for-field clone of a [DevicePreferences], so a partial save can
/// change one setting without restating the other seven.
///
/// The generated model has no `copyWith`, so every partial save used to rebuild
/// the whole object by hand. Nothing caught a dropped field, and one was
/// dropped: `_savePreferredSubtitle` omitted `captionPosition`, so picking a
/// different subtitle track mid-playback silently reset the viewer's caption
/// placement (ARGY-208). `setDevicePreferences` is last-wins over the whole
/// object, which makes an omission a write of `null` rather than a no-op.
///
/// Clone and mutate instead, so the field list exists in exactly one place:
///
/// ```dart
/// final next = prefs.copy()..captionPosition = pos;
/// ```
///
/// A cascade rather than a `copyWith` of optional named parameters, because
/// only the cascade keeps `null` meaningful: `..subtitleLanguage = null` clears
/// the preference, which `copyWith(subtitleLanguage: null)` cannot distinguish
/// from "leave it alone" without a sentinel. `setSubtitleLanguage(null)` is a
/// real call, so that distinction has to survive.
extension DevicePreferencesCopy on DevicePreferences {
  DevicePreferences copy() => DevicePreferences(
    subtitleLanguage: subtitleLanguage,
    subtitleEnabled: subtitleEnabled,
    audioLanguage: audioLanguage,
    captionScale: captionScale,
    captionColor: captionColor,
    captionBackground: captionBackground,
    captionPosition: captionPosition,
    seriesAutoAdvance: seriesAutoAdvance,
  );
}
