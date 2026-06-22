import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../home/home_providers.dart';

/// The two preference scopes the Settings screen edits: per-device playback
/// prefs (`/api/v1/preferences`) and per-user account prefs
/// (`/api/v1/user/preferences`). Bundled so the screen has one async state.
typedef SettingsData = ({DevicePreferences device, UserPreferences user});

/// Loads device + user preferences and persists edits. Saves are optimistic —
/// the UI updates immediately and reverts if the PUT fails — mirroring the web
/// settings view. Changing the home layout invalidates the Bridge so it
/// re-renders in the new layout without a manual refresh.
class SettingsController extends AsyncNotifier<SettingsData> {
  @override
  Future<SettingsData> build() async {
    final auth = ref.watch(authApiProvider);
    final results = await Future.wait([
      auth.getDevicePreferences().then<Object?>((v) => v).catchError((_) => null),
      auth.getUserPreferences().then<Object?>((v) => v).catchError((_) => null),
    ]);
    final device = results[0] as DevicePreferences? ??
        DevicePreferences(subtitleEnabled: false);
    final user = results[1] as UserPreferences? ??
        UserPreferences(homeLayout: UserPreferencesHomeLayoutEnum.focused);
    return (device: device, user: user);
  }

  Future<void> _saveDevice(DevicePreferences next) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData((device: next, user: current.user)); // optimistic
    try {
      await ref.read(authApiProvider).setDevicePreferences(next);
    } catch (_) {
      state = AsyncData(current); // revert on failure
      rethrow;
    }
  }

  // Each device mutator rebuilds the whole DevicePreferences from the current
  // one (the generated model has no copyWith) and persists it.
  DevicePreferences get _device => state.value!.device;

  Future<void> setSubtitlesEnabled(bool enabled) => _saveDevice(DevicePreferences(
        subtitleEnabled: enabled,
        subtitleLanguage: _device.subtitleLanguage,
        audioLanguage: _device.audioLanguage,
        captionScale: _device.captionScale,
        captionColor: _device.captionColor,
        captionBackground: _device.captionBackground,
      ));

  Future<void> setSubtitleLanguage(String? language) => _saveDevice(DevicePreferences(
        subtitleEnabled: _device.subtitleEnabled,
        subtitleLanguage: language,
        audioLanguage: _device.audioLanguage,
        captionScale: _device.captionScale,
        captionColor: _device.captionColor,
        captionBackground: _device.captionBackground,
      ));

  Future<void> setCaptionScale(double scale) => _saveDevice(DevicePreferences(
        subtitleEnabled: _device.subtitleEnabled,
        subtitleLanguage: _device.subtitleLanguage,
        audioLanguage: _device.audioLanguage,
        captionScale: scale,
        captionColor: _device.captionColor,
        captionBackground: _device.captionBackground,
      ));

  Future<void> setCaptionColor(String hex) => _saveDevice(DevicePreferences(
        subtitleEnabled: _device.subtitleEnabled,
        subtitleLanguage: _device.subtitleLanguage,
        audioLanguage: _device.audioLanguage,
        captionScale: _device.captionScale,
        captionColor: hex,
        captionBackground: _device.captionBackground,
      ));

  Future<void> setCaptionBackground(DevicePreferencesCaptionBackgroundEnum bg) =>
      _saveDevice(DevicePreferences(
        subtitleEnabled: _device.subtitleEnabled,
        subtitleLanguage: _device.subtitleLanguage,
        audioLanguage: _device.audioLanguage,
        captionScale: _device.captionScale,
        captionColor: _device.captionColor,
        captionBackground: bg,
      ));

  Future<void> setHomeLayout(UserPreferencesHomeLayoutEnum layout) async {
    final current = state.value;
    if (current == null) return;
    final next = UserPreferences(homeLayout: layout);
    state = AsyncData((device: current.device, user: next)); // optimistic
    try {
      await ref.read(authApiProvider).setUserPreferences(next);
      ref.invalidate(homeDataProvider); // Bridge re-renders in the new layout
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsData>(SettingsController.new);
