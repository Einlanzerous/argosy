import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/tv/tv_pairing_screen.dart';
import '../features/detail/tv/tv_movie_screen.dart';
import '../features/detail/tv/tv_series_screen.dart';
import '../features/home/tv/tv_home_screen.dart';
import '../features/player/tv/tv_player_screen.dart';
import '../features/splash/splash_screen.dart';
import '../tv/tv_nav_rail.dart';
import '../tv/tv_placeholder_screen.dart';
import 'app_router.dart';

final _tvRootKey = GlobalKey<NavigatorState>();

/// The TV (10-foot, D-pad) router — same auth gate as [routerProvider], but the
/// sections render the TV shell ([TvScaffold] + nav rail) instead of the touch
/// bottom-nav. Selected over the phone router in `app.dart` when the device is a
/// television (ARGY-51).
///
/// PR2 lands the core loop: the real [TvHomeScreen] (hero + Continue-Watching
/// rails), [TvMovieScreen]/[TvSeriesScreen] detail, and the D-pad
/// [TvPlayerScreen]. Library/Search/Settings remain placeholders until PR3.
final routerTvProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<AuthStatus>(AuthStatus.unknown);
  ref.onDispose(refresh.dispose);
  ref.listen<AuthStatus>(
    authControllerProvider,
    (_, next) => refresh.value = next,
    fireImmediately: true,
  );

  return GoRouter(
    navigatorKey: _tvRootKey,
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
      if (loc == Routes.splash || loc == Routes.login) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const TvPairingScreen()),

      GoRoute(path: Routes.home, builder: (_, _) => const TvHomeScreen()),
      GoRoute(
        path: Routes.library,
        builder: (_, _) => const TvPlaceholderScreen(
          section: TvSection.library,
          title: 'Library',
          note: 'The Manifest grid lands in PR3.',
        ),
      ),
      GoRoute(
        path: Routes.search,
        builder: (_, _) => const TvPlaceholderScreen(
          section: TvSection.search,
          title: 'Search',
          note: 'On-screen keyboard + live results land in PR3.',
        ),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const TvPlaceholderScreen(
          section: TvSection.settings,
          title: 'Bridge',
          note: 'Fleet + preferences land in PR3.',
        ),
      ),

      // Detail + player: the TV (10-foot, D-pad) layouts (PR2).
      GoRoute(
        path: '/movie/:id',
        parentNavigatorKey: _tvRootKey,
        builder: (_, state) =>
            TvMovieScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/series/:id',
        parentNavigatorKey: _tvRootKey,
        builder: (_, state) =>
            TvSeriesScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/:id',
        parentNavigatorKey: _tvRootKey,
        builder: (_, state) => TvPlayerScreen(
          itemId: state.pathParameters['id']!,
          resume: state.uri.queryParameters['resume'] == '1',
          startOver: state.uri.queryParameters['start'] == '1',
        ),
      ),
    ],
  );
});
