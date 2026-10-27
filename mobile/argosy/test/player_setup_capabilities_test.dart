import 'dart:io';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/player/player_providers.dart';
import 'package:argosy/features/stow/stow_controller.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/platform/device_capabilities.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `playerSetupProvider` carries the device's capability flags into the
/// [PlayerSetup] the screens hand the controller (ARGY-275). The channel is
/// unreachable under `flutter test` (`Platform.isAndroid` is false on the
/// runner), so the probes are seeded through `DeviceCapabilities.debugOverride`.
const _itemId = 'item-1';

class _FakeLibraryApi extends LibraryApi {
  _FakeLibraryApi() : super(ApiClient());

  @override
  Future<MediaItemDetail?> getMediaItem(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => MediaItemDetail(
    id: itemId,
    kind: 'movie',
    title: 'Test Film',
    filePath: 'movies/Test Film (2026).mkv',
    durationSeconds: 120,
    reviewRequired: false,
  );

  @override
  Future<PlaybackInfo?> getPlaybackInfo(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => PlaybackInfo(
    directPlay: false,
    method: PlaybackInfoMethodEnum.transcode,
    container: 'matroska,webm',
  );

  @override
  Future<PlayState?> getProgress(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => null;

  @override
  Future<List<SubtitleTrack>?> listSubtitles(
    String itemId, {
    Future<void>? abortTrigger,
  }) async => const [];
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi() : super(ApiClient());

  @override
  Future<DevicePreferences?> getDevicePreferences({
    Future<void>? abortTrigger,
  }) async => null;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('argosy-player-setup');
    container = ProviderContainer(
      overrides: [
        libraryApiProvider.overrideWithValue(_FakeLibraryApi()),
        authApiProvider.overrideWithValue(_FakeAuthApi()),
        // No entry for the item, so the online path runs.
        stowStoreProvider.overrideWithValue(StowStore(root: tempDir)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    DeviceCapabilities.debugReset();
    await tempDir.delete(recursive: true);
  });

  test('carries hevc, hevcHardware and the display mode height', () async {
    DeviceCapabilities.debugOverride(
      hevc4k: true,
      hevcHardware: true,
      displayModeHeight: 2160,
    );

    final setup = await container.read(playerSetupProvider(_itemId).future);

    expect(setup.isTranscode, isTrue);
    expect(setup.hevc, isTrue);
    expect(setup.hevcHardware, isTrue);
    expect(setup.displayModeHeight, 2160);
  });

  test('a probed null mode height stays null', () async {
    // The sentinel default tells "passed null" from "not passed".
    DeviceCapabilities.debugOverride(
      hevc4k: true,
      hevcHardware: false,
      displayModeHeight: null,
    );

    final setup = await container.read(playerSetupProvider(_itemId).future);

    expect(setup.hevc, isTrue);
    expect(setup.hevcHardware, isFalse);
    expect(setup.displayModeHeight, isNull);
  });
}
