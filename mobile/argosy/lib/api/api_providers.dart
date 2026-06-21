import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// A configured [ApiClient]: base path from [baseUrlProvider], Bearer auth fed
/// by a live provider closure so the current token is read per-request without
/// rebuilding the client.
final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final basePath = ref.watch(baseUrlProvider);
  final auth = HttpBearerAuth()..accessToken = () => store.token ?? '';
  return ApiClient(basePath: basePath, authentication: auth);
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
