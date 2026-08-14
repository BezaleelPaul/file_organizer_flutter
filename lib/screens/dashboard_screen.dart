import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
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
                      'Use the Windows/macOS/Linux or Android app to organize files.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _RootCard(state: state),
        const SizedBox(height: 16),
        _StatsRow(state: state),
        const SizedBox(height: 16),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.folder_open, color: scheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Working folder',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.root ?? 'No folder selected',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (state.root == null)
              PrimaryActionButton(
                label: 'Choose folder',
                icon: Icons.add,
                onPressed: () => state.pickRoot(),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PrimaryActionButton(
                    label: 'Change',
                    icon: Icons.folder_open,
                    onPressed: () => state.pickRoot(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => state.clearRoot(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scan = state.scan;
    final categories = state.categories;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        final cards = [
          _StatCard(
            icon: Icons.category_outlined,
            label: 'Categories',
            value: '${categories.length}',
            color: Colors.indigo,
          ),
          _StatCard(
            icon: Icons.description_outlined,
            label: 'Files found',
            value: '${scan?.files.length ?? 0}',
            color: Colors.teal,
          ),
          _StatCard(
            icon: Icons.storage_outlined,
            label: 'Total size',
            value: formatBytes(scan?.totalBytes ?? 0),
            color: Colors.orange,
          ),
          _StatCard(
            icon: Icons.undo_outlined,
            label: 'Undoable ops',
            value: '${state.history.length}',
            color: Colors.pink,
          ),
        ];
        if (isWide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final card in cards) SizedBox(width: 160, child: card)],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
    final recent = state.history.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent activity',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing organized yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              )
            else
              for (final entry in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry.action == 'copy'
                        ? Icons.copy_outlined
                        : Icons.drive_file_move_outlined,
                    color: scheme.primary,
                  ),
                  title: Text(
                      '${entry.count} files ${entry.action == 'copy' ? 'copied' : 'moved'}'),
                  subtitle: Text(
                    '${entry.timestamp.split('T').first} • ${_shortRoot(entry.root)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () => state.undo(entry),
                    child: const Text('Undo'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _shortRoot(String root) {
    final parts = root.split('/');
    return parts.isNotEmpty ? parts.last : root;
  }
}
