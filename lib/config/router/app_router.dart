import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/agent_bench_screen.dart';
import '../../presentation/screens/agent_builder_screen.dart';
import '../../presentation/screens/agent_detail_screen.dart';
import '../../presentation/screens/app_shell.dart';
import '../../presentation/screens/chat_screen.dart';
import '../../presentation/screens/home_screen.dart';
import '../../presentation/screens/model_catalog_screen.dart';
import '../../presentation/screens/sessions_screen.dart';
import '../../presentation/screens/settings_screen.dart';

/// Route paths, so no string literal is written twice.
abstract final class Routes {
  static const String home = '/';
  static const String chat = '/chat';
  static const String agent = '/agent';
  static const String settings = '/settings';

  /// Outside the shell, so it covers the navigation bar.
  static const String session = '/chat/session/:id';
  static const String catalog = '/settings/catalog';

  /// Inside the Agent branch, so the navigation bar stays visible on it — as
  /// the mockups draw it.
  static const String agentDetail = '/agent/:id';

  /// The pipeline builder, also inside the Agent branch. Both must be matched
  /// before [agentDetail], or `/agent/new` reads as an agent called `new`.
  static const String agentNew = '/agent/new';
  static const String agentEdit = '/agent/edit/:id';
  static const String agentCopy = '/agent/copy/:id';

  static String sessionOf(String id) => '/chat/session/$id';
  static String agentOf(String id) => '/agent/$id';
  static String agentEditOf(String id) => '/agent/edit/$id';
  static String agentCopyOf(String id) => '/agent/copy/$id';
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
  initialLocation: Routes.home,
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
        _branch(Routes.home, const HomeScreen()),
        _branch(Routes.chat, const SessionsScreen()),
        _branch(
          Routes.agent,
          const AgentBenchScreen(),
          routes: <RouteBase>[
            // Declared before `:id`: go_router matches in order, so these
            // would otherwise be read as agents called `new`, `edit` and
            // `copy`.
            GoRoute(path: 'new', builder: (_, _) => const AgentBuilderScreen()),
            GoRoute(
              path: 'edit/:id',
              builder: (_, state) =>
                  AgentBuilderScreen(agentId: state.pathParameters['id']),
            ),
            GoRoute(
              path: 'copy/:id',
              builder: (_, state) => AgentBuilderScreen(
                agentId: state.pathParameters['id'],
                duplicate: true,
              ),
            ),
            GoRoute(
              path: ':id',
              builder: (_, state) =>
                  AgentDetailScreen(agentId: state.pathParameters['id'] ?? ''),
            ),
          ],
        ),
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

StatefulShellBranch _branch(
  String path,
  Widget child, {
  List<RouteBase> routes = const <RouteBase>[],
}) => StatefulShellBranch(
  routes: <RouteBase>[
    GoRoute(path: path, builder: (_, _) => child, routes: routes),
  ],
);
