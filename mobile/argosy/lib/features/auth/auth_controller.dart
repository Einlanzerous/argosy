import 'dart:io' show Platform;

import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';

/// Where the session stands. [unknown] is the pre-bootstrap state used to hold
/// on the splash while we restore + validate a saved device token.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// Owns the auth/session state the router gates on: server selection, the
/// login → profile → device-registration pairing flow, token persistence, and
/// startup restore. Mirrors the web's session store + `LoginView` flow.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _bootstrap();
    return AuthStatus.unknown;
  }

  /// This device's platform tag for the Fleet (`android` / `ios`).
  String get platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _bootstrap() async {
    final store = ref.read(tokenStoreProvider);
    try {
      await store.load();
    } catch (_) {
      // Secure storage unavailable/corrupt (or absent in tests) — treat as
      // signed-out rather than bricking the app.
      state = AuthStatus.unauthenticated;
      return;
    }

    final base = store.baseUrl;
    if (base != null && base.isNotEmpty) {
      ref.read(baseUrlProvider.notifier).set(base);
    }

    if (!store.hasToken) {
      state = AuthStatus.unauthenticated;
      return;
    }

    // Validate the restored token. A definitive 401 means it was revoked →
    // re-pair; a transport error (server unreachable) keeps us optimistically
    // signed in so an offline launch isn't locked out.
    try {
      await ref.read(authApiProvider).getCurrentSession();
      state = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.code == 401) {
        await store.clearToken();
        state = AuthStatus.unauthenticated;
      } else {
        state = AuthStatus.authenticated;
      }
    } catch (_) {
      state = AuthStatus.authenticated;
    }
  }

  /// Persist + activate the household server address, then verify it's
  /// reachable. Throws [ApiFailure] if the address is unusable.
  Future<void> setServer(String rawUrl) async {
    final url = _normalizeServerUrl(rawUrl);
    if (url == null) {
      throw const ApiFailure(
        'Enter a valid server address, e.g. http://10.0.0.20:8097',
      );
    }
    await ref.read(tokenStoreProvider).setBaseUrl(url);
    ref.read(baseUrlProvider.notifier).set(url);
    try {
      await ref.read(systemApiProvider).ping();
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Step 1 — authenticate the household account; returns its profiles to pick.
  Future<List<UserProfile>> login(String username, String password) async {
    try {
      final res = await ref
          .read(authApiProvider)
          .login(LoginRequest(username: username, password: password));
      return res?.profiles ?? const [];
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Step 2 — register this device against the chosen profile and persist the
  /// returned device token. Flips the gate to authenticated on success.
  Future<void> pairDevice({
    required String username,
    required String password,
    required String userId,
    required String deviceName,
  }) async {
    try {
      final installId = await ref.read(tokenStoreProvider).ensureInstallId();
      final res = await ref
          .read(authApiProvider)
          .registerDevice(
            DeviceRegistrationRequest(
              username: username,
              password: password,
              userId: userId,
              deviceName: deviceName,
              platform: platform,
              installId: installId,
            ),
          );
      final token = res?.token;
      if (token == null || token.isEmpty) {
        throw const ApiFailure('Pairing succeeded but returned no token.');
      }
      await ref.read(tokenStoreProvider).setToken(token);
      state = AuthStatus.authenticated;
    } catch (e) {
      throw mapApiError(e);
    }
  }

  /// Adopt a device token obtained out-of-band — e.g. TV code-pairing, where the
  /// token is minted server-side once a web user approves the code (ARGY-112).
  /// The token is already valid, so we just persist it and open the gate.
  Future<void> adoptToken(String token) async {
    await ref.read(tokenStoreProvider).setToken(token);
    state = AuthStatus.authenticated;
  }

  /// Sign out / re-pair. Keeps the server address (only the token is cleared).
  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clearToken();
    state = AuthStatus.unauthenticated;
  }

  /// Accepts `host`, `host:port`, or a full URL; defaults to http, strips a
  /// trailing slash. Returns null when nothing usable is left.
  static String? _normalizeServerUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthStatus>(
  AuthController.new,
);
