/// JSON persistence for settings, history and watches via shared_preferences.
library;

import 'dart:convert';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _keyCategories = 'categories';
  static const _keyHistory = 'history';
  static const _keyWatches = 'watches';
  static const _keyLastRoot = 'last_root';

  Future<CategoryMap> loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCategories);
    if (raw == null) return normalizeCategories(defaultCategories);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return normalizeCategories(
        decoded.map((k, v) => MapEntry(
            k, (v as List<dynamic>).map((e) => e.toString()).toList())),
      );
    } catch (_) {
      return normalizeCategories(defaultCategories);
    }
  }

  Future<void> saveCategories(CategoryMap categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCategories, jsonEncode(categories));
  }

  Future<Map<String, bool>> loadFlags() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'byExtension': prefs.getBool('by_extension') ?? true,
      'bySize': prefs.getBool('by_size') ?? false,
      'byDate': prefs.getBool('by_date') ?? false,
      'copyInsteadOfMove': prefs.getBool('copy') ?? false,
    };
  }

  Future<void> saveFlags(Map<String, bool> flags) async {
    final prefs = await SharedPreferences.getInstance();
    flags.forEach((key, value) {
      prefs.setBool(_prefKey(key), value);
    });
  }

  String _prefKey(String key) => switch (key) {
        'byExtension' => 'by_extension',
        'bySize' => 'by_size',
        'byDate' => 'by_date',
        'copyInsteadOfMove' => 'copy',
        _ => key,
      };

  Future<void> saveLastRoot(String? root) async {
    final prefs = await SharedPreferences.getInstance();
    if (root == null) {
      await prefs.remove(_keyLastRoot);
    } else {
      await prefs.setString(_keyLastRoot, root);
    }
  }

  Future<String?> loadLastRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastRoot);
  }

  Future<List<HistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHistory);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHistory(List<HistoryEntry> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyHistory, jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<List<WatchJob>> loadWatches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyWatches);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => WatchJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveWatches(List<WatchJob> watches) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyWatches, jsonEncode(watches.map((e) => e.toJson()).toList()));
  }
}
