import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/detail/catch_detail_screen.dart';
import '../features/edit/catch_form_screen.dart';
import '../features/home/home_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/log/catch_list_screen.dart';
import '../features/map/catch_map_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/trips/trip_detail_screen.dart';
import '../features/trips/trip_list_screen.dart';

/// URL map. Every screen has a real URL, so the web build supports refresh, back/forward and
/// deep links — and the same paths drive navigation on iOS and Android.
///
///   /home  /log  /map  /trips  /insights          the five tabs
///   /(tab)/catch/:id                              a catch, opened inside whichever tab you were in
///   /trips/:tripId                                a trip
///   /catch/new   /catch/:id/edit                  full-screen editor (hides the tab bar)
abstract final class Routes {
  static const home = '/home';
  static const log = '/log';
  static const map = '/map';
  static const trips = '/trips';
  static const insights = '/insights';

  static String newCatch() => '/catch/new';
  static String editCatch(String id) => '/catch/$id/edit';

  /// A catch inside a given tab, so the tab bar stays visible and Back returns to that tab.
  static String catchIn(String tabPath, String id) => '$tabPath/catch/$id';
  static String trip(String id) => '$trips/$id';
}

GoRoute _catchDetailRoute() => GoRoute(
      path: 'catch/:id',
      builder: (context, state) => CatchDetailScreen(catchId: state.pathParameters['id']!),
    );

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen(), routes: [_catchDetailRoute()]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.log, builder: (_, _) => const CatchListScreen(), routes: [_catchDetailRoute()]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.map, builder: (_, _) => const CatchMapScreen(), routes: [_catchDetailRoute()]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.trips,
              builder: (_, _) => const TripListScreen(),
              routes: [
                GoRoute(
                  path: ':tripId',
                  builder: (context, state) => TripDetailScreen(tripId: state.pathParameters['tripId']!),
                  routes: [_catchDetailRoute()],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.insights, builder: (_, _) => const InsightsScreen()),
          ]),
        ],
      ),
      GoRoute(path: '/catch/new', builder: (_, _) => const CatchFormScreen()),
      GoRoute(
        path: '/catch/:id/edit',
        builder: (context, state) => CatchFormScreen(catchId: state.pathParameters['id']),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("That page doesn't exist."),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go(Routes.home), child: const Text('Go home')),
          ],
        ),
      ),
    ),
  );
});
