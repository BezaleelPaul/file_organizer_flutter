import 'dart:async';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/io_storage_service.dart';
import 'package:file_organizer/search/query.dart';
import 'package:file_organizer/search/search_service.dart';
import 'package:file_organizer/services/desktop_service.dart';
import 'package:file_organizer/state/app_state.dart';
import 'package:file_organizer/widgets/common.dart';
import 'package:flutter/material.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  SearchIndex? _index;
  bool _indexing = false;
  double _progress = 0;
  String? _error;
  final _query = TextEditingController();
  String _queryText = '';
  Timer? _debounce;
  int _progressCounter = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _buildIndex({bool force = false}) async {
    final root = widget.state.root;
    if (root == null) return;
    if (_indexing) return;
    if (!force && _index != null && _index!.root == root) return;

    setState(() {
      _indexing = true;
      _progress = 0;
      _error = null;
    });
    _progressCounter = 0;

    SearchIndex? index;
    if (!force) {
      index = await loadCachedIndex(root);
    }
    if (index == null) {
      try {
        index = await indexFolder(
          root,
          onProgress: (files) {
            _progressCounter += 1;
            if (_progressCounter % 64 == 0 && mounted) {
              setState(() => _progress = files / 5000);
            }
          },
        );
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    }
    if (index != null) {
      if (!force) saveCachedIndex(index);
      if (mounted) {
        setState(() {
          _index = index;
          _indexing = false;
          _progress = 1;
        });
      }
    } else if (mounted) {
      setState(() {
        _indexing = false;
        _error ??= 'Could not index this folder.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Search'),
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Search'),
              Tab(text: 'Tags'),
              Tab(text: 'Collections'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _searchTab(context),
            _tagsTab(context),
            _collectionsTab(context),
          ],
        ),
      ),
    );
  }

  Widget _searchTab(BuildContext context) {
    if (widget.state.storage is! IoStorageService) {
      return const EmptyState(
        icon: Icons.desktop_windows_outlined,
        title: 'Search is a desktop feature',
        message:
            'Indexed search works on Windows, macOS and Linux. It is not '
            'available in this build.',
      );
    }
    if (widget.state.root == null) {
      return EmptyState(
        icon: Icons.manage_search_outlined,
        title: 'Search a folder',
        message:
            'Pick a folder and Mise will index every file inside it, then '
            'answer instant queries like  *.pdf  type:image  tag:work  >100MB.',
        action: PrimaryActionButton(
          label: 'Choose folder',
          icon: Icons.folder_open,
          onPressed: () async {
            await widget.state.pickRoot();
            if (widget.state.root != null) _buildIndex();
          },
        ),
      );
    }
    if (_index == null && _indexing) {
      return Center(
        child: SizedBox(
          width: 260,
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
                      'Indexing ${widget.state.root}…',
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
    return _searchView(context);
  }

  Widget _searchView(BuildContext context) {
    final index = _index;
    final scheme = Theme.of(context).colorScheme;
    final results = index?.runQuery(_queryText, tagsByPath: widget.state.fileTags) ??
        const <SearchEntry>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _query,
            autofocus: true,
            onChanged: (v) {
              _queryText = v;
              _onQueryChanged(v);
            },
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              suffixIcon: index == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(10),
                      child: TextButton(
                        onPressed: () => _buildIndex(force: true),
                        child: const Text('Reindex'),
                      ),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  index == null
                      ? 'Indexing folder…'
                      : '${index.entries.length} files  •  '
                          '${formatBytes(index.totalBytes)}  •  '
                          '${results.length} ${results.length == 1 ? 'match' : 'matches'}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              if (index != null)
                TextButton.icon(
                  onPressed: () async {
                    await widget.state.pickRoot();
                    if (widget.state.root != null) _buildIndex();
                  },
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Change folder'),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ErrorBanner(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        const Divider(height: 16),
        Expanded(
          child: results.isEmpty
              ? EmptyState(
                  icon: Icons.search_off,
                  title: _queryText.isEmpty ? 'Type to search' : 'No matches',
                  message: _queryText.isEmpty
                      ? 'Try  report  or  type:image  or  tag:work'
                      : 'Nothing in this folder matches "$_queryText".',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ResultRow(
                    entry: results[i],
                    state: widget.state,
                    scheme: scheme,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _tagsTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tags = widget.state.tags;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Tags',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Attach labels to files from search results, then filter with '
          'tag:work. A tag stays for life — even across re-organizations.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (tags.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No tags yet. Create your first one below.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                InputChip(
                  avatar: _TagDot(color: AppState.tagPalette[tag.color % AppState.tagPalette.length]),
                  label: Text(tag.name),
                  deleteButtonTooltipMessage: 'Delete tag',
                  onDeleted: () => widget.state.removeTag(tag.name),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _AddTagForm(state: widget.state),
          ),
        ),
      ],
    );
  }

  Widget _collectionsTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.state.root == null || _index == null) {
      return EmptyState(
        icon: Icons.auto_awesome_motion_outlined,
        title: 'Index a folder first',
        message:
            'Collections are saved searches. Pick a folder and let Mise index '
            'it so collections can count and open their files.',
        action: widget.state.root == null
            ? PrimaryActionButton(
                label: 'Choose folder',
                icon: Icons.folder_open,
                onPressed: () async {
                  await widget.state.pickRoot();
                  if (widget.state.root != null) _buildIndex();
                },
              )
            : PrimaryActionButton(
                label: 'Index folder',
                icon: Icons.search,
                onPressed: () => _buildIndex(force: true),
              ),
      );
    }
    final index = _index!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _AddCollectionForm(
              state: widget.state,
              index: index,
              tagsByPath: widget.state.fileTags,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.state.collections.isEmpty)
          Text('No collections yet. Save a search to keep it one tap away.',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          for (final collection in widget.state.collections)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.auto_awesome_motion_outlined, color: scheme.primary),
                title: Text(collection.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${collection.query}  •  ${index.runQuery(collection.query, tagsByPath: widget.state.fileTags).length} files',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Delete collection',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.state.removeCollection(collection),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CollectionResultsScreen(
                        state: widget.state,
                        index: index,
                        collection: collection,
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _AddTagForm extends StatefulWidget {
  const _AddTagForm({required this.state});

  final AppState state;

  @override
  State<_AddTagForm> createState() => _AddTagFormState();
}

class _AddTagFormState extends State<_AddTagForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.state.addTag(name);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'New tag, e.g. work, to-review, taxes…',
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 8),
        PrimaryActionButton(
          label: 'Add',
          icon: Icons.add,
          onPressed: _add,
        ),
      ],
    );
  }
}

class _AddCollectionForm extends StatefulWidget {
  const _AddCollectionForm({
    required this.state,
    required this.index,
    required this.tagsByPath,
  });

  final AppState state;
  final SearchIndex index;
  final Map<String, List<String>> tagsByPath;

  @override
  State<_AddCollectionForm> createState() => _AddCollectionFormState();
}

class _AddCollectionFormState extends State<_AddCollectionForm> {
  final _name = TextEditingController();
  final _query = TextEditingController();
  String _live = '';

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    super.dispose();
  }

  void _save() {
    widget.state.addCollection(_name.text, _query.text);
    _name.clear();
    _query.clear();
    setState(() => _live = '');
  }

  @override
  Widget build(BuildContext context) {
    final matches = _live.trim().isEmpty
        ? 0
        : widget.index.runQuery(_live, tagsByPath: widget.tagsByPath).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Save a search as a collection',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Collection name',
            hintText: 'e.g. Invoices to file',
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          onChanged: (v) => setState(() => _live = v),
          decoration: InputDecoration(
            labelText: 'Search query',
            hintText: 'e.g. *.pdf tag:taxes',
            helperText: matches == 0 ? null : 'Matches $matches file(s)',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Spacer(),
            PrimaryActionButton(
              label: 'Save collection',
              icon: Icons.bookmark_add_outlined,
              onPressed: _name.text.trim().isEmpty || _query.text.trim().isEmpty
                  ? null
                  : _save,
            ),
          ],
        ),
      ],
    );
  }
}

class _CollectionResultsScreen extends StatelessWidget {
  const _CollectionResultsScreen({
    required this.state,
    required this.index,
    required this.collection,
  });

  final AppState state;
  final SearchIndex index;
  final SmartCollection collection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = index.runQuery(collection.query, tagsByPath: state.fileTags);
    return Scaffold(
      appBar: AppBar(title: Text(collection.name)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '${collection.query}  •  ${results.length} files',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No files match',
                    message: 'Nothing in the indexed folder matches this query.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _ResultRow(
                      entry: results[i],
                      state: state,
                      scheme: scheme,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.entry,
    required this.state,
    required this.scheme,
  });

  final SearchEntry entry;
  final AppState state;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final icon = switch (entry.category) {
      'Images' => Icons.image_outlined,
      'Videos' => Icons.movie_outlined,
      'Music' => Icons.music_note_outlined,
      'Documents' => Icons.description_outlined,
      'Archives' => Icons.folder_zip_outlined,
      'Programs' || 'Installers' => Icons.apps_outlined,
      'Scripts' || 'Code' => Icons.code_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    final fileTags = state.fileTags[entry.path] ?? const <String>[];
    return ListTile(
      dense: true,
      leading: Icon(icon, color: scheme.primary),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.path}  •  ${formatBytes(entry.size)}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      isThreeLine: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fileTags.isNotEmpty)
            for (final tag in fileTags.take(2)) ...[
              _TagDot(color: _tagColor(state, tag)),
              const SizedBox(width: 4),
            ],
          IconButton(
            tooltip: 'Edit tags',
            icon: Icon(
              fileTags.isEmpty ? Icons.label_outline : Icons.label,
              color: fileTags.isEmpty ? scheme.outline : scheme.primary,
            ),
            onPressed: () => showTagPicker(context, state, entry.path),
          ),
        ],
      ),
      onTap: () => revealInFileManager(entry.path),
    );
  }
}

Color _tagColor(AppState state, String name) {
  final index = state.tags.indexWhere((t) => t.name == name);
  final colorIndex = index < 0 ? 0 : state.tags[index].color;
  return AppState.tagPalette[colorIndex % AppState.tagPalette.length];
}

/// Dialog for editing the tags on a single file.
Future<void> showTagPicker(
  BuildContext context,
  AppState state,
  String path,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _TagPickerDialog(state: state, path: path),
  );
}

class _TagPickerDialog extends StatefulWidget {
  const _TagPickerDialog({required this.state, required this.path});

  final AppState state;
  final String path;

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  late final Set<String> _selected =
      {...(widget.state.fileTags[widget.path] ?? const <String>[])};
  late final TextEditingController _newTag = TextEditingController();

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
    });
    widget.state.setFileTags(widget.path, _selected.toList());
  }

  void _createAndTag() {
    final name = _newTag.text.trim();
    if (name.isEmpty) return;
    widget.state.addTag(name);
    setState(() {
      _newTag.clear();
      _selected.add(name);
    });
    widget.state.setFileTags(widget.path, _selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.state.tags;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Tags — ${widget.path.split(RegExp(r'[\\/]')).last}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tags.isEmpty)
              Text('No tags yet. Create one below.',
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      avatar: _TagDot(
                          color: AppState.tagPalette[tag.color % AppState.tagPalette.length]),
                      label: Text(tag.name),
                      selected: _selected.contains(tag.name),
                      onSelected: (_) => _toggle(tag.name),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTag,
                    decoration: const InputDecoration(
                      hintText: 'New tag…',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _createAndTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Create and tag',
                  icon: const Icon(Icons.add),
                  onPressed: _createAndTag,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}