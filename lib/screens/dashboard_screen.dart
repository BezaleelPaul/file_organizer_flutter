import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/screens/blitz_triage_screen.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/theme.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.state,
    this.onNavigateTab,
  });

  final AppState state;
  final ValueChanged<int>? onNavigateTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Workbench'),
        actions: [
          if (state.root != null && state.scan != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Blitz Triage'),
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.crimsonBurn,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (ctx) => BlitzTriageScreen(state: state),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entropy = calculateEntropy(state.scan?.files ?? []);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ErrorBanner(
              message: state.error!,
              onDismiss: () => state.clearError(),
            ),
          ),
        if (!state.storage.isSupported) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Browsers cannot access your local files. '
                      'Use the desktop or Android app to organize files.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _RootCard(state: state),
        const SizedBox(height: 20),
        _EntropyHeroCard(
          state: state,
          entropy: entropy,
          isDark: isDark,
        ),
        const SizedBox(height: 20),
        _RadarBentoRow(
          state: state,
          entropy: entropy,
          onNavigateTab: onNavigateTab,
        ),
        const SizedBox(height: 24),
        _ChefRecipesSection(state: state, onNavigateTab: onNavigateTab),
        const SizedBox(height: 24),
        _RecentActivity(state: state),
      ],
    );
  }
}

class _RootCard extends StatelessWidget {
  const _RootCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      color: isDark ? StudioColors.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StudioColors.electricIndigo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                color: StudioColors.electricIndigo,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'ACTIVE WORKSPACE',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (state.scan != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: StudioColors.emeraldZen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${state.scan!.files.length} files scanned',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: StudioColors.emeraldZen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.root ?? 'No folder selected — pick a folder to begin',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (state.root == null)
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Choose Folder'),
                style: FilledButton.styleFrom(
                  backgroundColor: StudioColors.electricIndigo,
                ),
                onPressed: () => state.pickRoot(),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.scan == null && state.busy == BusyKind.none)
                    FilledButton.icon(
                      icon: const Icon(Icons.radar_rounded, size: 18),
                      label: const Text('Scan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: StudioColors.electricIndigo,
                      ),
                      onPressed: () => state.scanRoot(),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => state.pickRoot(),
                    child: const Text('Change'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EntropyHeroCard extends StatelessWidget {
  const _EntropyHeroCard({
    required this.state,
    required this.entropy,
    required this.isDark,
  });

  final AppState state;
  final EntropyReport entropy;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = entropy.score;

    final Color scoreColor;
    if (score < 30) {
      scoreColor = StudioColors.emeraldZen;
    } else if (score < 60) {
      scoreColor = StudioColors.cyberAmber;
    } else {
      scoreColor = StudioColors.crimsonBurn;
    }

    return Card(
      color: isDark ? StudioColors.darkCard : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scoreColor.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular entropy gauge
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: score / 100.0,
                        strokeWidth: 6,
                        backgroundColor: scoreColor.withValues(alpha: 0.15),
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      '$score%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'ENTROPY & CHAOS RADAR',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scoreColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entropy.status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scoreColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entropy.tip,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.scan != null) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.bolt, size: 18),
                    label: const Text('Blitz Triage'),
                    style: FilledButton.styleFrom(
                      backgroundColor: StudioColors.crimsonBurn,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => BlitzTriageScreen(state: state),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarBentoRow extends StatelessWidget {
  const _RadarBentoRow({
    required this.state,
    required this.entropy,
    this.onNavigateTab,
  });

  final AppState state;
  final EntropyReport entropy;
  final ValueChanged<int>? onNavigateTab;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final pills = [
          _BentoInsightCard(
            icon: Icons.install_desktop_outlined,
            label: 'Installers / Packages',
            value: '${entropy.installerCount}',
            detail: entropy.installerCount > 0
                ? 'Disposable setup files cluttering root'
                : 'Zero installer clutter detected',
            color: StudioColors.crimsonBurn,
            actionLabel: 'Organize',
            onTap: () {
              if (onNavigateTab != null) onNavigateTab!(1);
            },
          ),
          _BentoInsightCard(
            icon: Icons.screenshot_monitor_outlined,
            label: 'Loose Screenshots',
            value: '${entropy.screenshotCount}',
            detail: entropy.screenshotCount > 0
                ? 'Ready to bundle into /Screenshots'
                : 'No loose screenshots found',
            color: StudioColors.cyanBeam,
            actionLabel: 'Sweep',
            onTap: () {
              if (onNavigateTab != null) onNavigateTab!(1);
            },
          ),
          _BentoInsightCard(
            icon: Icons.filter_tilt_shift_rounded,
            label: 'Duplicates & Waste',
            value: '${entropy.duplicateCount}',
            detail: 'Byte-identical redundant clones',
            color: StudioColors.radiantViolet,
            actionLabel: 'Inspect',
            onTap: () {
              if (onNavigateTab != null) onNavigateTab!(2);
            },
          ),
        ];

        if (isWide) {
          return Row(
            children: [
              for (var i = 0; i < pills.length; i++) ...[
                Expanded(child: pills[i]),
                if (i < pills.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var i = 0; i < pills.length; i++) ...[
              pills[i],
              if (i < pills.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _BentoInsightCard extends StatelessWidget {
  const _BentoInsightCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: isDark ? StudioColors.darkCard : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChefRecipesSection extends StatelessWidget {
  const _ChefRecipesSection({
    required this.state,
    this.onNavigateTab,
  });

  final AppState state;
  final ValueChanged<int>? onNavigateTab;

  void _applyRecipe(BuildContext context, ChefRecipe recipe) {
    // Add recipe rules into state
    for (final rule in recipe.patternRules) {
      if (!state.patternRules.any((r) => r.pattern == rule.pattern)) {
        state.patternRules.insert(0, rule);
      }
    }
    if (recipe.dateTemplate.isNotEmpty) {
      state.dateTemplate = recipe.dateTemplate;
      state.byDate = true;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded recipe: ${recipe.title}. Scanning folder…'),
      ),
    );

    if (state.root != null) {
      state.scanRoot().then((_) {
        if (onNavigateTab != null) onNavigateTab!(1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.restaurant_menu_rounded, size: 20, color: StudioColors.electricIndigo),
            const SizedBox(width: 8),
            const Text(
              'Chef\'s Playbook Recipes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              'Curated taxonomy strategies',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final recipes = ChefRecipe.all;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                mainAxisExtent: 140,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: recipes.length,
              itemBuilder: (context, i) {
                final r = recipes[i];
                return _RecipeCard(
                  recipe: r,
                  onApply: () => _applyRecipe(context, r),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.onApply,
  });

  final ChefRecipe recipe;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: isDark ? StudioColors.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              recipe.title,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: StudioColors.electricIndigo.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              recipe.badge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: StudioColors.electricIndigo,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        recipe.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onApply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Apply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Text(
              recipe.description,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recent = state.history.take(4).toList();

    return Card(
      color: isDark ? StudioColors.darkCard : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Time Machine & Audit Stream',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (recent.isNotEmpty)
                  Text(
                    '${state.history.length} journaled sessions',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No file movements recorded yet. Run a plan to build your audit timeline.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              )
            else
              for (final entry in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: StudioColors.electricIndigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      entry.action == 'copy'
                          ? Icons.copy_outlined
                          : entry.action == 'trash'
                              ? Icons.delete_sweep_outlined
                              : Icons.drive_file_move_outlined,
                      color: StudioColors.electricIndigo,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '${entry.count} files ${entry.action == 'copy' ? 'copied' : entry.action == 'trash' ? 'trashed' : 'organized'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${entry.timestamp.split('T').first} • ${_shortRoot(entry.root)}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, size: 14),
                    label: const Text('Undo', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: () => state.undo(entry),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _shortRoot(String root) {
    final parts = root.split(RegExp(r'[\\/]'));
    return parts.isNotEmpty ? parts.last : root;
  }
}
