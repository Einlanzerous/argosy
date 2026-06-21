import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the session stands. [unknown] is the pre-bootstrap state used to hold
/// on the splash while we try to restore a saved device token.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// Owns the auth/session state the router gates on.
///
/// This is a scaffold placeholder: bootstrap and sign-in are stubbed. Real
/// device-token restore (`GET /auth/me`) and pairing (`POST /auth/login` →
/// profile → `POST /auth/devices`) land in ARGY-46 once the Dart API client
/// (ARGY-78) exists.
class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _bootstrap();
    return AuthStatus.unknown;
  }

  Future<void> _bootstrap() async {
    // TODO(ARGY-46): restore a persisted device token and validate it via
    // GET /auth/me; fall through to unauthenticated on miss/expiry.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (state == AuthStatus.unknown) {
      state = AuthStatus.unauthenticated;
    }
  }

  /// Placeholder sign-in — flips the gate so the rest of the shell is
  /// reachable. Replaced by real pairing in ARGY-46.
  void signIn() => state = AuthStatus.authenticated;

  void signOut() => state = AuthStatus.unauthenticated;
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
