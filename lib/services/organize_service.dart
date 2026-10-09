/// The single owner of the scan → plan → execute → journal pipeline.
///
/// Manual organize, watches, schedules and the tray action all funnel through
/// here so every operation gets the exact same scan/filter/execute/journal
/// behavior. [AppState] handles UI state (busy, progress, history, logs).
library;

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

/// Snapshot of the classify/execute settings at the time a run starts, so a
/// long background run is not affected by settings changed mid-flight.
class OrganizeConfig {
  OrganizeConfig({
    required this.categories,
    required this.byExtension,
    required this.bySize,
    required this.byDate,
    required this.copyInsteadOfMove,
    required this.detectDuplicates,
    required this.renameTemplate,
    required this.dateTemplate,
    required this.patternRules,
    required this.autoRules,
    required this.excludePatterns,
    required this.allowedCategories,
  });

  final Map<String, List<String>> categories;
  final bool byExtension;
  final bool bySize;
  final bool byDate;
  final bool copyInsteadOfMove;
  final bool detectDuplicates;
  final String renameTemplate;
  final String dateTemplate;
  final List<PatternRule> patternRules;
  final List<AutoRule> autoRules;
  final List<String> excludePatterns;
  final Set<String> allowedCategories;
}

/// Outcome of a background run (watch/schedule/tray): whether work happened
/// and the resulting journal entry.
class OrganizeResult {
  const OrganizeResult({required this.entry});

  final HistoryEntry? entry;

  bool get hasChanges => entry != null;
}

class OrganizeService {
  OrganizeService({required this.storage});

  final StorageService storage;

  Organizer _organizerFor(
    String root,
    OrganizeConfig config, {
    bool? byExtension,
    bool? bySize,
    bool? byDate,
  }) =>
      Organizer(
        storage: storage,
        root: root,
        categories: config.categories,
        byExtension: byExtension ?? config.byExtension,
        bySize: bySize ?? config.bySize,
        byDate: byDate ?? config.byDate,
        copyInsteadOfMove: config.copyInsteadOfMove,
        patternRules: config.patternRules,
        autoRules: config.autoRules,
        detectDuplicates: config.detectDuplicates,
        renameTemplate: config.renameTemplate,
        dateTemplate: config.dateTemplate,
        excludePatterns: config.excludePatterns,
        allowedCategories: config.allowedCategories,
      );

  /// Scan [root] and return the planned moves (no changes made).
  Future<ScanResult> scan(String root, OrganizeConfig config) =>
      _organizerFor(root, config).scan();

  /// Execute an existing plan (the reviewed manual plan). Returns the journal
  /// entry that can be undone.
  Future<HistoryEntry> executePlan(
    String root,
    List<PlannedMove> plan,
    OrganizeConfig config, {
    void Function(int done, int total)? progress,
    void Function(String message)? log,
  }) =>
      _organizerFor(root, config).execute(
        plan,
        progress: progress ?? (_, _) {},
        log: log,
      );

  /// Run the full pipeline for [root]: scan, filter out skipped files and
  /// (when [skipDuplicates]) duplicates, execute. Returns a result with the
  /// journal entry, or `entry == null` when nothing was actionable.
  Future<OrganizeResult> organize(
    String root,
    OrganizeConfig config, {
    bool skipDuplicates = true,
    void Function(String message)? log,
  }) async {
    final organizer = _organizerFor(root, config);
    final plan = await organizer.scan();
    final actionable = plan.files
        .where((f) =>
            !f.skipped && (skipDuplicates ? !f.isDuplicate : true))
        .toList();
    if (actionable.isEmpty) return const OrganizeResult(entry: null);
    final entry = await organizer.execute(
      actionable,
      progress: (_, _) {},
      log: log,
    );
    return OrganizeResult(entry: entry);
  }

  /// Move [moves] into the reversible Trash folder and record it for undo.
  Future<HistoryEntry> trash(
    String root,
    List<PlannedMove> moves,
    OrganizeConfig config, {
    void Function(String message)? log,
  }) =>
      _organizerFor(root, config).trash(moves, log: log);

  /// Reverse a journal entry and remove folders that became empty.
  Future<void> undo(
    HistoryEntry entry, {
    void Function(String message)? log,
  }) =>
      undoSelected(entry, entry.moves, log: log);

  /// Selectively reverse specific moves from a journal entry.
  Future<void> undoSelected(
    HistoryEntry entry,
    List<MoveRecord> selectedMoves, {
    void Function(String message)? log,
  }) async {
    final organizer = Organizer(
      storage: storage,
      root: entry.root,
      categories: const {},
    );
    await organizer.undoSelected(entry, selectedMoves, log: log);
  }
}