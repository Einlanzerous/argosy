import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/settings/settings_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in AuthApi that serves preferences from memory and can be told to
/// fail a save, so we can exercise the controller's optimistic-then-revert path
/// without a server.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi();

  DevicePreferences device = DevicePreferences(subtitleEnabled: false);
  UserPreferences user =
      UserPreferences(homeLayout: UserPreferencesHomeLayoutEnum.focused);
  bool failUserSave = false;
  int userSaves = 0;

  @override
  Future<DevicePreferences?> getDevicePreferences({Future<void>? abortTrigger}) async =>
      device;

  @override
  Future<UserPreferences?> getUserPreferences({Future<void>? abortTrigger}) async => user;

  @override
  Future<DevicePreferences?> setDevicePreferences(DevicePreferences devicePreferences,
      {Future<void>? abortTrigger}) async {
    device = devicePreferences;
    return devicePreferences;
  }

  @override
  Future<UserPreferences?> setUserPreferences(UserPreferences userPreferences,
      {Future<void>? abortTrigger}) async {
    userSaves++;
    if (failUserSave) throw Exception('save failed');
    user = userPreferences;
    return userPreferences;
  }
}

void main() {
  ProviderContainer containerWith(_FakeAuthApi fake) {
    final c = ProviderContainer(overrides: [authApiProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
    return c;
  }

  test('loads device + user preferences', () async {
    final fake = _FakeAuthApi()
      ..device = DevicePreferences(subtitleEnabled: true, captionScale: 1.25)
      ..user = UserPreferences(homeLayout: UserPreferencesHomeLayoutEnum.discovery);
    final c = containerWith(fake);

    final data = await c.read(settingsControllerProvider.future);
    expect(data.device.subtitleEnabled, isTrue);
    expect(data.device.captionScale, 1.25);
    expect(data.user.homeLayout, UserPreferencesHomeLayoutEnum.discovery);
  });

  test('falls back to defaults when the server has none', () async {
    final c = containerWith(_FakeAuthApi());
    final data = await c.read(settingsControllerProvider.future);
    expect(data.device.subtitleEnabled, isFalse);
    expect(data.user.homeLayout, UserPreferencesHomeLayoutEnum.focused);
  });

  test('a device edit changes one field and persists it', () async {
    final fake = _FakeAuthApi();
    final c = containerWith(fake);
    await c.read(settingsControllerProvider.future);

    await c.read(settingsControllerProvider.notifier).setCaptionColor('#F1C40F');

    expect(fake.device.captionColor, '#F1C40F');
    expect(c.read(settingsControllerProvider).value!.device.captionColor, '#F1C40F');
    // Unrelated fields are preserved across the rebuild.
    expect(fake.device.subtitleEnabled, isFalse);
  });

  test('a failed save reverts the optimistic state', () async {
    final fake = _FakeAuthApi()..failUserSave = true;
    final c = containerWith(fake);
    await c.read(settingsControllerProvider.future);

    await expectLater(
      c
          .read(settingsControllerProvider.notifier)
          .setHomeLayout(UserPreferencesHomeLayoutEnum.discovery),
      throwsA(isA<Exception>()),
    );

    expect(fake.userSaves, 1);
    // Reverted to the original layout after the PUT failed.
    expect(c.read(settingsControllerProvider).value!.user.homeLayout,
        UserPreferencesHomeLayoutEnum.focused);
  });
}
