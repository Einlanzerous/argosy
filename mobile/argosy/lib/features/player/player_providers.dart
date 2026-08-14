import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../platform/device_capabilities.dart';
import '../browse/media_card.dart';
import '../stow/stow_controller.dart';
import '../stow/stow_store.dart';
import '../stow/stowed_item.dart';

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
  List<String> preferredLanguages,
  bool hevc,

  /// Absolute path to a stowed copy of this item, when one is on the device
  /// (ARGY-49). Set means play from disk and never touch the network.
  String? localPath,

  /// Local WebVTT sidecars that came down with the stowed copy, keyed by the
  /// same track id the picker uses. Empty when playing online.
  List<({String id, String label, String language, String path})>
  localSubtitles,
});

final playerSetupProvider = FutureProvider.autoDispose.family<PlayerSetup, String>((
  ref,
  itemId,
) async {
  final lib = ref.watch(libraryApiProvider);
  final auth = ref.watch(authApiProvider);

  // A stowed copy short-circuits everything the network would otherwise be
  // asked for. This is checked first, and deliberately not merged into the
  // concurrent fetch below: on a plane those requests don't fail fast, they
  // hang until they time out, and the player would sit on a spinner for a file
  // already sitting on the device.
  final store = ref.watch(stowStoreProvider);
  await store.load();
  final stowed = store.get(itemId);
  if (stowed != null) {
    return await _offlineSetup(ref, store, stowed, itemId);
  }

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
    // Household preferred languages (ARGY-154): the track sheet shows matching
    // tracks by default and folds the rest behind "More options".
    preferredLanguages: playback?.preferredLanguages ?? const [],
    hevc: await hevcF,
    localPath: null,
    localSubtitles:
        const <({String id, String label, String language, String path})>[],
  );
});

/// Builds the setup for a stowed item, using only what is on the device.
///
/// Everything optional degrades rather than failing: saved progress and device
/// preferences are attempted (they may be cached, or the device may in fact be
/// online), but a failure just means resuming from the start with default
/// captions — never a player that refuses to open a file it already has.
Future<PlayerSetup> _offlineSetup(
  Ref ref,
  StowStore store,
  StowedItem stowed,
  String itemId,
) async {
  final lib = ref.read(libraryApiProvider);
  final auth = ref.read(authApiProvider);

  // Rebuild the picker's track list from the sidecars on disk, keeping each
  // track's original id. That id is what the caption preference is saved
  // against, so a viewer's "English, on" choice survives going offline.
  final localSubs =
      <({String id, String label, String language, String path})>[];
  final localTracks = <SubtitleTrack>[];
  for (final track in stowed.subtitles) {
    localSubs.add((
      id: track.id,
      label: track.label,
      language: track.language,
      path: await store.subtitlePath(stowed, track),
    ));
    localTracks.add(
      SubtitleTrack(
        id: track.id,
        source_: SubtitleTrackSource_Enum.embedded,
        language: track.language,
        label: track.label,
        forced: false,
        default_: false,
      ),
    );
  }

  // Saved progress and device preferences are worth having when the server
  // happens to be reachable, but a stowed file must never wait on them: these
  // run concurrently and time out fast, because the failure that matters is not
  // airplane mode (which errors immediately) but connected-with-no-server —
  // hotel and plane Wi-Fi — where a request hangs instead of failing. Missing
  // either just means starting from the top with default captions.
  const settleWait = Duration(seconds: 4);
  final progressF = lib
      .getProgress(itemId)
      .timeout(settleWait)
      .then<PlayState?>((p) => p)
      .catchError((_) => null);
  final prefsF = auth
      .getDevicePreferences()
      .timeout(settleWait)
      .then<DevicePreferences?>((p) => p)
      .catchError((_) => null);
  final progress = await progressF;
  final prefs = await prefsF;

  return (
    // A stowed item still needs catalog-shaped detail for the title bar and the
    // scrub bar's domain; it is reconstructed from the index rather than
    // fetched, since the server may be unreachable.
    item: MediaItemDetail(
      id: stowed.itemId,
      // The catalog's own vocabulary: a playable row is a movie or an episode.
      kind: stowed.kind == MediaKind.series ? 'episode' : 'movie',
      title: stowed.title,
      filePath: stowed.fileName,
      durationSeconds: stowed.durationSeconds,
      posterUrl: stowed.posterUrl,
      reviewRequired: false,
      seasonNumber: stowed.seasonNumber,
      episodeNumber: stowed.episodeNumber,
    ),
    // A local file is played directly; there is no session to transcode.
    isTranscode: false,
    progress: progress,
    prefs: prefs,
    subtitles: localTracks,
    preferredLanguages: const <String>[],
    hevc: false,
    localPath: await store.videoPath(stowed),
    localSubtitles: localSubs,
  );
}
