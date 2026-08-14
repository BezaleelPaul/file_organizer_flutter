import 'package:file_organizer/screens/dashboard_screen.dart';
import 'package:file_organizer/screens/history_screen.dart';
import 'package:file_organizer/screens/organize_screen.dart';
import 'package:file_organizer/screens/rules_screen.dart';
import 'package:file_organizer/screens/watch_screen.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:flutter/material.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(state: widget.state),
      OrganizeScreen(state: widget.state),
      RulesScreen(state: widget.state),
      WatchScreen(state: widget.state),
      HistoryScreen(state: widget.state),
    ];
    final labels = const ['Dashboard', 'Organize', 'Rules', 'Watch', 'History'];
    final icons = const [
      Icons.dashboard_outlined,
      Icons.folder_copy_outlined,
      Icons.tune_outlined,
      Icons.visibility_outlined,
      Icons.history_outlined,
    ];
    final selectedIcons = const [
      Icons.dashboard,
      Icons.folder_copy,
      Icons.tune,
      Icons.visibility,
      Icons.history,
    ];

    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              _SideNav(
                index: _index,
                labels: labels,
                icons: icons,
                selectedIcons: selectedIcons,
                onSelect: (i) => setState(() => _index = i),
              ),
            Expanded(child: screens[_index]),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    selectedIcon: Icon(selectedIcons[i]),
                    label: labels[i],
                  ),
              ],
            ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.index,
    required this.labels,
    required this.icons,
    required this.selectedIcons,
    required this.onSelect,
  });

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      extended: MediaQuery.of(context).size.width >= 1200,
      selectedIndex: index,
      onDestinationSelected: onSelect,
      labelType: MediaQuery.of(context).size.width >= 1200
          ? NavigationRailLabelType.all
          : NavigationRailLabelType.selected,
      backgroundColor: scheme.surfaceContainerLow,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder_special_outlined, color: scheme.primary),
            ),
            if (MediaQuery.of(context).size.width >= 1200) ...[
              const SizedBox(width: 8),
              const Text('File Organizer',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
      destinations: [
        for (var i = 0; i < labels.length; i++)
          NavigationRailDestination(
            icon: Icon(icons[i]),
            selectedIcon: Icon(selectedIcons[i]),
            label: Text(labels[i]),
          ),
      ],
    );
  }
}
