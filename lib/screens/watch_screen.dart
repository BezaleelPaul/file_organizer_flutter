import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.state});

  final AppState state;

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  int _interval = 60;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch folders'),
        actions: [
          if (state.watches.isNotEmpty)
            IconButton(
              tooltip: 'Run all now',
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                for (final watch in state.watches) {
                  if (watch.running) state.runWatchNow(watch);
                }
              },
            ),
        ],
      ),
      body: state.watches.isEmpty
          ? EmptyState(
              icon: Icons.visibility_outlined,
              title: 'No folders watched',
              message:
                  'Add a folder and File Organizer will keep it tidy in the '
                  'background, sorting new files as they appear.',
              action: PrimaryActionButton(
                label: 'Add a folder',
                icon: Icons.add,
                onPressed: _addWatch,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: PrimaryActionButton(
                    label: 'Add a folder',
                    icon: Icons.add,
                    onPressed: _addWatch,
                  ),
                ),
                const SizedBox(height: 16),
                for (final watch in state.watches)
                  _WatchCard(
                    watch: watch,
                    onToggle: (running) => state.toggleWatch(watch, running),
                    onRemove: () => state.removeWatch(watch),
                  ),
              ],
            ),
    );
  }

  Future<void> _addWatch() async {
    final root = await widget.state.storage.pickDirectory();
    if (root == null || !mounted) return;
    final interval = await showDialog<int>(
      context: context,
      builder: (context) => _IntervalDialog(initial: _interval),
    );
    if (interval == null || !mounted) return;
    _interval = interval;
    await widget.state.addWatch(root, interval);
    if (!mounted) return;
    if (widget.state.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.state.error!)));
      widget.state.clearError();
    }
  }
}

class _IntervalDialog extends StatefulWidget {
  const _IntervalDialog({required this.initial});

  final int initial;

  @override
  State<_IntervalDialog> createState() => _IntervalDialogState();
}

class _IntervalDialogState extends State<_IntervalDialog> {
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Watch interval'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Check every $_seconds seconds'),
          Slider(
            value: _seconds.toDouble(),
            min: 20,
            max: 600,
            divisions: 29,
            label: '$_seconds s',
            onChanged: (v) => setState(() => _seconds = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _seconds),
          child: const Text('Start watching'),
        ),
      ],
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.watch,
    required this.onToggle,
    required this.onRemove,
  });

  final WatchJob watch;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = watch.lastRun;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              watch.running ? Icons.visibility : Icons.visibility_off_outlined,
              color: watch.running ? Colors.green : scheme.outline,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(watch.root,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    'Every ${watch.interval}s • ${watch.byExtension ? 'extension, ' : ''}${watch.bySize ? 'size, ' : ''}${watch.byDate ? 'date' : ''}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  if (watch.error != null)
                    Text('Error: ${watch.error}',
                        style: TextStyle(color: scheme.error, fontSize: 12)),
                  if (last != null)
                    Text(
                      'Last run: ${last.split('T').first} ${last.split('T').last.substring(0, 8)} • '
                      '${watch.lastCount} files',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                ],
              ),
            ),
            Switch(
              value: watch.running,
              onChanged: onToggle,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
