/// Centralized History and Undo Journal Store.
///
/// Stores operation journals and undo transactions in the platform's
/// application support directory (e.g. `%APPDATA%\Mise` on Windows,
/// `~/Library/Application Support/Mise` on macOS, and app-private storage on mobile).
///
/// Replaces in-target folder journals with a centralized, tamper-resistant store.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_organizer/core/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class HistoryStore {
  HistoryStore({Directory? baseDir}) : _customBaseDir = baseDir;

  final Directory? _customBaseDir;
  static const _historyFileName = 'history.json';
  List<HistoryEntry>? _cached;

  Future<File> _getFile() async {
    Directory dir;
    if (_customBaseDir != null) {
      dir = _customBaseDir;
    } else {
      try {
        final support = await getApplicationSupportDirectory();
        dir = Directory(p.join(support.path, 'Mise'));
      } catch (_) {
        dir = Directory(p.join(Directory.current.path, '.mise_data'));
      }
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dir.path, _historyFileName));
  }

  /// Load all history entries, newest first.
  Future<List<HistoryEntry>> loadHistory() async {
    if (_cached != null) return _cached!;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cached = [];
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cached = [];
        return [];
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cached = decoded
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return _cached!;
    } catch (e) {
      debugPrint('Error loading centralized history: $e');
      _cached = [];
      return [];
    }
  }

  /// Save the entire history list to the app support directory.
  Future<void> saveHistory(List<HistoryEntry> entries) async {
    _cached = entries;
    try {
      final file = await _getFile();
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
    } catch (e) {
      debugPrint('Error saving centralized history: $e');
    }
  }

  /// Record a new completed run at the top of history.
  Future<void> record(HistoryEntry entry) async {
    final list = await loadHistory();
    list.insert(0, entry);
    if (list.length > 200) {
      list.removeRange(200, list.length);
    }
    await saveHistory(list);
  }

  /// Mark an entry as rolled back rather than deleting it, preserving the audit trail.
  Future<void> markRolledBack(HistoryEntry entry) async {
    final list = await loadHistory();
    final index = list.indexWhere(
        (e) => e.timestamp == entry.timestamp && e.root == entry.root);
    if (index >= 0) {
      list[index] = list[index].copyWith(status: 'rolled_back');
      await saveHistory(list);
    }
  }
}
