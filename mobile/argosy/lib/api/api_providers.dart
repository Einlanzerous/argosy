import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/io_client.dart';

import 'stream_urls.dart';
import 'token_store.dart';

/// Optional compile-time default for the server address, e.g.
/// `flutter run --dart-define=ARGOSY_BASE_URL=http://10.0.0.20:8097`.
/// Empty until pairing (ARGY-46) persists a real one via [TokenStore].
const _envBaseUrl = String.fromEnvironment('ARGOSY_BASE_URL');

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
  String build() {
    final stored = ref.watch(tokenStoreProvider).baseUrl;
    return (stored != null && stored.isNotEmpty) ? stored : _envBaseUrl;
  }

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
