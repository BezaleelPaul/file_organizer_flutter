import 'dart:async';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: _content(context),
    );
  }

  Widget _content(BuildContext context) {
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
            'answer instant queries like  *.pdf  type:image  >100MB.',
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
    final results = index?.runQuery(_queryText) ?? const <SearchEntry>[];

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
                      ? 'Try  report  or  type:image  or  >500MB'
                      : 'Nothing in this folder matches "$_queryText".',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _ResultRow(entry: results[i], scheme: scheme),
                ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.entry, required this.scheme});

  final SearchEntry entry;
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
    return ListTile(
      dense: true,
      leading: Icon(icon, color: scheme.primary),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.path}  •  ${formatBytes(entry.size)}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
      trailing: Text(entry.category,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
      onTap: () => revealInFileManager(entry.path),
    );
  }
}