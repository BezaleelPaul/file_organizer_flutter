/// Application state: root folder, options, scan result, history, watches.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:file_organizer/ai/suggestion_engine.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/update_checker.dart' as update;
import 'package:file_organizer/core/storage/io_storage_service.dart';
import 'package:file_organizer/core/storage/storage_factory.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:file_organizer/services/desktop_service.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watcher/watcher.dart';

enum BusyKind { none, scanning, organizing, undo }

/// A user-facing result shown once an operation finishes.
class CompletionMessage {
  const CompletionMessage({
    required this.title,
    required this.message,
    this.success = true,
    this.undoEntry,
  });

  final String title;
  final String message;
  final bool success;
  final HistoryEntry? undoEntry;
}

class AppState extends ChangeNotifier {
  AppState({required this.store}) {
    _init();
  }

  final SettingsStore store;
  final StorageService storage = createStorageService();

  bool get osWatchSupported => _osWatchSupported;

  bool initialized = false;
  CompletionMessage? completion;

  CategoryMap categories = normalizeCategories(defaultCategories);
  bool byExtension = true;
  bool bySize = false;
  bool byDate = false;
  bool copyInsteadOfMove = false;
  bool detectDuplicates = false;
  String renameTemplate = '';
  String dateTemplate = '{year}-{month}';
  List<PatternRule> patternRules = [];
  List<AutoRule> autoRules = [];
  List<Tag> tags = [];
  Map<String, List<String>> fileTags = {};
  List<SmartCollection> collections = [];
  List<String> excludePatterns = [];
  Set<String> allowedCategories = {};
  bool launchAtStartup = false;
  bool minimizeToTray = true;
  update.UpdateInfo? availableUpdate;
  String appVersion = '';

  String? root;
  String? rootLabel;
  ScanResult? scan;

  /// Offline smart suggestions for the current scan (empty until loaded).
  List<Suggestion> suggestions = [];
  bool suggestionsLoading = false;
  List<HistoryEntry> history = [];
  List<WatchJob> watches = [];
  List<ScheduleJob> schedules = [];

  BusyKind busy = BusyKind.none;
  double progress = 0;
  String status = '';
  List<String> logLines = [];
  String? error;

  Timer? _watchTimer;
  Timer? _scheduleTimer;
  final Map<String, StreamSubscription<WatchEvent>> _osWatchers = {};
  final Map<String, Timer> _watchDebounces = {};
  bool _osWatchSupported = false;

  Future<void> _init() async {
    categories = await store.loadCategories();
    final flags = await store.loadFlags();
    byExtension = flags['byExtension'] ?? true;
    bySize = flags['bySize'] ?? false;
    byDate = flags['byDate'] ?? false;
    copyInsteadOfMove = flags['copyInsteadOfMove'] ?? false;
    detectDuplicates = await store.loadDetectDuplicates();
    renameTemplate = await store.loadRenameTemplate();
    dateTemplate = await store.loadDateTemplate();
    patternRules = await store.loadPatternRules();
    autoRules = await store.loadAutoRules();
    tags = await store.loadTags();
    fileTags = await store.loadFileTags();
    collections = await store.loadCollections();
    excludePatterns = await store.loadExcludes();
    allowedCategories = await store.loadAllowedCategories();
    history = await store.loadHistory();
    watches = await store.loadWatches();
    schedules = await store.loadSchedules();
    launchAtStartup = await store.loadLaunchAtStartup();
    minimizeToTray = await store.loadMinimizeToTray();
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      appVersion = '';
    }
    final lastRoot = await store.loadLastRoot();
    if (lastRoot != null) root = lastRoot;
    _osWatchSupported =
        storage is IoStorageService && !kIsWeb && FileSystemEntity.isWatchSupported;
    _startWatching();
    _startScheduler();
    initialized = true;
    notifyListeners();
  }

  /// Clear the pending completion message (after it has been shown).
  void consumeCompletion() {
    if (completion != null) {
      completion = null;
      notifyListeners();
    }
  }

  void _setBusy(BusyKind kind, [double p = 0]) {
    busy = kind;
    progress = p;
    error = null;
    notifyListeners();
  }
  void addLog(String line) {
    logLines.add('${DateTime.now().hour.toString().padLeft(2, '0')}:'
        '${DateTime.now().minute.toString().padLeft(2, '0')}:'
        '${DateTime.now().second.toString().padLeft(2, '0')}  $line');
    if (logLines.length > 200) {
      logLines.removeRange(0, logLines.length - 200);
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<bool> pickRoot() async {
    if (busy != BusyKind.none) return false;
    try {
      final picked = await storage.pickDirectory();
      if (picked == null) return false;
      root = picked;
      scan = null;
      await store.saveLastRoot(picked);
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> clearRoot() async {
    root = null;
    scan = null;
    await store.saveLastRoot(null);
    notifyListeners();
  }

  Future<void> scanRoot() async {
    final current = root;
    if (current == null || busy != BusyKind.none) return;
    _setBusy(BusyKind.scanning);
    addLog('Scanning…');
    try {
      final organizer = _organizer(current);
      scan = await organizer.scan();
      status = '${scan!.files.length} files found';
      addLog(status);
      completion = CompletionMessage(
        title: 'Scan complete',
        message:
            '${scan!.files.length} files found in ${scan!.root}. Review them '
            'before organizing.',
      );
      _setBusy(BusyKind.none);
      suggestions = [];
      _loadSuggestions();
    } catch (e) {
      error = e.toString();
      _setBusy(BusyKind.none);
    }
  }

  Future<void> organize() async {
    final current = root;
    final plan = scan?.files;
    if (current == null || plan == null || busy != BusyKind.none) return;
    if (plan.every((f) => f.skipped)) {
      error = 'Nothing selected to organize.';
      notifyListeners();
      return;
    }
    _setBusy(BusyKind.organizing);
    addLog('Organizing…');
    try {
      final organizer = _organizer(current);
      final entry = await organizer.execute(
        plan,
        progress: (done, total) {
          progress = total == 0 ? 1 : done / total;
          notifyListeners();
        },
        log: (m) => addLog(m),
      );
      history.insert(0, entry);
      if (history.length > 50) history.removeRange(50, history.length);
      await store.saveHistory(history);
      final folderCount =
          entry.moves.map((m) => m.destDir).toSet().length;
      status = '${entry.count} files ${copyInsteadOfMove ? 'copied' : 'moved'}';
      addLog(status);
      completion = CompletionMessage(
        title: copyInsteadOfMove ? 'Files copied' : 'All organized',
        message:
            '${entry.count} files ${copyInsteadOfMove ? 'copied' : 'moved'} into '
            '$folderCount ${folderCount == 1 ? 'folder' : 'folders'}.',
        undoEntry: entry,
      );
      _setBusy(BusyKind.none);
    } catch (e) {
      error = e.toString();
      addLog('ERROR: $e');
      _setBusy(BusyKind.none);
    }
  }

  Future<void> undo(HistoryEntry entry) async {
    if (busy != BusyKind.none) return;
    _setBusy(BusyKind.undo);
    addLog('Undoing ${entry.count} files…');
    try {
      final organizer = _organizer(entry.root);
      await organizer.undo(entry, log: (m) => addLog(m));
      history.removeWhere((h) => identical(h, entry) || h == entry);
      await store.saveHistory(history);
      status = 'Undone ${entry.count} files';
      addLog(status);
      completion = CompletionMessage(
        title: 'Changes undone',
        message: '${entry.count} files have been restored to their original '
            'folders.',
      );
      _setBusy(BusyKind.none);
    } catch (e) {
      error = e.toString();
      addLog('ERROR: $e');
      _setBusy(BusyKind.none);
    }
  }

  Organizer _organizer(String root) =>
    _organizerFor(root,
        byExtension: byExtension, bySize: bySize, byDate: byDate);

  Organizer _organizerFor(
    String root, {
    required bool byExtension,
    required bool bySize,
    required bool byDate,
  }) =>
      Organizer(
        storage: storage,
        root: root,
        categories: categories,
        byExtension: byExtension,
        bySize: bySize,
        byDate: byDate,
        copyInsteadOfMove: copyInsteadOfMove,
        patternRules: patternRules,
        autoRules: autoRules,
        detectDuplicates: detectDuplicates,
        renameTemplate: renameTemplate,
        dateTemplate: dateTemplate,
        excludePatterns: excludePatterns,
        allowedCategories: allowedCategories,
      );

  // ---- Rules ----

  /// Toggle whether a planned file should be skipped during organize.
  void setSkip(PlannedMove file, bool skipped) {
    file.skipped = skipped;
    notifyListeners();
  }

  /// Override the destination category for a planned file (null to clear).
  void setOverride(PlannedMove file, String? category) {
    file.overrideCategory = (category == null || category == file.category)
        ? null
        : category;
    notifyListeners();
  }

  // ---- Smart suggestions ----

  Future<void> _loadSuggestions() async {
    final plan = scan;
    if (plan == null) return;
    suggestionsLoading = true;
    suggestions = [];
    notifyListeners();
    try {
      suggestions = await SuggestionEngine(
        storage: storage,
        categories: categories,
      ).suggestAll(plan);
    } catch (_) {
      suggestions = [];
    } finally {
      suggestionsLoading = false;
      notifyListeners();
    }
  }

  /// Apply one suggestion to its planned file.
  void applySuggestion(Suggestion suggestion) {
    final plan = scan;
    if (plan == null) return;
    for (final file in plan.files) {
      if (file.name == suggestion.fileName) {
        setOverride(file, suggestion.toCategory);
        return;
      }
    }
  }

  void applyAllSuggestions() {
    for (final suggestion in suggestions) {
      applySuggestion(suggestion);
    }
  }

  Future<void> setCategories(CategoryMap categories) async {
    this.categories = normalizeCategories(categories);
    await store.saveCategories(this.categories);
    notifyListeners();
  }

  Future<void> setFlags({
    bool? byExtension,
    bool? bySize,
    bool? byDate,
    bool? copyInsteadOfMove,
    bool? detectDuplicates,
  }) async {
    this.byExtension = byExtension ?? this.byExtension;
    this.bySize = bySize ?? this.bySize;
    this.byDate = byDate ?? this.byDate;
    this.copyInsteadOfMove = copyInsteadOfMove ?? this.copyInsteadOfMove;
    this.detectDuplicates = detectDuplicates ?? this.detectDuplicates;
    await store.saveFlags({
      'byExtension': this.byExtension,
      'bySize': this.bySize,
      'byDate': this.byDate,
      'copyInsteadOfMove': this.copyInsteadOfMove,
    });
    await store.saveDetectDuplicates(this.detectDuplicates);
    notifyListeners();
  }

  Future<void> setPatternRules(List<PatternRule> rules) async {
    patternRules = rules.where((r) => r.pattern.isNotEmpty).toList();
    await store.savePatternRules(patternRules);
    notifyListeners();
  }

  Future<void> setAutoRules(List<AutoRule> rules) async {
    autoRules = rules;
    await store.saveAutoRules(autoRules);
    notifyListeners();
  }

  // ---- Tags ----

  /// The 8 colors of the tag palette (index = color of a Tag).
  static const tagPalette = <Color>[
    Color(0xFFE57373), Color(0xFFF06292), Color(0xFFBA68C8),
    Color(0xFF64B5F6), Color(0xFF4DB6AC), Color(0xFF81C784),
    Color(0xFFFFB74D), Color(0xFFA1887F),
  ];

  Future<void> setTags(List<Tag> tags) async {
    this.tags = tags;
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

  /// Set the tags on a single file (absolute path).
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

  /// Toggle a single tag on a file.
  Future<void> toggleFileTag(String path, String name) async {
    final current = [...(fileTags[path] ?? const <String>[])];
    if (current.contains(name)) {
      current.remove(name);
    } else {
      current.add(name);
    }
    await setFileTags(path, current);
  }

  // ---- Collections ----

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

  Future<void> setExcludePatterns(List<String> patterns) async {
    excludePatterns =
        patterns.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await store.saveExcludes(excludePatterns);
    notifyListeners();
  }

  Future<void> setAllowedCategories(Set<String> allowed) async {
    allowedCategories = allowed;
    await store.saveAllowedCategories(allowed);
    notifyListeners();
  }

  Future<void> setRenameTemplate(String template) async {
    renameTemplate = template.trim();
    await store.saveRenameTemplate(renameTemplate);
    notifyListeners();
  }

  Future<void> setDateTemplate(String template) async {
    dateTemplate = template.trim().isEmpty ? '{year}-{month}' : template.trim();
    await store.saveDateTemplate(dateTemplate);
    notifyListeners();
  }

  // ---- Watches ----

  void _startWatching() {
    _watchTimer?.cancel();
    for (final sub in _osWatchers.values) {
      sub.cancel();
    }
    _osWatchers.clear();
    for (final timer in _watchDebounces.values) {
      timer.cancel();
    }
    _watchDebounces.clear();

    if (watches.isEmpty) return;

    if (_osWatchSupported) {
      for (final watch in watches) {
        if (!watch.running) continue;
        try {
          final watcher = DirectoryWatcher(watch.root);
          final sub = watcher.events.listen((event) {
            if (event.type == ChangeType.REMOVE) return;
            _scheduleOsWatch(watch);
          }, onError: (Object e) {
            watch.error = e.toString();
            notifyListeners();
          });
          _osWatchers[watch.root] = sub;
        } catch (_) {
          // Fall back to polling for this folder.
        }
      }
    }

    // Polling safety net for Android (SAF) and any folder without OS events.
    // Each watch runs at its own chosen interval.
    _watchTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = DateTime.now();
      for (final watch in watches) {
        if (!watch.running) continue;
        if (_osWatchers.containsKey(watch.root)) continue;
        final last = watch.lastRun == null
            ? null
            : DateTime.tryParse(watch.lastRun!);
        if (last != null &&
            now.difference(last).inSeconds < watch.interval) {
          continue;
        }
        _runWatch(watch);
      }
    });
  }

  void _scheduleOsWatch(WatchJob watch) {
    _watchDebounces[watch.root]?.cancel();
    _watchDebounces[watch.root] = Timer(const Duration(seconds: 1), () {
      _runWatch(watch);
    });
  }

  Future<void> addWatch(String root, int interval, {
    bool byExtension = true,
    bool bySize = false,
    bool byDate = false,
  }) async {
    if (watches.any((w) => w.root == root)) {
      error = 'Already watching this folder.';
      notifyListeners();
      return;
    }
    watches.add(WatchJob(
      root: root,
      interval: interval,
      byExtension: byExtension,
      bySize: bySize,
      byDate: byDate,
    ));
    await store.saveWatches(watches);
    _startWatching();
    notifyListeners();
    _runWatch(watches.last);
  }

  Future<void> toggleWatch(WatchJob watch, bool running) async {
    watch.running = running;
    await store.saveWatches(watches);
    _startWatching();
    notifyListeners();
  }

  Future<void> removeWatch(WatchJob watch) async {
    watches.remove(watch);
    await store.saveWatches(watches);
    _startWatching();
    notifyListeners();
  }

  /// Run a single watch job immediately.
  Future<void> runWatchNow(WatchJob watch) => _runWatch(watch);

  Future<void> _runWatch(WatchJob watch) async {
    if (busy != BusyKind.none) return;
    try {
      final organizer = _organizerFor(
        watch.root,
        byExtension: watch.byExtension,
        bySize: watch.bySize,
        byDate: watch.byDate,
      );
      final plan = await organizer.scan();
      final actionable =
          plan.files.where((f) => !f.skipped && !f.isDuplicate).toList();
      if (actionable.isEmpty) {
        watch.lastRun = DateTime.now().toIso8601String();
        watch.lastCount = 0;
        notifyListeners();
        return;
      }
      final entry = await organizer.execute(
        actionable,
        progress: (_, _) {},
        log: (m) => addLog('[watch] $m'),
      );
      history.insert(0, entry);
      if (history.length > 50) history.removeRange(50, history.length);
      await store.saveHistory(history);
      watch.lastRun = DateTime.now().toIso8601String();
      watch.lastCount = entry.count;
      notifyListeners();
    } catch (e) {
      watch.error = e.toString();
      watch.running = false;
      await store.saveWatches(watches);
      notifyListeners();
    }
  }

  // ---- Schedules ----

  void _startScheduler() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSchedules();
    });
    _checkSchedules();
  }

  void _checkSchedules() {
    final now = DateTime.now();
    for (final job in schedules) {
      if (!job.enabled) continue;
      if (job.lastRun == null) {
        // Prime the schedule so the first run lands on its next slot.
        job.lastRun = now.toIso8601String();
        continue;
      }
      if (now.isBefore(job.nextRun(now))) continue;
      _runSchedule(job);
    }
  }

  Future<void> addSchedule(ScheduleJob job) async {
    schedules.add(job);
    await store.saveSchedules(schedules);
    notifyListeners();
  }

  Future<void> toggleSchedule(ScheduleJob job, bool enabled) async {
    job.enabled = enabled;
    await store.saveSchedules(schedules);
    notifyListeners();
  }

  Future<void> removeSchedule(ScheduleJob job) async {
    schedules.remove(job);
    await store.saveSchedules(schedules);
    notifyListeners();
  }

  Future<void> runScheduleNow(ScheduleJob job) => _runSchedule(job);

  Future<void> _runSchedule(ScheduleJob job) async {
    if (busy != BusyKind.none) return;
    try {
      final organizer = _organizerFor(
        job.root,
        byExtension: job.byExtension,
        bySize: job.bySize,
        byDate: job.byDate,
      );
      final plan = await organizer.scan();
      job.lastRun = DateTime.now().toIso8601String();
      final actionable =
          plan.files.where((f) => !f.skipped && !f.isDuplicate).toList();
      if (actionable.isEmpty) {
        job.lastCount = 0;
        notifyListeners();
        return;
      }
      final entry = await organizer.execute(
        actionable,
        progress: (_, _) {},
        log: (m) => addLog('[schedule] $m'),
      );
      history.insert(0, entry);
      if (history.length > 50) history.removeRange(50, history.length);
      await store.saveHistory(history);
      job.lastCount = entry.count;
      notifyListeners();
    } catch (e) {
      job.error = e.toString();
      job.enabled = false;
      await store.saveSchedules(schedules);
      notifyListeners();
    }
  }

  // ---- Trash ----

  /// Move [files] to the reversible in-folder Trash and record it for undo.
  Future<void> trashFiles(List<PlannedMove> files) async {
    final current = root;
    if (current == null || files.isEmpty || busy != BusyKind.none) return;
    _setBusy(BusyKind.organizing);
    addLog('Moving ${files.length} files to Trash…');
    try {
      final organizer = _organizer(current);
      final entry = await organizer.trash(files, log: (m) => addLog(m));
      for (final move in files) {
        move.skipped = true;
      }
      history.insert(0, entry);
      if (history.length > 50) history.removeRange(50, history.length);
      await store.saveHistory(history);
      status = '${entry.count} files trashed';
      addLog(status);
      completion = CompletionMessage(
        title: 'Moved to Trash',
        message: '${entry.count} files moved to the Trash folder. You can '
            'undo this from History.',
        undoEntry: entry,
      );
      _setBusy(BusyKind.none);
    } catch (e) {
      error = e.toString();
      addLog('ERROR: $e');
      _setBusy(BusyKind.none);
    }
  }

  /// Skip every file flagged as a duplicate.
  void skipAllDuplicates() {
    final scan = this.scan;
    if (scan == null) return;
    for (final file in scan.files) {
      if (file.isDuplicate) file.skipped = true;
    }
    notifyListeners();
  }

  // ---- Settings ----

  Future<void> setLaunchAtStartup(bool enabled) async {
    launchAtStartup = enabled;
    await store.saveLaunchAtStartup(enabled);
    await setLaunchAtStartupEnabled(enabled);
    notifyListeners();
  }

  Future<void> setMinimizeToTray(bool enabled) async {
    minimizeToTray = enabled;
    await store.saveMinimizeToTray(enabled);
    if (isDesktop) {
      await syncMinimizeToTray(enabled);
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    if (kIsWeb) return;
    final info = await update.checkForUpdates(currentVersion: appVersion);
    availableUpdate = info;
    notifyListeners();
  }

  void dismissUpdate() {
    availableUpdate = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _scheduleTimer?.cancel();
    for (final sub in _osWatchers.values) {
      sub.cancel();
    }
    for (final timer in _watchDebounces.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
