import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/pairing_screen.dart';
import '../features/browse/media_card.dart';
import '../features/detail/movie_detail_screen.dart';
import '../features/detail/series_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import 'scaffold_with_nav.dart';

/// Route paths, referenced by name everywhere instead of raw strings.
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
  static const library = '/library';
  static const search = '/search';
  static const settings = '/settings';

  static String movie(String id) => '/movie/$id';
  static String series(String id) => '/series/$id';
  static String player(String id) => '/player/$id';
}

/// Pushes the detail screen for a card (Film → movie, Series → series).
void openDetail(BuildContext context, MediaKind kind, String id) {
  context.push(kind == MediaKind.series ? Routes.series(id) : Routes.movie(id));
}

/// Pushes the player for a playable item. `resume` jumps straight to the saved
/// position; `startOver` forces playback from the top. With neither, the player
/// asks (Resume vs. Start over) when there's saved progress — mirroring the web.
void openPlayer(
  BuildContext context,
  String itemId, {
  bool resume = false,
  bool startOver = false,
}) {
  final query = resume
      ? '?resume=1'
      : startOver
      ? '?start=1'
      : '';
  context.push('${Routes.player(itemId)}$query');
}

/// Pushes the Settings screen over the nav shell.
void openSettings(BuildContext context) => context.push(Routes.settings);

/// Switches to the Search tab (its own nav-shell branch).
void openSearch(BuildContext context) => context.go(Routes.search);

final _rootKey = GlobalKey<NavigatorState>();

/// The app router. Auth state drives a [GoRouter.redirect] gate:
///   unknown → splash, unauthenticated → login, authenticated → app shell.
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
    navigatorKey: _rootKey,
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
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const PairingScreen()),

      // The bottom-nav shell: Bridge / Manifest / Search, each its own branch.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ScaffoldWithNav(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                builder: (_, _) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.search,
                builder: (_, _) => const SearchScreen(),
              ),
            ],
          ),
        ],
      ),

      // Detail + player cover the whole screen (over the nav bar).
      GoRoute(
        path: '/movie/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            MovieDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/series/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) =>
            SeriesDetailScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => PlayerScreen(
          itemId: state.pathParameters['id']!,
          resume: state.uri.queryParameters['resume'] == '1',
          startOver: state.uri.queryParameters['start'] == '1',
        ),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
});
