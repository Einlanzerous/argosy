import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../platform/device_capabilities.dart';

/// Everything the player needs to start a session for an item, gathered up
/// front: catalog detail (title + duration), the playback decision, saved
/// progress, device preferences, subtitle tracks, and the device's HEVC
/// capability. The optional pieces degrade to null/empty rather than failing
/// the whole load.
typedef PlayerSetup = ({
  MediaItemDetail item,
  bool isTranscode,
  PlayState? progress,
  DevicePreferences? prefs,
  List<SubtitleTrack> subtitles,
  bool hevc,
});

final playerSetupProvider =
    FutureProvider.autoDispose.family<PlayerSetup, String>((ref, itemId) async {
  final lib = ref.watch(libraryApiProvider);
  final auth = ref.watch(authApiProvider);

  final item = await lib.getMediaItem(itemId);
  if (item == null) throw const ApiFailure('Not found.', statusCode: 404);

  // Kick the rest off concurrently before awaiting any of them.
  final playbackF = lib.getPlaybackInfo(itemId);
  final progressF = lib
      .getProgress(itemId)
      .then<PlayState?>((p) => p)
      .catchError((_) => null);
  final prefsF = auth
      .getDevicePreferences()
      .then<DevicePreferences?>((p) => p)
      .catchError((_) => null);
  final subsF = lib
      .listSubtitles(itemId)
      .then<List<SubtitleTrack>?>((s) => s)
      .catchError((_) => null);
  final hevcF = DeviceCapabilities.supportsHevc4k();

  final playback = await playbackF;
  return (
    item: item,
    // No playback info (or it says direct) → direct play; else transcode.
    isTranscode: playback != null && !playback.directPlay,
    progress: await progressF,
    prefs: await prefsF,
    subtitles: await subsF ?? const [],
    hevc: await hevcF,
  );
});
