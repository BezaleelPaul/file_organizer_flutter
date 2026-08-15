import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/search/query.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

/// Visual builder for first-class automation rules.
class AutoRuleScreen extends StatefulWidget {
  const AutoRuleScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AutoRuleScreen> createState() => _AutoRuleScreenState();
}

class _AutoRuleScreenState extends State<AutoRuleScreen> {
  AutoRule? _editing;
  bool _editorOpen = false;

  void _openEditor([AutoRule? rule]) {
    setState(() {
      _editing = rule;
      _editorOpen = true;
    });
  }

  void _closeEditor() {
    setState(() {
      _editing = null;
      _editorOpen = false;
    });
  }

  void _save(AutoRule rule) {
    final rules = [...widget.state.autoRules];
    final index = _editing == null
        ? -1
        : rules.indexWhere((r) => identical(r, _editing) || r == _editing);
    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    widget.state.setAutoRules(rules);
    _closeEditor();
  }

  void _remove(AutoRule rule) {
    widget.state.setAutoRules(
        widget.state.autoRules.where((r) => !identical(r, rule)).toList());
  }

  void _reorder(int oldIndex, int newIndex) {
    final rules = [...widget.state.autoRules];
    if (newIndex > oldIndex) newIndex -= 1;
    final rule = rules.removeAt(oldIndex);
    rules.insert(newIndex, rule);
    widget.state.setAutoRules(rules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto rules'),
        actions: [
          if (!_editorOpen)
            TextButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New rule'),
            ),
        ],
      ),
      floatingActionButton: !_editorOpen
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New rule'),
            )
          : null,
      body: _editorOpen ? _editorView(context) : _listView(context),
    );
  }

  Widget _listView(BuildContext context) {
    final rules = widget.state.autoRules;
    if (rules.isEmpty) {
      return EmptyState(
        icon: Icons.rule_outlined,
        title: 'No auto rules yet',
        message:
            'Build rules like "PDFs larger than 10MB from last month go to '
            'Archives". Rules are checked in order — the first match wins.',
        action: PrimaryActionButton(
          label: 'Build a rule',
          icon: Icons.add,
          onPressed: () => _openEditor(),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Rules run top to bottom; the first match wins. Drag to reorder.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.all(24),
            onReorder: _reorder,
            buildDefaultDragHandles: true,
            children: [
              for (final rule in rules)
                Card(
                  key: ValueKey(rule),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    leading: Switch(
                      value: rule.enabled,
                      onChanged: (v) {
                        rule.enabled = v;
                        widget.state.setAutoRules([...rules]);
                      },
                    ),
                    title: Text(
                      rule.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _describe(rule),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _openEditor(rule),
                    trailing: IconButton(
                      tooltip: 'Delete rule',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(rule),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editorView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _RuleEditor(
                key: ValueKey(_editing),
                initial: _editing,
                categories: widget.state.categories.keys.toList(),
                onSave: _save,
                onCancel: _closeEditor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A file must match every condition to be routed. Leave a condition '
            'empty to ignore it. Auto rules override the default '
            'extension-based sorting.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _describe(AutoRule rule) {
  final conditions = <String>[];
  if (rule.extensions.isNotEmpty) {
    conditions.add(rule.extensions.map((e) => '*$e').join(', '));
  }
  if (rule.namePattern.isNotEmpty) conditions.add('name: ${rule.namePattern}');
  if (rule.minSize != null) conditions.add('≥ ${formatBytes(rule.minSize!)}');
  if (rule.maxSize != null) conditions.add('≤ ${formatBytes(rule.maxSize!)}');
  if (rule.modifiedAfter != null) {
    conditions.add('after ${_shortDate(rule.modifiedAfter!)}');
  }
  if (rule.modifiedBefore != null) {
    conditions.add('before ${_shortDate(rule.modifiedBefore!)}');
  }
  if (conditions.isEmpty) conditions.add('any file');
  return '${conditions.join('  ')}  →  ${rule.category}';
}

String _shortDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum _ModifiedChoice { any, week, month, year, custom }

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    super.key,
    required this.initial,
    required this.categories,
    required this.onSave,
    required this.onCancel,
  });

  final AutoRule? initial;
  final List<String> categories;
  final ValueChanged<AutoRule> onSave;
  final VoidCallback onCancel;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController _name;
  late final TextEditingController _extensions;
  late final TextEditingController _namePattern;
  late final TextEditingController _minSize;
  late final TextEditingController _maxSize;
  late String _category;
  late bool _enabled;
  late _ModifiedChoice _modified;
  DateTime? _after;
  DateTime? _before;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.initial;
    final min = rule?.minSize;
    final max = rule?.maxSize;
    _name = TextEditingController(text: rule?.name ?? '');
    _extensions = TextEditingController(
        text: rule?.extensions.map((e) => e.replaceFirst('.', '')).join(', ') ?? '');
    _namePattern = TextEditingController(text: rule?.namePattern ?? '');
    _minSize = TextEditingController(text: min == null ? '' : formatBytes(min));
    _maxSize = TextEditingController(text: max == null ? '' : formatBytes(max));
    _category = rule?.category ?? 'Others';
    if (!widget.categories.contains(_category)) _category = 'Others';
    _enabled = rule?.enabled ?? true;
    _after = rule?.modifiedAfter;
    _before = rule?.modifiedBefore;
    _modified = _after == null && _before == null
        ? _ModifiedChoice.any
        : _ModifiedChoice.custom;
  }

  @override
  void dispose() {
    _name.dispose();
    _extensions.dispose();
    _namePattern.dispose();
    _minSize.dispose();
    _maxSize.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the rule a name.');
      return;
    }
    final pattern = _namePattern.text.trim();
    if (pattern.isNotEmpty) {
      try {
        RegExp(pattern);
      } on FormatException catch (e) {
        setState(() => _error = 'Invalid name pattern: ${e.message}');
        return;
      }
    }
    final minBytes = _minSize.text.trim().isEmpty
        ? null
        : parseSizeValue(_minSize.text.trim());
    final maxBytes = _maxSize.text.trim().isEmpty
        ? null
        : parseSizeValue(_maxSize.text.trim());
    if (minBytes == null && _minSize.text.trim().isNotEmpty) {
      setState(() => _error = 'Minimum size must look like 5MB, 500KB…');
      return;
    }
    if (maxBytes == null && _maxSize.text.trim().isNotEmpty) {
      setState(() => _error = 'Maximum size must look like 5MB, 500KB…');
      return;
    }
    final extensions = _extensions.text
        .split(RegExp(r'[,\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => (e.startsWith('.') ? e : '.$e').toLowerCase())
        .toList();

    DateTime? after;
    DateTime? before;
    final now = DateTime.now();
    switch (_modified) {
      case _ModifiedChoice.week:
        after = now.subtract(const Duration(days: 7));
      case _ModifiedChoice.month:
        after = now.subtract(const Duration(days: 30));
      case _ModifiedChoice.year:
        after = now.subtract(const Duration(days: 365));
      case _ModifiedChoice.custom:
        after = _after;
        before = _before;
      case _ModifiedChoice.any:
        break;
    }

    widget.onSave(AutoRule(
      name: name,
      category: _category,
      extensions: extensions,
      namePattern: pattern,
      minSize: minBytes,
      maxSize: maxBytes,
      modifiedAfter: after,
      modifiedBefore: before,
      enabled: _enabled,
    ));
  }

  Future<void> _pickDate(bool isAfter) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isAfter ? _after : _before) ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isAfter) {
        _after = picked;
      } else {
        _before = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Rule name',
                  hintText: 'e.g. Scanner PDFs',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Send to folder',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final category in widget.categories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const Divider(height: 24),
        Text('Conditions — a file must match all of them',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: _extensions,
          decoration: const InputDecoration(
            labelText: 'File extensions',
            hintText: 'pdf, jpg, docx  (leave empty for any)',
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _namePattern,
          decoration: const InputDecoration(
            labelText: 'Name pattern (regex)',
            hintText: r'^IMG_  or  (scan|receipt)',
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minSize,
                decoration: const InputDecoration(
                  labelText: 'Minimum size',
                  hintText: 'e.g. 5MB',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxSize,
                decoration: const InputDecoration(
                  labelText: 'Maximum size',
                  hintText: 'e.g. 500MB',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<_ModifiedChoice>(
                initialValue: _modified,
                decoration: const InputDecoration(
                  labelText: 'Modified',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: _ModifiedChoice.any, child: Text('Any time')),
                  DropdownMenuItem(
                      value: _ModifiedChoice.week, child: Text('Last 7 days')),
                  DropdownMenuItem(
                      value: _ModifiedChoice.month, child: Text('Last 30 days')),
                  DropdownMenuItem(
                      value: _ModifiedChoice.year, child: Text('Last year')),
                  DropdownMenuItem(
                      value: _ModifiedChoice.custom,
                      child: Text('Custom range…')),
                ],
                onChanged: (v) => setState(() => _modified = v ?? _ModifiedChoice.any),
              ),
            ),
            if (_modified == _ModifiedChoice.custom) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _pickDate(true),
                child: Text(_after == null
                    ? 'After: any'
                    : 'After: ${_shortDate(_after!)}'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _pickDate(false),
                child: Text(_before == null
                    ? 'Before: any'
                    : 'Before: ${_shortDate(_before!)}'),
              ),
            ],
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            PrimaryActionButton(
              label: 'Save rule',
              icon: Icons.check,
              onPressed: _save,
            ),
          ],
        ),
      ],
    );
  }
}