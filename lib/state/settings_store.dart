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
  static const _keyPatternRules = 'pattern_rules';
  static const _keyAutoRules = 'auto_rules';
  static const _keyTags = 'tags';
  static const _keyFileTags = 'file_tags';
  static const _keyCollections = 'collections';
  static const _keyExcludes = 'excludes';
  static const _keyAllowedCategories = 'allowed_categories';
  static const _keyRenameTemplate = 'rename_template';
  static const _keyDateTemplate = 'date_template';
  static const _keyDetectDuplicates = 'detect_duplicates';

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

  Future<List<PatternRule>> loadPatternRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPatternRules);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PatternRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePatternRules(List<PatternRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyPatternRules, jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  Future<List<AutoRule>> loadAutoRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAutoRules);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => AutoRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAutoRules(List<AutoRule> rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyAutoRules, jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  Future<List<Tag>> loadTags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTags);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => Tag.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTags(List<Tag> tags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyTags, jsonEncode(tags.map((e) => e.toJson()).toList()));
  }

  Future<Map<String, List<String>>> loadFileTags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFileTags);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((path, names) => MapEntry(
          path, (names as List<dynamic>).map((e) => e.toString()).toList()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFileTags(Map<String, List<String>> fileTags) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFileTags, jsonEncode(fileTags));
  }

  Future<List<SmartCollection>> loadCollections() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCollections);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => SmartCollection.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCollections(List<SmartCollection> collections) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCollections,
        jsonEncode(collections.map((e) => e.toJson()).toList()));
  }

  Future<List<String>> loadExcludes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyExcludes) ?? [];
  }

  Future<void> saveExcludes(List<String> excludes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyExcludes, excludes);
  }

  Future<Set<String>> loadAllowedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyAllowedCategories)?.toSet() ?? {};
  }

  Future<void> saveAllowedCategories(Set<String> allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyAllowedCategories, allowed.toList());
  }

  Future<String> loadRenameTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRenameTemplate) ?? '';
  }

  Future<void> saveRenameTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRenameTemplate, template);
  }

  Future<String> loadDateTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDateTemplate) ?? '{year}-{month}';
  }

  Future<void> saveDateTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDateTemplate, template);
  }

  Future<bool> loadDetectDuplicates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDetectDuplicates) ?? false;
  }

  Future<void> saveDetectDuplicates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDetectDuplicates, value);
  }

  Future<bool> loadLaunchAtStartup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('launch_at_startup') ?? false;
  }

  Future<void> saveLaunchAtStartup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('launch_at_startup', value);
  }

  Future<bool> loadMinimizeToTray() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('minimize_to_tray') ?? true;
  }

  Future<void> saveMinimizeToTray(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('minimize_to_tray', value);
  }
}
