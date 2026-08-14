import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: state.history.isEmpty
          ? const EmptyState(
              icon: Icons.history_outlined,
              title: 'No organized runs yet',
              message:
                  'Every organize operation is recorded here so you can undo it.',
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final entry in state.history)
                  _HistoryCard(state: state, entry: entry),
              ],
            ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.state, required this.entry});

  final AppState state;
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime.tryParse(entry.timestamp);
    final label = date == null
        ? entry.timestamp
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            entry.action == 'copy'
                ? Icons.copy_outlined
                : Icons.drive_file_move_outlined,
            color: scheme.primary,
          ),
        ),
        title: Text(
            '${entry.count} files ${entry.action == 'copy' ? 'copied' : 'moved'}'),
        subtitle: Text(_shortRoot(entry.root), overflow: TextOverflow.ellipsis),
        trailing: TextButton(
          onPressed: () => _confirmUndo(context),
          child: const Text('Undo'),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
                const Divider(height: 16),
                for (final move in entry.moves.take(200))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.arrow_forward, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_short(move.srcDir)}/${move.srcName}  →  '
                            '${_short(move.destDir)}/${move.destName}',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmUndo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo this operation?'),
        content: Text('Move ${entry.count} files back to their original folder.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              state.undo(entry);
            },
            child: const Text('Undo'),
          ),
        ],
      ),
    );
  }
}

String _shortRoot(String root) {
  final parts = root.split('/');
  return parts.isNotEmpty ? parts.last : root;
}

String _short(String path) {
  final parts = path.split('/');
  return parts.isNotEmpty ? parts.last : path;
}