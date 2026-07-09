import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// An Argosy server found on the local network via mDNS (ARGY-123). The server
/// advertises `_argosy._tcp` (see internal/discovery on the Go side) with a
/// friendly `name` TXT attribute.
class DiscoveredServer {
  const DiscoveredServer({required this.name, required this.url});

  /// Human-friendly server name (the ARGOSY_SERVER_NAME the server advertises).
  final String name;

  /// Base URL, e.g. `http://10.0.0.45:8096`.
  final String url;
}

/// The DNS-SD service type the server advertises.
const argosyServiceType = '_argosy._tcp';

/// Browses the LAN for an Argosy server and completes with the first one that
/// resolves, or null after [timeout]. Any platform/discovery failure also
/// yields null — the caller falls back to manual address entry, so discovery
/// must never throw out of this function.
Future<DiscoveredServer?> discoverServer({
  Duration timeout = const Duration(seconds: 6),
}) async {
  BonsoirDiscovery? discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? sub;
  final found = Completer<DiscoveredServer?>();
  try {
    discovery = BonsoirDiscovery(type: argosyServiceType);
    await discovery.initialize();
    final resolver = discovery.serviceResolver;
    sub = discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          service.resolve(resolver);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          final url = _serviceUrl(service);
          if (url != null && !found.isCompleted) {
            found.complete(DiscoveredServer(
              name: service.attributes['name'] ?? service.name,
              url: url,
            ));
          }
        default:
          break;
      }
    });
    await discovery.start();
    return await found.future
        .timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    await sub?.cancel();
    try {
      await discovery?.stop();
    } catch (_) {
      // Best-effort teardown; nothing actionable if the platform side is gone.
    }
  }
}

/// Builds `http://host:port` from a resolved service, preferring an IPv4
/// address (an IPv6 literal needs brackets and is more likely to be
/// link-local/unroutable for our purposes).
String? _serviceUrl(BonsoirService service) {
  final addresses = service.hostAddresses;
  String? host;
  for (final a in addresses) {
    if (!a.contains(':')) {
      host = a;
      break;
    }
  }
  host ??= addresses.isNotEmpty ? '[${addresses.first}]' : service.hostname;
  if (host == null || host.isEmpty) return null;
  return 'http://$host:${service.port}';
}
