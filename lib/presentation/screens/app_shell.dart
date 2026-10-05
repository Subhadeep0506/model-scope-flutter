import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/router/app_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: _onSelected,
      destinations: <Widget>[
        for (final tab in appTabs)
          NavigationDestination(
            icon: Icon(tab.icon),
            label: tab.label,
            tooltip: tab.label,
          ),
      ],
    ),
  );

  void _onSelected(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);
}
