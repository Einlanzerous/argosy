import 'dart:async';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../platform/device_capabilities.dart';
import 'offline_progress_queue.dart';
import 'stow_runner.dart';
import 'stow_service.dart';
import 'stow_store.dart';
import 'stowed_item.dart';

/// The app's view of what is being stowed.
///
/// It no longer runs the downloads itself (ARGY-201): the transfer belongs to a
/// [StowEngine], which on Android is a foreground service that keeps going with
/// the app backgrounded or swiped away. What is left here is the part that only
/// makes sense while there is a UI — turning a catalog item into a job, and
/// keeping every screen agreeing on what is in flight.
///
/// Held as a single controller rather than one per item because the Stowed
/// screen, the detail-screen button and the player all read the same state, and
/// because cancelling has to reach a download the screen that started it may
/// have long since disposed.
class StowController extends Notifier<Map<String, StowStatus>> {
  StowController();

  StowStore get _store => ref.read(stowStoreProvider);
  StowEngine get _engine => ref.read(stowEngineProvider);
  LibraryApi get _libraryApi => ref.read(libraryApiProvider);

  @override
  Map<String, StowStatus> build() {
    final subscription = _engine.events.listen(_onEvent);
    ref.onDispose(subscription.cancel);
    // The service may already be downloading something this app launch never
    // started — it survives the app being closed. Ask what it is holding.
    unawaited(_engine.sync());
    return const {};
  }

  /// Live status for an item: the in-flight phase if there is one, else
  /// [StowPhase.stowed] when it is already on the device.
  StowStatus statusFor(String itemId) {
    final live = state[itemId];
    if (live != null) return live;
    if (_store.has(itemId)) {
      return StowStatus(
        phase: StowPhase.stowed,
        totalBytes: _store.get(itemId)?.bytes ?? 0,
      );
    }
    // In-flight status lives in memory, so after a restart a stow that failed
    // partway would otherwise read as "never started" — offering Stow with no
    // hint that gigabytes are sitting underneath it. The unfinished index entry
    // is what survives, so report from that.
    final partial = _store.partial(itemId);
    if (partial != null) {
      return StowStatus(
        phase: StowPhase.failed,
        receivedBytes: partial.bytes,
        message: 'Download stopped partway — it resumes where it left off.',
      );
    }
    return const StowStatus.none();
  }

  void _onEvent(StowEvent event) {
    // The service outlives this controller: a download running when the app is
    // torn down keeps reporting, and touching a disposed Ref throws.
    if (event.isIdle || !ref.mounted) return;
    final itemId = event.itemId!;
    final status = event.status;
    state = status == null
        ? ({...state}..remove(itemId))
        : {...state, itemId: status};
    if (event.indexChanged) {
      // The index was rewritten by the isolate that owns the download, so the
      // copy this side is holding is out of date.
      unawaited(
        _store.reload().then((_) {
          if (ref.mounted) ref.invalidate(stowedItemsProvider);
        }),
      );
    }
  }

  /// Stows an item known only by id — the episode-row case, where the screen
  /// holds an [EpisodeSummary] rather than a full detail. Fetches the detail
  /// first, since the stow record has to stand on its own offline.
  Future<void> stowById(String itemId, {String? subtitleLine}) async {
    if (statusFor(itemId).isBusy) return;
    _set(itemId, const StowStatus(phase: StowPhase.requesting));
    try {
      final detail = await _libraryApi.getMediaItem(itemId);
      if (detail == null) {
        throw const ApiFailure('That item is no longer in the library.');
      }
      await stow(detail, subtitleLine: subtitleLine);
    } catch (e) {
      _set(
        itemId,
        StowStatus(
          phase: StowPhase.failed,
          message: e is ApiFailure ? e.message : mapApiError(e).message,
        ),
      );
    }
  }

  /// Packs [item] away for offline viewing. Safe to call again for an item
  /// already in flight — it is a no-op rather than a second download.
  Future<void> stow(MediaItemDetail item, {String? subtitleLine}) async {
    final itemId = item.id;
    // Show something immediately: handing the job over involves starting a
    // service, and a button that does nothing for a beat reads as broken.
    _set(itemId, const StowStatus(phase: StowPhase.requesting));
    try {
      await _engine.enqueue(
        StowJobRequest(
          itemId: itemId,
          title: item.title,
          sourcePath: item.filePath,
          subtitleLine: subtitleLine ?? _defaultSubtitleLine(item),
          posterUrl: item.posterUrl,
          durationSeconds: (item.durationSeconds ?? 0).toDouble(),
          // The catalog says `episode`, not `series` — a playable item is never
          // the series itself. Anything episode-shaped rows as series so the
          // offline list labels it the way the rest of the app does.
          isEpisode: item.kind == 'episode' || item.episodeNumber != null,
          seasonNumber: item.seasonNumber,
          episodeNumber: item.episodeNumber,
          // Answered here, while the capability channel exists: it is
          // registered on the app's engine, and the service isolate asking
          // would be told "no" and package a file this phone plays as it is.
          hevc: await DeviceCapabilities.supportsHevc4k(),
          // ExoPlayer opens Matroska; AVPlayer does not. Answering honestly is
          // what lets most of an mkv library stow without an encode on Android.
          matroska: Platform.isAndroid,
        ),
      );
    } catch (e) {
      _set(
        itemId,
        StowStatus(
          phase: StowPhase.failed,
          message: e is ApiFailure ? e.message : mapApiError(e).message,
        ),
      );
    }
  }

  /// Cancels an in-flight stow and clears whatever it had written.
  Future<void> cancel(String itemId) => _engine.cancel(itemId);

  /// Removes a stowed item from the device.
  Future<void> remove(String itemId) => _engine.remove(itemId);

  void _set(String itemId, StowStatus status) {
    state = {...state, itemId: status};
  }

  String? _defaultSubtitleLine(MediaItemDetail item) {
    if (item.seasonNumber != null && item.episodeNumber != null) {
      final code = 'S${item.seasonNumber} · E${item.episodeNumber}';
      final title = item.episodeTitle;
      return title == null || title.isEmpty ? code : '$code · $title';
    }
    return item.year?.toString();
  }
}

/// The device's stow index. Callers `await store.load()` before reading; it is
/// idempotent, so every entry point can do so without coordinating.
final stowStoreProvider = Provider<StowStore>((ref) => StowStore());

/// What actually performs downloads.
///
/// Android gets the foreground service, so a stow survives leaving the app. On
/// iOS the equivalent is `URLSession` background transfers, which is a separate
/// piece of work — until then it runs in-app, as it did everywhere before
/// ARGY-201. Tests override this with a [LocalStowEngine] over a fake server.
final stowEngineProvider = Provider<StowEngine>((ref) {
  final store = ref.watch(stowStoreProvider);
  final engine = Platform.isAndroid
      ? ForegroundStowEngine(store: store)
      : LocalStowEngine(
          store: store,
          connect: () async => StowSession.connect(
            baseUrl: ref.read(baseUrlProvider),
            token: ref.read(tokenStoreProvider).token,
          ),
        );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Resume positions recorded while the server was unreachable, waiting to be
/// sent. Drained whenever a progress report succeeds, and once at startup.
final offlineProgressQueueProvider = Provider<OfflineProgressQueue>(
  (ref) => OfflineProgressQueue(),
);

/// Sends anything the device recorded offline. Called once after sign-in, so a
/// flight's worth of watching lands without waiting for the next play.
Future<int> flushOfflineProgress(Ref ref) async {
  try {
    return await ref
        .read(offlineProgressQueueProvider)
        .flush(ref.read(libraryApiProvider));
  } catch (_) {
    return 0; // Still offline; the next attempt will get it.
  }
}

final stowControllerProvider =
    NotifierProvider<StowController, Map<String, StowStatus>>(
      StowController.new,
    );

/// Everything currently stowed on the device. Invalidated by the controller
/// whenever the index changes.
final stowedItemsProvider = FutureProvider<List<StowedItem>>((ref) async {
  final store = ref.watch(stowStoreProvider);
  await store.load();
  return store.list();
});

/// Whether a given item is playable from local storage right now — the player
/// consults this before reaching for the network.
final stowedItemProvider = FutureProvider.family<StowedItem?, String>((
  ref,
  itemId,
) async {
  final store = ref.watch(stowStoreProvider);
  await store.load();
  return store.get(itemId);
});
