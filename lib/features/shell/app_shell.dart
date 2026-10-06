import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/icons.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

const _destinations = [
  _Destination('Home', Icon(Icons.home_outlined), Icon(Icons.home)),
  _Destination('Log', Icon(Icons.format_list_bulleted), Icon(Icons.format_list_bulleted)),
  _Destination('Map', Icon(Icons.map_outlined), Icon(Icons.map)),
  _Destination('Trips', Icon(Icons.sailing_outlined), Icon(Icons.sailing)),
  _Destination('Insights', Icon(Icons.insights_outlined), Icon(Icons.insights)),
];

/// Five tabs, adaptive: a bottom bar on phones, a navigation rail on wide screens (web,
/// tablets, landscape) — the Flutter counterpart of the Swift app's `.sidebarAdaptable` tabs.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const double railBreakpoint = 720;
  static const double extendedRailBreakpoint = 1100;

  void _select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= railBreakpoint;
        if (!wide) {
          return Scaffold(
            body: shell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: d.label),
              ],
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: constraints.maxWidth >= extendedRailBreakpoint,
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: _select,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: FishIcon(size: 32, color: Theme.of(context).colorScheme.primary),
                  ),
                  labelType: constraints.maxWidth >= extendedRailBreakpoint
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label)),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: shell),
            ],
          ),
        );
      },
    );
  }
}
