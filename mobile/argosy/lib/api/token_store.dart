import 'dart:math';

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
  static const _kInstallId = 'argosy.installId';

  String? _token;
  String? _baseUrl;
  String? _installId;

  /// Current device token, or null when signed out. Synchronous (cached).
  String? get token => _token;

  /// Household server base URL (scheme + host[:port], no `/api/v1`), or null.
  String? get baseUrl => _baseUrl;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Hydrate the in-memory cache from secure storage. Call once at startup.
  Future<void> load() async {
    _token = await _storage.read(key: _kToken);
    _baseUrl = await _storage.read(key: _kBaseUrl);
    _installId = await _storage.read(key: _kInstallId);
  }

  /// A stable per-install id, minted once and persisted across re-pairs (and
  /// sign-outs — [clearToken] never touches it) so re-registering this device
  /// updates its existing Fleet row instead of spawning a duplicate (ARGY-99).
  Future<String> ensureInstallId() async {
    final existing = _installId;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomUuidV4();
    _installId = id;
    await _storage.write(key: _kInstallId, value: id);
    return id;
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

  /// Clear the token (sign-out). The server base URL and install id are
  /// intentionally kept — both outlive a single session.
  Future<void> clearToken() => setToken(null);
}

/// A random RFC-4122 v4 UUID built from [Random.secure]; avoids pulling in a
/// uuid package just for an opaque install id.
String _randomUuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
