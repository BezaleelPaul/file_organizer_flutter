import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/screens/auto_rule_screen.dart';
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
  late final TextEditingController _newPattern;
  late final TextEditingController _newRuleCategory;
  late final TextEditingController _newExclude;
  late final TextEditingController _renameTemplate;
  late final TextEditingController _dateTemplate;
  final Map<String, TextEditingController> _extControllers = {};
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _newName = TextEditingController();
    _newPattern = TextEditingController();
    _newRuleCategory = TextEditingController();
    _newExclude = TextEditingController();
    _renameTemplate = TextEditingController(text: widget.state.renameTemplate);
    _dateTemplate = TextEditingController(text: widget.state.dateTemplate);
  }

  @override
  void dispose() {
    _newName.dispose();
    _newPattern.dispose();
    _newRuleCategory.dispose();
    _newExclude.dispose();
    _renameTemplate.dispose();
    _dateTemplate.dispose();
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

  void _addPatternRule() {
    final pattern = _newPattern.text.trim();
    final category = _newRuleCategory.text.trim().isEmpty
        ? 'Others'
        : _newRuleCategory.text.trim();
    if (pattern.isEmpty) return;
    try {
      RegExp(pattern);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid pattern: ${e.message}')),
      );
      return;
    }
    widget.state.setPatternRules([
      ...widget.state.patternRules,
      PatternRule(pattern: pattern, category: category),
    ]);
    _newPattern.clear();
    _newRuleCategory.clear();
  }

  void _removePatternRule(PatternRule rule) {
    widget.state
        .setPatternRules(widget.state.patternRules.where((r) => r != rule).toList());
  }

  void _addExclude() {
    final pattern = _newExclude.text.trim();
    if (pattern.isEmpty) return;
    widget.state.setExcludePatterns([...widget.state.excludePatterns, pattern]);
    _newExclude.clear();
  }

  void _removeExclude(String pattern) {
    widget.state.setExcludePatterns(
        widget.state.excludePatterns.where((e) => e != pattern).toList());
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
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AutoRuleScreen(state: widget.state),
                ),
              );
            },
            icon: const Icon(Icons.rule_outlined),
            label: const Text('Auto rules'),
          ),
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
                  const Divider(height: 24),
                  _FlagSwitch(
                    title: 'Detect duplicates',
                    subtitle: 'Flag files that are byte-identical so you can skip them',
                    icon: Icons.content_copy_outlined,
                    value: widget.state.detectDuplicates,
                    onChanged: (v) =>
                        widget.state.setFlags(detectDuplicates: v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _renameTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Rename template',
                      hintText: '{name}_{category}_{year}-{month}-{day}',
                      helperText:
                          'Tokens: {name} {ext} {category} {year} {month} {day} {counter}',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) => widget.state
                        .setRenameTemplate(_renameTemplate.text),
                    onChanged: (_) => widget.state
                        .setRenameTemplate(_renameTemplate.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dateTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Date sub-folder template',
                      hintText: '{year}-{month}  or  {year}/{month}/{day}',
                      helperText: 'Used when "By date" is enabled',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: (_) =>
                        widget.state.setDateTemplate(_dateTemplate.text),
                    onChanged: (_) =>
                        widget.state.setDateTemplate(_dateTemplate.text),
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
                  Text('Name pattern rules',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Regex rules that route files to a folder by their name, '
                    'e.g. ^IMG_ → Images.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _newPattern,
                          decoration: const InputDecoration(
                            hintText: 'Regex, e.g. ^IMG_',
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _addPatternRule(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _newRuleCategory,
                          decoration: const InputDecoration(
                            hintText: 'Folder',
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _addPatternRule(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PrimaryActionButton(
                        label: 'Add',
                        icon: Icons.add,
                        onPressed: _addPatternRule,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.state.patternRules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No pattern rules yet.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    for (final rule in widget.state.patternRules)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Switch(
                          value: rule.enabled,
                          onChanged: (v) {
                            rule.enabled = v;
                            widget.state.setPatternRules(widget.state.patternRules);
                          },
                        ),
                        title: Text(
                            '${rule.pattern}  →  ${rule.category}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removePatternRule(rule),
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
                  Text('Excluded files',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    r'Regex patterns for files that should never be organized '
                    r'(e.g. \.tmp$).',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newExclude,
                          decoration: const InputDecoration(
                            hintText: r'Regex, e.g. \.tmp$',
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          onSubmitted: (_) => _addExclude(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PrimaryActionButton(
                        label: 'Add',
                        icon: Icons.add,
                        onPressed: _addExclude,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.state.excludePatterns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Nothing excluded.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final pattern in widget.state.excludePatterns)
                          Chip(
                            label: Text(pattern,
                                style: const TextStyle(fontFamily: 'monospace')),
                            onDeleted: () => _removeExclude(pattern),
                          ),
                      ],
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Allowed folders',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    'Turn off folders you never want created. Files that would '
                    'go there are sent to Others instead.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in categories.keys)
                        FilterChip(
                          label: Text(category),
                          selected: widget.state.allowedCategories.isEmpty ||
                              widget.state.allowedCategories.contains(category),
                          onSelected: (selected) {
                            final allowed = {...widget.state.allowedCategories};
                            if (selected) {
                              allowed.add(category);
                            } else {
                              allowed.remove(category);
                            }
                            widget.state.setAllowedCategories(allowed);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
