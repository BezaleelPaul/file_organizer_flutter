/// Controller for file indexing, search query parsing, tags, and smart collections.
library;

import 'dart:ui' show Color;

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/search/query.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:flutter/foundation.dart';

class SearchController extends ChangeNotifier {
  SearchController({required this.store});

  final SettingsStore store;

  List<Tag> tags = [];
  Map<String, List<String>> fileTags = {};
  List<SmartCollection> collections = [];

  static const tagPalette = <Color>[
    Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8),
    Color(0xFF64B5F6), Color(0xFF4DB6AC), Color(0xFF81C784),
    Color(0xFFFFB74D), Color(0xFFA1887F),
  ];

  Future<void> init() async {
    tags = await store.loadTags();
    fileTags = await store.loadFileTags();
    collections = await store.loadCollections();
    notifyListeners();
  }

  Future<void> setTags(List<Tag> newTags) async {
    tags = newTags;
    await store.saveTags(tags);
    notifyListeners();
  }

  Future<void> addTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (tags.any((t) => t.name == trimmed)) return;
    final tag = Tag(name: trimmed, color: tags.length % tagPalette.length);
    await setTags([...tags, tag]);
  }

  Future<void> removeTag(String name) async {
    await setTags(tags.where((t) => t.name != name).toList());
    var changed = false;
    fileTags.updateAll((_, names) {
      final filtered = names.where((n) => n != name).toList();
      changed = changed || filtered.length != names.length;
      return filtered;
    });
    fileTags.removeWhere((_, names) => names.isEmpty);
    if (changed) {
      await store.saveFileTags(fileTags);
    }
    notifyListeners();
  }

  Future<void> setFileTags(String path, List<String> names) async {
    final known = tags.map((t) => t.name).toSet();
    final filtered = names.where(known.contains).toList();
    if (filtered.isEmpty) {
      fileTags.remove(path);
    } else {
      fileTags[path] = filtered;
    }
    await store.saveFileTags(fileTags);
    notifyListeners();
  }

  Future<void> toggleFileTag(String path, String name) async {
    final current = [...(fileTags[path] ?? const <String>[])];
    if (current.contains(name)) {
      current.remove(name);
    } else {
      current.add(name);
    }
    await setFileTags(path, current);
  }

  Future<void> addCollection(String name, String query) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || query.trim().isEmpty) return;
    collections.add(SmartCollection(name: trimmed, query: query.trim()));
    await store.saveCollections(collections);
    notifyListeners();
  }

  Future<void> removeCollection(SmartCollection collection) async {
    collections.remove(collection);
    await store.saveCollections(collections);
    notifyListeners();
  }

  /// Evaluates a query string against files and applies tags.
  SearchQuery parse(String queryString) => parseQuery(queryString);
}
