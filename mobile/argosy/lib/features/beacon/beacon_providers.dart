import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../api/stream_urls.dart';
import '../auth/auth_controller.dart';
import '../detail/detail_providers.dart';
import '../home/home_providers.dart';
import 'beacon_client.dart';
import 'live_refresh.dart';

/// This device's id, resolved from the current session, used to drop echoes of
/// our own progress reports on the Beacon stream. Best-effort: null on failure,
/// in which case we forward every event (a redundant refresh beats a miss).
final selfDeviceIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final session = await ref.watch(authApiProvider).getCurrentSession();
    return session?.deviceId;
  } catch (_) {
    return null;
  }
});

/// The live Beacon SSE client. autoDispose so it tears down (closing the socket
/// and halting reconnects) the moment [beaconSyncProvider] stops watching it on
/// sign-out. The URL is resolved live per connect, so a re-pair / server switch
/// is honoured on the next reconnect.
final beaconClientProvider = Provider.autoDispose<BeaconClient>((ref) {
  final client = BeaconClient(
    resolveUrl: () {
      final token = ref.read(tokenStoreProvider).token;
      return StreamUrls(ref.read(baseUrlProvider), token).beacon();
    },
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Everything that shows play progress, refetched together when it may be
/// stale. Invalidating a whole family touches only the instances that are
/// alive, i.e. the detail screens actually on the stack, and every one of them
/// renders stale-while-revalidate, so nothing flashes or loses focus.
void invalidateProgressViews(Ref ref) {
  ref.invalidate(homeDataProvider);
  ref.invalidate(seriesDetailProvider);
  ref.invalidate(movieDetailProvider);
}

/// App-lifetime glue between the Beacon stream and the UI: while authenticated,
/// it holds the SSE connection open and refreshes Home and any open detail
/// screen when *another* device reports a new position, when the app returns
/// to the foreground, and when the stream reconnects (ARGY-291; see
/// [LiveRefresh]). A no-op until authenticated. Watch it once at the app root so
/// it spans the whole session.
final beaconSyncProvider = Provider<void>((ref) {
  if (ref.watch(authControllerProvider) != AuthStatus.authenticated) return;

  final client = ref.watch(beaconClientProvider);
  final live = LiveRefresh(refresh: () => invalidateProgressViews(ref));
  ref.onDispose(live.dispose);

  // Track this device's id reactively for echo-suppression.
  String? selfId;
  ref.listen<AsyncValue<String?>>(
    selfDeviceIdProvider,
    (_, next) => selfId = next.value,
    fireImmediately: true,
  );

  final sub = client.events.listen((ev) {
    if (selfId != null && ev.originDeviceId == selfId) return; // our own echo
    live.onForeignEvent();
  });
  ref.onDispose(sub.cancel);
  final opened = client.opened.listen((_) => live.onStreamOpened());
  ref.onDispose(opened.cancel);

  // Android freezes a backgrounded app and the SSE socket dies with it, so the
  // events published meanwhile are lost; the resume refetch recovers them.
  final lifecycle = AppLifecycleListener(onResume: live.onResumed);
  ref.onDispose(lifecycle.dispose);

  client.start();
});
