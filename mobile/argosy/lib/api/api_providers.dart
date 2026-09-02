import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/io_client.dart';

import 'stream_urls.dart';
import 'token_store.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// The token + base-URL store. [TokenStore.load] must be awaited once at
/// startup (the auth controller does this on bootstrap) before reads are valid.
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStorageProvider)),
);

/// The resolved server base URL (persisted value, else the compile-time
/// default). Watching this rebuilds [apiClientProvider] when the server
/// address changes (e.g. after pairing); call [BaseUrlController.set] to
/// update it.
class BaseUrlController extends Notifier<String> {
  @override
  String build() => resolveBaseUrl(ref.watch(tokenStoreProvider).baseUrl);

  void set(String url) => state = url;
}

final baseUrlProvider =
    NotifierProvider<BaseUrlController, String>(BaseUrlController.new);

/// How long a request may spend trying to reach the server before giving up.
///
/// The generated client sets no timeout, and `dart:io`'s
/// `HttpClient.connectionTimeout` defaults to null — so a host that routes but
/// has nothing listening (captive-portal Wi-Fi, a tailnet that's down, the
/// server simply off) hangs for the OS connect timeout, which is minutes. That
/// is the *normal* condition for a phone playing something stowed, so every
/// call has to be bounded or the offline paths stall on a network that will
/// never answer (ARGY-49). Long enough not to trip on a slow tailnet hop.
const _connectTimeout = Duration(seconds: 6);

/// A configured [ApiClient]: base path from [baseUrlProvider], Bearer auth fed
/// by a live provider closure so the current token is read per-request without
/// rebuilding the client, over a transport with a bounded connect timeout.
final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final basePath = ref.watch(baseUrlProvider);
  final auth = HttpBearerAuth()..accessToken = () => store.token ?? '';
  final httpClient = IOClient(HttpClient()..connectionTimeout = _connectTimeout);
  ref.onDispose(httpClient.close);
  return ApiClient(basePath: basePath, authentication: auth)
    ..client = httpClient;
});

// Typed API surfaces, one per spec tag.
final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final libraryApiProvider =
    Provider<LibraryApi>((ref) => LibraryApi(ref.watch(apiClientProvider)));
final transcodeApiProvider =
    Provider<TranscodeApi>((ref) => TranscodeApi(ref.watch(apiClientProvider)));
final systemApiProvider =
    Provider<SystemApi>((ref) => SystemApi(ref.watch(apiClientProvider)));

/// Answers whether a *candidate* server address responds, without disturbing
/// the configured one. Manual server entry probes before it commits (ARGY-192),
/// so it needs a client aimed somewhere other than [baseUrlProvider].
///
/// A provider so tests can substitute a fake instead of reaching the network.
typedef ServerProbe =
    Future<({bool ok, String? detail})> Function(String baseUrl);

/// Shorter than [_connectTimeout]: this runs up to twice in a row while someone
/// waits on a "Continue" spinner, and a candidate that isn't listening is the
/// expected outcome rather than an error.
const _probeTimeout = Duration(seconds: 3);

final serverProbeProvider = Provider<ServerProbe>((ref) => _probeServer);

Future<({bool ok, String? detail})> _probeServer(String baseUrl) async {
  final httpClient = IOClient(HttpClient()..connectionTimeout = _probeTimeout);
  try {
    // `/api/v1/ping` is unauthenticated (`security: []`), so this answers
    // before there are any credentials to answer with.
    await SystemApi(ApiClient(basePath: baseUrl)..client = httpClient)
        .ping()
        .timeout(_probeTimeout);
    return (ok: true, detail: null);
  } catch (e) {
    // Keep why it failed: a server that answers 500 is a different problem
    // from one that isn't there, and the caller reports the last candidate's.
    return (ok: false, detail: mapApiError(e).message);
  } finally {
    httpClient.close();
  }
}

/// URL builder for the `?token=`-authenticated streaming/SSE endpoints, using
/// the current base URL + token.
final streamUrlsProvider = Provider<StreamUrls>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return StreamUrls(ref.watch(baseUrlProvider), store.token);
});

/// A friendly, typed failure surfaced to controllers/UI instead of the raw
/// [ApiException] / transport errors.
class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'ApiFailure($statusCode): $message';
}

/// Normalizes anything thrown by the generated client into an [ApiFailure].
ApiFailure mapApiError(Object error) {
  if (error is ApiFailure) return error;
  if (error is ApiException) {
    final code = error.code;
    final message = switch (code) {
      401 => 'Your session has expired. Please sign in again.',
      403 => "You don't have access to that.",
      404 => 'Not found.',
      >= 500 => 'The server had a problem. Try again shortly.',
      _ => error.message ?? 'Request failed ($code).',
    };
    return ApiFailure(message, statusCode: code == 0 ? null : code);
  }
  // Socket/timeout/format errors, etc.
  return const ApiFailure(
    "Couldn't reach the server. Check the connection and server address.",
  );
}
