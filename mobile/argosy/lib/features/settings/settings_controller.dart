import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../api/device_preferences_copy.dart';
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

  // Each device mutator clones the current preferences and sets only its own
  // field, so adding a preference cannot silently drop it here (ARGY-208).
  DevicePreferences get _device => state.value!.device;

  Future<void> setSubtitlesEnabled(bool enabled) =>
      _saveDevice(_device.copy()..subtitleEnabled = enabled);

  Future<void> setSubtitleLanguage(String? language) =>
      _saveDevice(_device.copy()..subtitleLanguage = language);

  Future<void> setCaptionScale(double scale) =>
      _saveDevice(_device.copy()..captionScale = scale);

  Future<void> setCaptionColor(String hex) =>
      _saveDevice(_device.copy()..captionColor = hex);

  Future<void> setCaptionBackground(DevicePreferencesCaptionBackgroundEnum bg) =>
      _saveDevice(_device.copy()..captionBackground = bg);

  Future<void> setCaptionPosition(DevicePreferencesCaptionPositionEnum pos) =>
      _saveDevice(_device.copy()..captionPosition = pos);

  Future<void> setSeriesAutoAdvance(bool enabled) =>
      _saveDevice(_device.copy()..seriesAutoAdvance = enabled);

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
