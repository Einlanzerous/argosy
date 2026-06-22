import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../api/stream_urls.dart';
import '../auth/auth_controller.dart';
import '../home/home_providers.dart';
import 'beacon_client.dart';

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

/// App-lifetime glue between the Beacon stream and the UI: while authenticated,
/// it holds the SSE connection open and refreshes the home Continue-Watching /
/// On-Deck rows whenever *another* device reports a new position. A no-op until
/// authenticated. Watch it once at the app root so it spans the whole session.
final beaconSyncProvider = Provider<void>((ref) {
  if (ref.watch(authControllerProvider) != AuthStatus.authenticated) return;

  final client = ref.watch(beaconClientProvider);

  // Track this device's id reactively for echo-suppression.
  String? selfId;
  ref.listen<AsyncValue<String?>>(
    selfDeviceIdProvider,
    (_, next) => selfId = next.value,
    fireImmediately: true,
  );

  final sub = client.events.listen((ev) {
    if (selfId != null && ev.originDeviceId == selfId) return; // our own echo
    // Another device moved the position → recompute Continue-Watching/On-Deck.
    // (Resume-on-open for the player itself comes from GET /progress at launch.)
    ref.invalidate(homeDataProvider);
  });
  ref.onDispose(sub.cancel);

  client.start();
});
