/// Indexing and search: build an in-memory file index for a folder, cache it
/// to disk for instant reopens, and run queries against it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_organizer/core/disk_scanner.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/search/query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One file in the search index.
class SearchEntry {
  SearchEntry({
    required this.path,
    required this.name,
    required this.ext,
    required this.size,
    required this.modified,
    required this.category,
  });

  final String path;
  final String name;

  /// Lower-cased extension with leading dot (e.g. `.pdf`, '' when none).
  final String ext;
  final int size;
  final DateTime modified;
  final String category;

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'ext': ext,
        'size': size,
        'modified': modified.toIso8601String(),
        'category': category,
      };

  factory SearchEntry.fromJson(Map<String, dynamic> json) => SearchEntry(
        path: json['path'] as String,
        name: json['name'] as String,
        ext: json['ext'] as String? ?? '',
        size: json['size'] as int,
        modified: DateTime.parse(json['modified'] as String),
        category: json['category'] as String? ?? 'Others',
      );
}

/// The searchable set of files for one root folder.
class SearchIndex {
  SearchIndex({required this.root, required this.entries});

  final String root;
  final List<SearchEntry> entries;

  int get totalBytes => entries.fold(0, (sum, e) => sum + e.size);

  /// All files matching [query], sorted by name then size.
  List<SearchEntry> runQuery(String query) {
    final parsed = parseQuery(query);
    if (parsed.isEmpty) return const [];
    final matches = entries.where((e) => matchQuery(
          parsed,
          name: e.name,
          path: e.path,
          ext: e.ext,
          size: e.size,
          modified: e.modified,
        ));
    return sortResults(matches.toList(), (e) => e.name, (e) => e.size);
  }
}

/// Recursively index [root] and return an in-memory index.
Future<SearchIndex> indexFolder(
  String root, {
  void Function(int files)? onProgress,
}) async {
  final scan = await scanTree(root, onProgress: onProgress);
  final categories = normalizeCategories(defaultCategories);
  final entries = <SearchEntry>[];
  for (final file in scan.files) {
    final category = classifyFile(
      extension: file.extension,
      sizeBytes: file.size,
      categories: categories,
      byExtension: true,
      bySize: false,
      patternRules: const [],
      fileName: file.name,
    );
    entries.add(SearchEntry(
      path: file.path,
      name: file.name,
      ext: file.extension,
      size: file.size,
      modified: file.modified,
      category: category,
    ));
  }
  return SearchIndex(root: root, entries: entries);
}

/// Load a previously cached index for [root], or null when none exists.
Future<SearchIndex?> loadCachedIndex(String root) async {
  try {
    final file = await _cacheFile(root);
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['root'] != root) return null;
    final entries = (data['entries'] as List<dynamic>)
        .map((e) => SearchEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return SearchIndex(root: root, entries: entries);
  } catch (_) {
    return null;
  }
}

/// Persist [index] to disk for fast reopens.
Future<void> saveCachedIndex(SearchIndex index) async {
  try {
    final file = await _cacheFile(index.root);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'root': index.root,
      'entries': index.entries.map((e) => e.toJson()).toList(),
    }));
  } catch (_) {
    // Cache is best-effort; never fail search over it.
  }
}

Future<File> _cacheFile(String root) async {
  final dir = await getApplicationSupportDirectory();
  final hash = sha1.convert(utf8.encode(root)).toString().substring(0, 12);
  return File(p.join(dir.path, 'mise_index_$hash.json'));
}