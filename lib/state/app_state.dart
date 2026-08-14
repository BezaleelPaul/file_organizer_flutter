/// Application state: root folder, options, scan result, history, watches.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/io_storage_service.dart';
import 'package:file_organizer/core/storage/storage_factory.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:flutter/foundation.dart';
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
  List<String> excludePatterns = [];
  Set<String> allowedCategories = {};

  String? root;
  String? rootLabel;
  ScanResult? scan;
  List<HistoryEntry> history = [];
  List<WatchJob> watches = [];

  BusyKind busy = BusyKind.none;
  double progress = 0;
  String status = '';
  List<String> logLines = [];
  String? error;

  Timer? _watchTimer;
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
    excludePatterns = await store.loadExcludes();
    allowedCategories = await store.loadAllowedCategories();
    history = await store.loadHistory();
    watches = await store.loadWatches();
    final lastRoot = await store.loadLastRoot();
    if (lastRoot != null) root = lastRoot;
    _osWatchSupported =
        storage is IoStorageService && !kIsWeb && FileSystemEntity.isWatchSupported;
    _startWatching();
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

  Organizer _organizer(String root) => Organizer(
        storage: storage,
        root: root,
        categories: categories,
        byExtension: byExtension,
        bySize: bySize,
        byDate: byDate,
        copyInsteadOfMove: copyInsteadOfMove,
        patternRules: patternRules,
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
    _watchTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      for (final watch in watches) {
        if (watch.running && !_osWatchers.containsKey(watch.root)) {
          _runWatch(watch);
        }
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
      final organizer = Organizer(
        storage: storage,
        root: watch.root,
        categories: categories,
        byExtension: watch.byExtension,
        bySize: watch.bySize,
        byDate: watch.byDate,
        patternRules: patternRules,
        detectDuplicates: detectDuplicates,
        renameTemplate: renameTemplate,
        dateTemplate: dateTemplate,
        excludePatterns: excludePatterns,
        allowedCategories: allowedCategories,
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

  @override
  void dispose() {
    _watchTimer?.cancel();
    for (final sub in _osWatchers.values) {
      sub.cancel();
    }
    for (final timer in _watchDebounces.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
