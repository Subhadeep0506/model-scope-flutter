import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/app_shell.dart';
import '../../presentation/screens/chat_screen.dart';
import '../../presentation/screens/model_catalog_screen.dart';
import '../../presentation/screens/placeholder_screen.dart';
import '../../presentation/screens/sessions_screen.dart';
import '../../presentation/screens/settings_screen.dart';

/// Route paths, so no string literal is written twice.
abstract final class Routes {
  static const String home = '/';
  static const String chat = '/chat';
  static const String agent = '/agent';
  static const String settings = '/settings';

  /// Full-screen transcript, deliberately outside the shell so it covers the
  /// navigation bar — see `assets/design/chat-messages.png`.
  static const String session = '/chat/session/:id';

  /// The model catalog, nested under Settings so the navigation bar stays put
  /// and back returns to Settings — see
  /// `assets/design/settings-browse-models-list.png`.
  static const String catalog = '/settings/catalog';

  static String sessionOf(String id) => '/chat/session/$id';
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

/// The four tabs, in the order drawn in the mockups.
const List<AppTab> appTabs = <AppTab>[
  AppTab(path: Routes.home, label: 'Home', icon: Icons.grid_view_outlined),
  AppTab(
    path: Routes.chat,
    label: 'Chat',
    icon: Icons.chat_bubble_outline_rounded,
  ),
  AppTab(path: Routes.agent, label: 'Agent', icon: Icons.smart_toy_outlined),
  AppTab(path: Routes.settings, label: 'Settings', icon: Icons.tune_outlined),
];

/// One entry in the bottom navigation bar.
class AppTab {
  const AppTab({required this.path, required this.label, required this.icon});

  final String path;
  final String label;
  final IconData icon;
}

GoRouter createRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  // Opens on the tab this part actually implements.
  initialLocation: Routes.chat,
  routes: <RouteBase>[
    GoRoute(
      path: Routes.session,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) =>
          ChatScreen(sessionId: state.pathParameters['id'] ?? ''),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) => AppShell(shell: navigationShell),
      branches: <StatefulShellBranch>[
        _branch(Routes.home, const PlaceholderScreen(title: 'Home')),
        _branch(Routes.chat, const SessionsScreen()),
        _branch(Routes.agent, const PlaceholderScreen(title: 'Agent')),
        _branch(
          Routes.settings,
          const SettingsScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'catalog',
              builder: (_, _) => const ModelCatalogScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// One tab, with any screens pushed on top of it.
///
/// Sub-routes are relative paths and nest inside the branch, so pushing one
/// keeps the navigation bar on screen and leaves the other tabs' stacks alone.
StatefulShellBranch _branch(
  String path,
  Widget child, {
  List<RouteBase> routes = const <RouteBase>[],
}) => StatefulShellBranch(
  routes: <RouteBase>[
    GoRoute(path: path, builder: (_, _) => child, routes: routes),
  ],
);
