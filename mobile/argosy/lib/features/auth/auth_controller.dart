import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';

/// Where the session stands. [unknown] is the pre-bootstrap state used to hold
/// on the splash while we restore a saved device token.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// Owns the auth/session state the router gates on, backed by the persisted
/// [TokenStore].
///
/// ARGY-78 delivers token persistence + the API client plumbing. Real pairing
/// (`POST /auth/login` → profile → `POST /auth/devices`) and session validation
/// via `AuthApi.getCurrentSession()` land in ARGY-46 — [signIn] is still a
/// placeholder that just persists a token so the gate survives a restart.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _bootstrap();
    return AuthStatus.unknown;
  }

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

    // Re-seed the base-URL state from the freshly loaded store.
    final base = store.baseUrl;
    if (base != null && base.isNotEmpty) {
      ref.read(baseUrlProvider.notifier).set(base);
    }

    // TODO(ARGY-46): when a token exists, validate it via
    // AuthApi.getCurrentSession() and drop to unauthenticated on 401.
    state = store.hasToken
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
  }

  /// Placeholder sign-in — persists a token so the session survives restarts.
  /// Replaced by real pairing in ARGY-46.
  Future<void> signIn() async {
    await ref.read(tokenStoreProvider).setToken('dev-placeholder-token');
    state = AuthStatus.authenticated;
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clearToken();
    state = AuthStatus.unauthenticated;
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
