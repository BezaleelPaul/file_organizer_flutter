import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

/// The Schedule tab: background runs on an interval, daily, or on chosen
/// weekdays while Mise is running (including in the tray).
class ScheduleTab extends StatelessWidget {
  const ScheduleTab({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final schedules = state.schedules;
    if (schedules.isEmpty) {
      return EmptyState(
        icon: Icons.schedule_outlined,
        title: 'No scheduled runs',
        message:
            'Let Mise tidy a folder on a schedule — every few hours, every '
            'day at a time, or on chosen weekdays.',
        action: PrimaryActionButton(
          label: 'Schedule a run',
          icon: Icons.add,
          onPressed: () => _addSchedule(context),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PrimaryActionButton(
            label: 'Schedule a run',
            icon: Icons.add,
            onPressed: () => _addSchedule(context),
          ),
        ),
        const SizedBox(height: 16),
        for (final job in schedules)
          _ScheduleCard(
            state: state,
            job: job,
            onToggle: (enabled) => state.toggleSchedule(job, enabled),
            onRemove: () => state.removeSchedule(job),
            onRunNow: () => state.runScheduleNow(job),
          ),
      ],
    );
  }

  Future<void> _addSchedule(BuildContext context) async {
    final root = await state.storage.pickDirectory();
    if (root == null || !context.mounted) return;
    final job = await showDialog<ScheduleJob>(
      context: context,
      builder: (context) => _ScheduleFormDialog(root: root),
    );
    if (job == null || !context.mounted) return;
    await state.addSchedule(job);
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.state,
    required this.job,
    required this.onToggle,
    required this.onRemove,
    required this.onRunNow,
  });

  final AppState state;
  final ScheduleJob job;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = job.lastRun;
    final next = job.nextRun(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              job.enabled ? Icons.schedule : Icons.schedule_outlined,
              color: job.enabled ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.root,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(job.describe(),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  Text(
                    'Next: ${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')} ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: scheme.primary, fontSize: 12),
                  ),
                  if (last != null)
                    Text(
                      'Last run: ${last.split('T').first} ${last.split('T').last.substring(0, 8)} • ${job.lastCount} files',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  if (job.error != null)
                    Text('Error: ${job.error}',
                        style: TextStyle(color: scheme.error, fontSize: 12)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: job.enabled ? onRunNow : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Run now'),
            ),
            Switch(value: job.enabled, onChanged: onToggle),
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

class _ScheduleFormDialog extends StatefulWidget {
  const _ScheduleFormDialog({required this.root});

  final String root;

  @override
  State<_ScheduleFormDialog> createState() => _ScheduleFormDialogState();
}

class _ScheduleFormDialogState extends State<_ScheduleFormDialog> {
  String _mode = 'interval';
  int _intervalHours = 6;
  int _hour = 2;
  int _minute = 0;
  final Set<int> _weekdays = {1, 2, 3, 4, 5};
  bool _byExtension = true;
  bool _bySize = false;
  bool _byDate = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Schedule a run'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.root,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(
                  labelText: 'How often',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'interval', child: Text('Every N hours')),
                  DropdownMenuItem(value: 'daily', child: Text('Once a day')),
                  DropdownMenuItem(value: 'weekly', child: Text('On chosen weekdays')),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'interval'),
              ),
              if (_mode == 'interval') ...[
                const SizedBox(height: 12),
                Text('Every $_intervalHours hours'),
                Slider(
                  value: _intervalHours.toDouble(),
                  min: 1,
                  max: 72,
                  divisions: 71,
                  label: '$_intervalHours h',
                  onChanged: (v) => setState(() => _intervalHours = v.round()),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _hour,
                        decoration: const InputDecoration(
                          labelText: 'Hour',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var h = 0; h < 24; h++)
                            DropdownMenuItem(value: h, child: Text('$h')),
                        ],
                        onChanged: (v) => setState(() => _hour = v ?? _hour),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _minute,
                        decoration: const InputDecoration(
                          labelText: 'Minute',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('00')),
                          DropdownMenuItem(value: 15, child: Text('15')),
                          DropdownMenuItem(value: 30, child: Text('30')),
                          DropdownMenuItem(value: 45, child: Text('45')),
                        ],
                        onChanged: (v) => setState(() => _minute = v ?? _minute),
                      ),
                    ),
                  ],
                ),
                if (_mode == 'weekly') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_dayName(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (on) {
                            setState(() {
                              if (on) {
                                _weekdays.add(day);
                              } else {
                                _weekdays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ],
              const Divider(height: 24),
              Text('Sort by',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Extension'),
                value: _byExtension,
                onChanged: (v) => setState(() => _byExtension = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Size'),
                value: _bySize,
                onChanged: (v) => setState(() => _bySize = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Date'),
                value: _byDate,
                onChanged: (v) => setState(() => _byDate = v),
              ),
              const SizedBox(height: 8),
              Text(
                'Active while Mise is running, including minimized to the tray.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              ScheduleJob(
                root: widget.root,
                mode: _mode,
                intervalHours: _intervalHours,
                hour: _hour,
                minute: _minute,
                weekdays: _mode == 'weekly' ? _weekdays.toList() : const [],
                byExtension: _byExtension,
                bySize: _bySize,
                byDate: _byDate,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _dayName(int day) =>
      const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day];
}