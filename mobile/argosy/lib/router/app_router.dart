import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/splash/splash_screen.dart';

/// Route paths, referenced by name everywhere instead of raw strings.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
}

/// The app router. Auth state drives a [GoRouter.redirect] gate:
///   unknown → splash, unauthenticated → login, authenticated → home.
/// We bridge Riverpod → go_router with a [ValueNotifier] fed by `ref.listen`,
/// so the router re-evaluates `redirect` whenever the session changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<AuthStatus>(AuthStatus.unknown);
  ref.onDispose(refresh.dispose);
  ref.listen<AuthStatus>(
    authControllerProvider,
    (_, next) => refresh.value = next,
    fireImmediately: true,
  );

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = refresh.value;
      final loc = state.matchedLocation;

      if (status == AuthStatus.unknown) {
        return loc == Routes.splash ? null : Routes.splash;
      }
      if (status == AuthStatus.unauthenticated) {
        return loc == Routes.login ? null : Routes.login;
      }
      // Authenticated: bounce off the splash/login screens into the app.
      if (loc == Routes.splash || loc == Routes.login) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomeScreen(),
      ),
    ],
  );
});
