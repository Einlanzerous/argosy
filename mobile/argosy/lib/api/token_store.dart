import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the device bearer token + the household server base URL, with an
/// in-memory cache so they can be read synchronously.
///
/// The sync [token] getter matters: the generated client's bearer auth takes a
/// `String Function()` provider that runs per-request, so the live token has to
/// be readable without awaiting. Call [load] once at startup to hydrate the
/// cache from secure storage.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _kToken = 'argosy.deviceToken';
  static const _kBaseUrl = 'argosy.baseUrl';

  String? _token;
  String? _baseUrl;

  /// Current device token, or null when signed out. Synchronous (cached).
  String? get token => _token;

  /// Household server base URL (scheme + host[:port], no `/api/v1`), or null.
  String? get baseUrl => _baseUrl;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Hydrate the in-memory cache from secure storage. Call once at startup.
  Future<void> load() async {
    _token = await _storage.read(key: _kToken);
    _baseUrl = await _storage.read(key: _kBaseUrl);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _kToken);
    } else {
      await _storage.write(key: _kToken, value: token);
    }
  }

  Future<void> setBaseUrl(String? baseUrl) async {
    _baseUrl = baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      await _storage.delete(key: _kBaseUrl);
    } else {
      await _storage.write(key: _kBaseUrl, value: baseUrl);
    }
  }

  /// Clear the token (sign-out). The server base URL is intentionally kept —
  /// the household server address outlives a single session.
  Future<void> clearToken() => setToken(null);
}
