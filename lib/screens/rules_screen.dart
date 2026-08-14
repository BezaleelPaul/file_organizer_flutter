import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.state});

  final AppState state;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final TextEditingController _newName;
  final Map<String, TextEditingController> _extControllers = {};
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _newName = TextEditingController();
  }

  @override
  void dispose() {
    _newName.dispose();
    for (final controller in _extControllers.values) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _commit() {
    final updated = <String, List<String>>{};
    widget.state.categories.forEach((name, exts) {
      final controller = _extControllers[name];
      if (controller != null) {
        updated[name] = controller.text
            .split(RegExp(r'[,\s]+'))
            .where((e) => e.trim().isNotEmpty)
            .map((e) => e.startsWith('.') ? e : '.$e')
            .toList();
      } else {
        updated[name] = exts;
      }
    });
    widget.state.setCategories(updated);
  }

  void _addCategory() {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    if (widget.state.categories.containsKey(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" already exists.')),
      );
      return;
    }
    widget.state.setCategories({...widget.state.categories, name: <String>[]});
    _newName.clear();
  }

  void _removeCategory(String name) {
    if (name == 'Others') return;
    widget.state.setCategories(
        {...widget.state.categories}..remove(name));
  }

  void _reset() {
    widget.state.setCategories(normalizeCategories(defaultCategories));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = widget.state.categories;
    // Ensure a controller exists for every category.
    categories.forEach((name, _) {
      _extControllers.putIfAbsent(
          name, () => TextEditingController(text: categories[name]!.join(', ')));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rules'),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        controller: _scrollController,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to sort',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _FlagSwitch(
                    title: 'By extension',
                    subtitle: 'Sort files into their type folder (e.g. .jpg → Images)',
                    icon: Icons.extension_outlined,
                    value: widget.state.byExtension,
                    onChanged: (v) => widget.state
                        .setFlags(byExtension: v),
                  ),
                  _FlagSwitch(
                    title: 'By size',
                    subtitle: 'Small (<1 MB) / Medium (<100 MB) / Large',
                    icon: Icons.straighten_outlined,
                    value: widget.state.bySize,
                    onChanged: (v) =>
                        widget.state.setFlags(bySize: v),
                  ),
                  _FlagSwitch(
                    title: 'By date',
                    subtitle: 'Sub-folder per month like 2026-08',
                    icon: Icons.calendar_month_outlined,
                    value: widget.state.byDate,
                    onChanged: (v) =>
                        widget.state.setFlags(byDate: v),
                  ),
                  _FlagSwitch(
                    title: 'Copy instead of move',
                    subtitle: 'Keep the original files in place',
                    icon: Icons.copy_outlined,
                    value: widget.state.copyInsteadOfMove,
                    onChanged: (v) =>
                        widget.state.setFlags(copyInsteadOfMove: v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Category folders',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Add category',
                icon: const Icon(Icons.add),
                onPressed: _addCategory,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newName,
                  decoration: const InputDecoration(
                    hintText: 'New category name…',
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _addCategory(),
                ),
              ),
              const SizedBox(width: 8),
              PrimaryActionButton(
                label: 'Add',
                icon: Icons.add,
                onPressed: _addCategory,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final entry in categories.entries) ...[
                  _CategoryRow(
                    name: entry.key,
                    extensions: entry.value,
                    controller: _extControllers[entry.key]!,
                    removable: entry.key != 'Others',
                    onCommit: _commit,
                    onRemove: () => _removeCategory(entry.key),
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Files not matching any rule go into the Others folder.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FlagSwitch extends StatelessWidget {
  const _FlagSwitch({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      secondary: Icon(icon),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    required this.name,
    required this.extensions,
    required this.controller,
    required this.removable,
    required this.onCommit,
    required this.onRemove,
  });

  final String name;
  final List<String> extensions;
  final TextEditingController controller;
  final bool removable;
  final VoidCallback onCommit;
  final VoidCallback onRemove;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(Icons.folder_outlined, color: scheme.primary),
      title: Text(widget.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(widget.extensions.isEmpty
          ? 'No extensions yet'
          : widget.extensions.take(6).join(', ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.removable)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.onRemove,
            ),
          Icon(_open ? Icons.expand_less : Icons.expand_more),
        ],
      ),
      onExpansionChanged: (v) => setState(() => _open = v),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Extensions (comma separated)',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: widget.controller,
                decoration: InputDecoration(
                  hintText: '.pdf, .docx, .txt',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => widget.onCommit(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onCommit,
                  child: const Text('Save extensions'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
