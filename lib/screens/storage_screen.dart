import 'package:file_organizer/core/disk_scanner.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/io_storage_service.dart';
import 'package:file_organizer/services/desktop_service.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key, required this.state});

  final AppState state;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this);
  DiskScan? _scan;
  bool _scanning = false;
  double _progress = 0;
  List<DuplicateGroup>? _duplicates;
  bool _hashing = false;
  final _selected = <String>{};
  int _progressCounter = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    if (widget.state.root != null) _runScan();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.index == 1) _hashIfNeeded();
  }

  Future<void> _runScan() async {
    final root = widget.state.root;
    if (root == null || _scanning) return;
    setState(() {
      _scanning = true;
      _progress = 0;
      _scan = null;
      _duplicates = null;
      _selected.clear();
    });
    _progressCounter = 0;
    final scan = await scanTree(
      root,
      onProgress: (files) {
        _progressCounter += 1;
        if (_progressCounter % 96 == 0 && mounted) {
          setState(() => _progress = files / 8000);
        }
      },
    );
    if (mounted) {
      setState(() {
        _scan = scan;
        _scanning = false;
        _progress = 1;
      });
      _hashIfNeeded();
    }
  }

  Future<void> _hashIfNeeded() async {
    final scan = _scan;
    if (scan == null || _duplicates != null || _hashing) return;
    setState(() => _hashing = true);
    final groups = await findDuplicates(scan);
    if (mounted) {
      setState(() {
        _duplicates = groups;
        _hashing = false;
      });
    }
  }

  Future<void> _trashSelected() async {
    final root = widget.state.root;
    final scan = _scan;
    if (root == null || scan == null) return;
    final items = scan.files.where((f) => _selected.contains(f.path)).toList();
    if (items.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final moved = await trashItems(root, items);
    if (!mounted) return;
    setState(() => _selected.clear());
    messenger.showSnackBar(
      SnackBar(
        content: Text('${moved.length} file${moved.length == 1 ? '' : 's'} moved to Trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await restoreItems(root, moved);
            if (mounted) _runScan();
          },
        ),
      ),
    );
    _runScan();
  }

  Future<void> _deleteEmpty() async {
    final scan = _scan;
    if (scan == null) return;
    final empty = emptyFolders(scan);
    if (empty.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete empty folders?'),
        content: Text('Remove ${empty.length} empty folder(s). This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var deleted = 0;
    for (final dir in empty) {
      if (await widget.state.storage.removeEmptyDirectory(dir.path)) deleted += 1;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('$deleted empty folder(s) removed')),
    );
    _runScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Duplicates'),
            Tab(text: 'Large files'),
            Tab(text: 'Empty folders'),
          ],
        ),
      ),
      body: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    if (widget.state.storage is! IoStorageService) {
      return const EmptyState(
        icon: Icons.desktop_windows_outlined,
        title: 'Storage Center is a desktop feature',
        message:
            'Deep disk analysis works on Windows, macOS and Linux. It is not '
            'available in this build.',
      );
    }
    if (widget.state.root == null) {
      return EmptyState(
        icon: Icons.storage_outlined,
        title: 'Analyze a folder',
        message:
            'Pick a folder to see what is using space, find byte-identical '
            'duplicates, the largest files and empty folders.',
        action: PrimaryActionButton(
          label: 'Choose folder',
          icon: Icons.folder_open,
          onPressed: () async {
            await widget.state.pickRoot();
            if (widget.state.root != null) _runScan();
          },
        ),
      );
    }
    if (_scan == null && _scanning) {
      return Center(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      'Analyzing ${widget.state.root}…',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SmoothProgressBar(value: _progress),
            ],
          ),
        ),
      );
    }
    final scan = _scan;
    if (scan == null) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not analyze this folder',
        message: 'Try a different folder.',
      );
    }
    return TabBarView(
      controller: _tabs,
      children: [
        _OverviewTab(scan: scan, onRescan: _runScan),
        _DuplicatesTab(
          scan: scan,
          groups: _duplicates,
          hashing: _hashing,
          selected: _selected,
          onToggle: (path) => setState(() {
            if (!_selected.remove(path)) _selected.add(path);
          }),
          onTrash: _trashSelected,
        ),
        _LargeTab(
          scan: scan,
          selected: _selected,
          onToggle: (path) => setState(() {
            if (!_selected.remove(path)) _selected.add(path);
          }),
          onTrash: _trashSelected,
        ),
        _EmptyTab(scan: scan, onDelete: _deleteEmpty),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.scan, required this.onRescan});

  final DiskScan scan;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = storageByCategory(scan.files)
      ..remove('Others');
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.bytes.compareTo(a.value.bytes));
    final total = scan.totalBytes;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${scan.files.length} files',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${formatBytes(total)} in ${scan.root}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rescan'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                _CategoryRow(
                  name: sorted[i].key,
                  stat: sorted[i].value,
                  total: total,
                ),
                if (i < sorted.length - 1) const Divider(height: 1),
              ],
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No files found.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.name,
    required this.stat,
    required this.total,
  });

  final String name;
  final CategoryStat stat;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total == 0 ? 0.0 : stat.bytes / total;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${stat.count} • ${formatBytes(stat.bytes)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class _DuplicatesTab extends StatelessWidget {
  const _DuplicatesTab({
    required this.scan,
    required this.groups,
    required this.hashing,
    required this.selected,
    required this.onToggle,
    required this.onTrash,
  });

  final DiskScan scan;
  final List<DuplicateGroup>? groups;
  final bool hashing;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = groups ?? const <DuplicateGroup>[];
    final reclaimable = all.fold(0, (sum, g) => sum + g.reclaimable);

    if (hashing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(height: 12),
            Text('Comparing file contents…'),
          ],
        ),
      );
    }
    if (all.isEmpty) {
      return EmptyState(
        icon: Icons.verified_outlined,
        title: 'No duplicates found',
        message: 'Byte-identical files would be grouped here.',
        action: selected.isEmpty
            ? null
            : PrimaryActionButton(
                label: 'Move to Trash (${selected.length})',
                icon: Icons.delete_sweep_outlined,
                onPressed: onTrash,
              ),
      );
    }
    final wasteByCategory = <String, int>{};
    for (final group in all) {
      final ext = group.files.first.extension;
      final cat = classifyFile(
        extension: ext,
        sizeBytes: group.size,
        categories: normalizeCategories(defaultCategories),
        byExtension: true,
        bySize: false,
      );
      wasteByCategory[cat] = (wasteByCategory[cat] ?? 0) + group.reclaimable;
    }
    final sortedWaste = wasteByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    void selectAllDuplicatesExceptFirst() {
      for (final group in all) {
        for (var i = 1; i < group.files.length; i++) {
          if (!selected.contains(group.files[i].path)) {
            onToggle(group.files[i].path);
          }
        }
      }
    }

    return Column(
      children: [
        // Visual Reclaimable Space Treemap & Category Breakdown
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.tertiary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: scheme.tertiary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reclaimable: ${formatBytes(reclaimable)} across ${all.length} duplicate groups',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              if (reclaimable > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        for (final entry in sortedWaste)
                          if (entry.value > 0)
                            Expanded(
                              flex: ((entry.value / reclaimable) * 100)
                                  .round()
                                  .clamp(1, 100),
                              child: Container(
                                color: _wasteColor(entry.key, scheme),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 0.5),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in sortedWaste.take(4))
                      if (entry.value > 0)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: CircleAvatar(
                            backgroundColor: _wasteColor(entry.key, scheme),
                            radius: 4,
                          ),
                          label: Text(
                            '${entry.key}: ${formatBytes(entry.value)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: selectAllDuplicatesExceptFirst,
                icon: const Icon(Icons.select_all, size: 16),
                label: const Text('Select duplicates to clean'),
              ),
              const Spacer(),
              if (selected.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: onTrash,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text('Trash ${selected.length}'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              for (final group in all)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ExpansionTile(
                    leading: Icon(Icons.copy_all_outlined, color: scheme.tertiary),
                    title: Text(group.files.first.name,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${group.files.length} copies  •  ${formatBytes(group.size)} each  •  '
                      'reclaim ${formatBytes(group.reclaimable)}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                    children: [
                      for (final file in group.files)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(file.path),
                          onChanged: (_) => onToggle(file.path),
                          title: Text(file.path,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LargeTab extends StatelessWidget {
  const _LargeTab({
    required this.scan,
    required this.selected,
    required this.onToggle,
    required this.onTrash,
  });

  final DiskScan scan;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final files = largestFiles(scan);
    if (files.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nothing here yet',
        message: 'Scan a folder to list its largest files.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Largest ${files.length} files',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              if (selected.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: onTrash,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text('Trash ${selected.length}'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final file = files[i];
              return ListTile(
                dense: true,
                leading: Checkbox(
                  value: selected.contains(file.path),
                  onChanged: (_) => onToggle(file.path),
                ),
                title: Text(file.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  file.path,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                trailing: Text(formatBytes(file.size),
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w600)),
                onTap: () => revealInFileManager(file.path),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.scan, required this.onDelete});

  final DiskScan scan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = emptyFolders(scan);
    if (empty.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'No empty folders',
        message: 'Clean scan — nothing to tidy up.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${empty.length} empty folder(s)',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: empty.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => ListTile(
              dense: true,
              leading: Icon(Icons.folder_off_outlined, color: scheme.outline),
              title: Text(empty[i].path, overflow: TextOverflow.ellipsis),
              onTap: () => revealInFileManager(empty[i].path),
            ),
          ),
        ),
      ],
    );
  }
}

Color _wasteColor(String category, ColorScheme scheme) {
  return switch (category) {
    'Images' => const Color(0xFFAB47BC),
    'Videos' => const Color(0xFFFF7043),
    'Documents' => const Color(0xFF42A5F5),
    'Music' => const Color(0xFFEC407A),
    'Archives' => const Color(0xFFFFA726),
    'Programs' => const Color(0xFF26A69A),
    'Code' => const Color(0xFF5C6BC0),
    'Data' => const Color(0xFF78909C),
    _ => scheme.tertiary,
  };
}