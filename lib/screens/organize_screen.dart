import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class OrganizeScreen extends StatelessWidget {
  const OrganizeScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organize')),
      body: Column(
        children: [
          Expanded(child: _content(context)),
          LogPanel(lines: state.logLines),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (!state.storage.isSupported) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'File access not available',
        message:
            'This platform cannot reach your local files. Install the desktop '
            'or Android version of File Organizer instead.',
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: state.root == null
          ? _NoRoot(state: state)
          : state.scan == null
              ? _ScanPrompt(key: const ValueKey('scan'), state: state)
              : _ReviewPanel(
                  key: const ValueKey('review'), state: state),
    );
  }
}

class _NoRoot extends StatelessWidget {
  const _NoRoot({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.folder_open_outlined,
      title: 'Pick a folder to organize',
      message:
          'Choose a folder full of unsorted files. File Organizer will plan '
          'moves for every file — you review them before anything changes.',
      action: PrimaryActionButton(
        label: 'Choose folder',
        icon: Icons.folder_open,
        onPressed: () => state.pickRoot(),
      ),
    );
  }
}

class _ScanBusy extends StatelessWidget {
  const _ScanBusy({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scanning folder…',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SmoothProgressBar(value: 0),
        ],
      ),
    );
  }
}

class _ScanPrompt extends StatelessWidget {
  const _ScanPrompt({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Folder',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(state.root!,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: state.busy == BusyKind.scanning
                      ? _ScanBusy(key: const ValueKey('busy'), state: state)
                      : Wrap(
                          key: const ValueKey('actions'),
                          spacing: 8,
                          children: [
                            PrimaryActionButton(
                              label: 'Change',
                              icon: Icons.folder_open,
                              onPressed: () => state.pickRoot(),
                              filled: false,
                            ),
                            PrimaryActionButton(
                              label: 'Scan folder',
                              icon: Icons.search,
                              onPressed: () => state.scanRoot(),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current rules',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _RuleChip(
                    label: 'By extension', active: state.byExtension),
                _RuleChip(label: 'By size', active: state.bySize),
                _RuleChip(label: 'By date', active: state.byDate),
                _RuleChip(
                    label: state.copyInsteadOfMove ? 'Copy' : 'Move',
                    active: true,
                    icon: state.copyInsteadOfMove
                        ? Icons.copy_outlined
                        : Icons.drive_file_move_outlined),
                const SizedBox(height: 8),
                Text('Edit rules on the Rules tab.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label, required this.active, this.icon});

  final String label;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: active ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 4)],
          Text(label),
        ],
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scan = state.scan!;
    final files = scan.files;
    final selectedCount =
        files.where((f) => !f.skipped).length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${files.length} files in ${scan.root}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '$selectedCount will be ${state.copyInsteadOfMove ? 'copied' : 'moved'} '
                    '• ${formatBytes(scan.totalBytes)} total',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (state.busy != BusyKind.organizing)
              PrimaryActionButton(
                label: selectedCount == 0
                    ? 'Nothing selected'
                    : '${state.copyInsteadOfMove ? 'Copy' : 'Organize'} ($selectedCount)',
                icon: state.copyInsteadOfMove
                    ? Icons.copy_outlined
                    : Icons.auto_fix_high,
                loading: state.busy == BusyKind.organizing,
                onPressed:
                    selectedCount == 0 ? null : () => state.organize(),
              ),
          ],
        ),
        if (state.busy == BusyKind.organizing) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Organizing files… ${(state.progress * 100).round()}%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${(state.progress * (scan.files.where((f) => !f.skipped).length)).round()} files',
                        style:
                            TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SmoothProgressBar(value: state.progress),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < files.length; i++) ...[
                _FileRow(
                  state: state,
                  file: files[i],
                  index: i,
                ),
                if (i < files.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.state,
    required this.file,
    required this.index,
  });

  final AppState state;
  final PlannedMove file;
  final int index;

  @override
  Widget build(BuildContext context) {
    final categories = state.categories.keys.toList();
    final category = file.effectiveCategory;
    return Opacity(
      opacity: file.skipped ? 0.5 : 1,
      child: ListTile(
        leading: Checkbox(
          value: !file.skipped,
          onChanged: state.busy == BusyKind.none
              ? (v) => state.setSkip(file, v != true)
              : null,
        ),
        title: Text(file.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: file.skipped ? TextDecoration.lineThrough : null,
            )),
        subtitle: Text(
          '${formatBytes(file.size)}  →  ${file.overrideCategory ?? file.destination}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            key: ValueKey('$index-$category'),
            initialValue: category,
            isDense: true,
            decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: state.busy == BusyKind.none
                ? (v) => state.setOverride(file, v)
                : null,
          ),
        ),
      ),
    );
  }
}
