import 'package:file_organizer/screens/dashboard_screen.dart';
import 'package:file_organizer/screens/history_screen.dart';
import 'package:file_organizer/screens/organize_screen.dart';
import 'package:file_organizer/screens/rules_screen.dart';
import 'package:file_organizer/screens/search_screen.dart';
import 'package:file_organizer/screens/settings_screen.dart';
import 'package:file_organizer/screens/storage_screen.dart';
import 'package:file_organizer/screens/watch_screen.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/theme.dart';
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
      DashboardScreen(
        state: widget.state,
        onNavigateTab: (i) => setState(() => _index = i),
      ),
      OrganizeScreen(state: widget.state),
      StorageScreen(state: widget.state),
      SearchScreen(state: widget.state),
      RulesScreen(state: widget.state),
      WatchScreen(state: widget.state),
      HistoryScreen(state: widget.state),
      SettingsScreen(state: widget.state),
    ];

    // Primary mobile destinations (5 items fit gracefully without overflow)
    final mobileDestinations = const [
      (0, 'Workbench', Icons.dashboard_outlined, Icons.dashboard_rounded),
      (1, 'Blueprint', Icons.folder_copy_outlined, Icons.folder_copy_rounded),
      (2, 'Storage', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded),
      (3, 'Search', Icons.search_outlined, Icons.search_rounded),
      (6, 'Time Machine', Icons.history_outlined, Icons.history_rounded),
    ];

    // Full desktop navigation rail destinations
    final railDestinations = const [
      ('Workbench', Icons.dashboard_outlined, Icons.dashboard_rounded),
      ('Blueprint', Icons.folder_copy_outlined, Icons.folder_copy_rounded),
      ('Storage Vault', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded),
      ('Search & Tags', Icons.search_outlined, Icons.search_rounded),
      ('Custom Rules', Icons.tune_outlined, Icons.tune_rounded),
      ('Auto-Watch', Icons.bolt_outlined, Icons.bolt_rounded),
      ('Time Machine', Icons.history_outlined, Icons.history_rounded),
      ('Settings', Icons.settings_outlined, Icons.settings_rounded),
    ];

    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              _SideNav(
                index: _index,
                destinations: railDestinations,
                onSelect: (i) => setState(() => _index = i),
                state: widget.state,
              ),
            Expanded(child: screens[_index]),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              backgroundColor: isDark ? StudioColors.darkSurface : Colors.white,
              indicatorColor: StudioColors.electricIndigo.withValues(alpha: 0.15),
              selectedIndex: mobileDestinations.indexWhere((d) => d.$1 == _index).clamp(0, 4),
              onDestinationSelected: (idx) {
                setState(() => _index = mobileDestinations[idx].$1);
              },
              destinations: [
                for (final d in mobileDestinations)
                  NavigationDestination(
                    icon: Icon(d.$3),
                    selectedIcon: Icon(d.$4, color: StudioColors.electricIndigo),
                    label: d.$2,
                  ),
              ],
            ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.index,
    required this.destinations,
    required this.onSelect,
    required this.state,
  });

  final int index;
  final List<(String, IconData, IconData)> destinations;
  final ValueChanged<int> onSelect;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExtended = MediaQuery.of(context).size.width >= 1200;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? StudioColors.darkSurface : scheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: isDark ? StudioColors.darkBorder : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: NavigationRail(
        extended: isExtended,
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelType: isExtended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.selected,
        backgroundColor: Colors.transparent,
        indicatorColor: StudioColors.electricIndigo.withValues(alpha: 0.15),
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [StudioColors.electricIndigo, StudioColors.radiantViolet],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: StudioColors.electricIndigo.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (isExtended) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MISE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'STUDIO WORKBENCH',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        destinations: [
          for (final d in destinations)
            NavigationRailDestination(
              icon: Icon(d.$2),
              selectedIcon: Icon(d.$3, color: StudioColors.electricIndigo),
              label: Text(d.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
