/// The core organizing engine: scan → plan → execute → undo.
///
/// Supports extension/pattern/size classification, date-token subfolders,
/// rename templates, duplicate detection, exclude patterns, category
/// whitelists and a reversible in-folder Trash.
library;

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

/// Thrown when an organize/trash run fails.
///
/// [entry] contains every move that completed before the failure. When
/// [rolledBack] is true those moves were already reversed and the folder is
/// unchanged; when false they still exist on disk and must be recorded so the
/// user can undo them.
class OrganizeFailure implements Exception {
  const OrganizeFailure(
    this.cause,
    this.entry, {
    required this.rolledBack,
    this.rollbackError,
  });

  final Object cause;
  final HistoryEntry entry;
  final bool rolledBack;
  final Object? rollbackError;

  @override
  String toString() {
    if (rolledBack) {
      return 'Organize failed and all completed moves were rolled back: $cause';
    }
    final detail = rollbackError == null
        ? ''
        : ' Rollback also failed: $rollbackError';
    return 'Organize failed after ${entry.count} completed '
        '${entry.count == 1 ? 'move' : 'moves'}: $cause.$detail';
  }
}

/// Thrown when an undo could not reverse every selected move.
class UndoFailure implements Exception {
  const UndoFailure(this.failures);

  final List<String> failures;

  @override
  String toString() =>
      'Could not undo ${failures.length} ${failures.length == 1 ? 'file' : 'files'}: '
      '${failures.join('; ')}';
}

class Organizer {
  Organizer({
    required this.storage,
    required this.root,
    required this.categories,
    this.byExtension = true,
    this.bySize = false,
    this.byDate = false,
    this.copyInsteadOfMove = false,
    this.patternRules = const [],
    this.autoRules = const [],
    this.detectDuplicates = false,
    this.renameTemplate = '',
    this.dateTemplate = '{year}-{month}',
    this.excludePatterns = const [],
    this.allowedCategories = const {},
  });

  final StorageService storage;
  final String root;
  final CategoryMap categories;
  final bool byExtension;
  final bool bySize;
  final bool byDate;
  final bool copyInsteadOfMove;

  /// Regex filename rules evaluated after extension matching.
  final List<PatternRule> patternRules;

  /// First-class automation rules built in the visual rule builder. They win
  /// over extension/pattern classification: the first enabled rule that
  /// matches overrides the file's category.
  final List<AutoRule> autoRules;

  /// When true, files that are byte-identical to another scanned file are
  /// flagged (`isDuplicate`) so the caller can skip or trash them.
  final bool detectDuplicates;

  /// Name template (`{name}`, `{category}`, `{year}`, `{counter}`, …) applied
  /// to every moved file. Empty means keep the original name.
  final String renameTemplate;

  /// Subfolder template for date sorting, e.g. `{year}-{month}` or
  /// `{year}/{month}`.
  final String dateTemplate;

  /// Regex patterns matched against file names to skip them during scan.
  final List<String> excludePatterns;

  /// When non-empty, only these categories are produced; everything else goes
  /// to `Others`.
  final Set<String> allowedCategories;

  /// The name of the reversible Trash folder created inside the root.
  static const trashFolder = 'Trash';

  /// Scan [root] and produce the planned moves (no changes made).
  Future<ScanResult> scan() async {
    final entries = await storage.listDirectory(root);
    final files = <PlannedMove>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final name = entry.name;
      if (name.startsWith('.') || isExcluded(name, excludePatterns)) continue;
      final ext = extensionOf(name);
      var category = classifyFile(
        extension: ext,
        sizeBytes: entry.size,
        categories: categories,
        byExtension: byExtension,
        bySize: bySize,
        patternRules: patternRules,
        fileName: name,
      );
      for (final rule in autoRules) {
        if (!rule.enabled) continue;
        if (rule.matches(
          fileName: name,
          extension: ext,
          size: entry.size,
          modified: entry.modified,
        )) {
          category = rule.category;
          break;
        }
      }
      if (allowedCategories.isNotEmpty &&
          !allowedCategories.contains(category)) {
        category = 'Others';
      }
      final parts = <String>[category];
      if (byDate && category != 'Others') {
        final sub = dateSubfolder(entry.modified, template: dateTemplate);
        if (sub.isNotEmpty) parts.addAll(splitTemplatePath(sub));
      }
      for (final part in parts) {
        if (!isSafePathSegment(part)) {
          throw FormatException(
            'Invalid folder name "$part" for "$name". Category and date '
            'templates must produce portable folder names.',
          );
        }
      }
      files.add(
        PlannedMove(
          name: name,
          size: entry.size,
          category: category,
          destination: parts.join('/'),
          modified: entry.modified,
        ),
      );
    }
    if (detectDuplicates) {
      await _markDuplicates(files);
    }
    return ScanResult(root: root, files: files);
  }

  /// Flag every file that is byte-identical to another scanned file.
  Future<void> _markDuplicates(List<PlannedMove> files) async {
    final bySize = <int, List<PlannedMove>>{};
    for (final file in files) {
      bySize.putIfAbsent(file.size, () => []).add(file);
    }
    final seenHashes = <String>{};
    for (final group in bySize.values) {
      if (group.length < 2) continue;
      final seenInGroup = <String>{};
      for (final file in group) {
        final hash = await storage.fileHash(root, file.name);
        if (hash == null) continue;
        if (seenInGroup.contains(hash) || seenHashes.contains(hash)) {
          file.isDuplicate = true;
        } else {
          seenInGroup.add(hash);
          seenHashes.add(hash);
        }
      }
    }
  }

  /// Execute a plan. Returns a journal entry that can be undone.
  ///
  /// Files flagged as duplicates are moved to the Trash folder instead of
  /// their destination when [duplicatesToTrash] is true; otherwise they are
  /// organized like every other file (callers normally skip them first).
  /// [progress] is called with (done, total) after each file.
  ///
  /// [beforeMove] runs before each rename/copy and [afterMove] immediately
  /// after it succeeds. Callers use these to write a crash-safe journal. When
  /// the run fails, completed moves are rolled back by default so the folder
  /// is never left half-organized; if rollback also fails the partial entry is
  /// returned inside [OrganizeFailure] so it can still be recorded and undone.
  Future<HistoryEntry> execute(
    List<PlannedMove> moves, {
    required void Function(int done, int total) progress,
    void Function(String message)? log,
    bool duplicatesToTrash = false,
    Future<void> Function(MoveRecord record)? beforeMove,
    Future<void> Function(MoveRecord record)? afterMove,
    Future<void> Function(String path)? onCreatedDir,
    bool rollbackOnError = true,
  }) async {
    final total = moves.length;
    var done = 0;
    final journal = <MoveRecord>[];
    final createdDirs = <String>[];
    final claimed = <String, Set<String>>{};
    final existingNames = <String, Set<String>>{};
    final ensuredDirs = <String, String>{};
    final timestamp = DateTime.now().toIso8601String();
    var renameCounter = 0;

    // Validate every destination before touching the disk. A bad category or
    // date template must fail before the first file moves.
    for (final move in moves) {
      if (move.skipped) continue;
      _segmentsFor(move);
    }

    Future<Set<String>> namesFor(String destDir) async {
      var names = existingNames[destDir];
      if (names == null) {
        names = (await storage.listDirectory(
          destDir,
        )).map((e) => e.name).toSet();
        existingNames[destDir] = names;
      }
      return names;
    }

    Future<String> destDirFor(PlannedMove move) async {
      final segments = _segmentsFor(move);
      var current = root;
      for (final segment in segments) {
        final existed = await storage.directoryExists(current, segment);
        final key = '$current/$segment';
        var dir = ensuredDirs[key];
        if (dir == null) {
          dir = await storage.ensureDirectory(current, segment);
          ensuredDirs[key] = dir;
        }
        current = dir;
        if (!existed) {
          createdDirs.add(current);
          await onCreatedDir?.call(current);
        }
      }
      return current;
    }

    Future<String> freeName(String destDir, String desired) async {
      final pool = await namesFor(destDir);
      claimed.putIfAbsent(destDir, () => <String>{});
      final name = uniqueName(desired, {
        ...pool,
        ...claimed[destDir]!,
      }, caseInsensitive: storage.caseInsensitiveNames);
      pool.add(name);
      claimed[destDir]!.add(name);
      return name;
    }

    Future<void> performMove(PlannedMove move) async {
      final destDir = await destDirFor(move);
      var destName = move.name;
      if (renameTemplate.isNotEmpty) {
        final dot = move.name.lastIndexOf('.');
        final stem = dot > 0 ? move.name.substring(0, dot) : move.name;
        final ext = dot > 0 ? move.name.substring(dot) : '';
        var rendered = applyTemplate(
          renameTemplate,
          stem: stem,
          extension: ext,
          category: move.effectiveCategory,
          modified: move.modified,
          counter: renameCounter,
        );
        // Never strip the original extension unless the template already uses
        // {ext} explicitly.
        if (!renameTemplate.contains('{ext}') &&
            ext.isNotEmpty &&
            !rendered.endsWith(ext)) {
          rendered = '$rendered$ext';
        }
        final safe = sanitizeFileName(rendered);
        if (safe == null) {
          log?.call(
            'Rename template produced an invalid name for ${move.name}; '
            'keeping the original name.',
          );
        } else {
          destName = safe;
        }
        renameCounter += 1;
      }
      destName = await freeName(destDir, destName);
      log?.call('${move.name} → $destName');

      late final MoveRecord record;
      if (move.isDuplicate && duplicatesToTrash) {
        final trashDir = await _ensureTrash();
        final trashName = await freeName(trashDir, move.name);
        record = MoveRecord(
          srcDir: root,
          srcName: move.name,
          destDir: trashDir,
          destName: trashName,
        );
        await beforeMove?.call(record);
        await storage.moveFile(root, move.name, trashDir, trashName);
      } else {
        record = MoveRecord(
          srcDir: root,
          srcName: move.name,
          destDir: destDir,
          destName: destName,
        );
        await beforeMove?.call(record);
        if (copyInsteadOfMove) {
          await storage.copyFile(root, move.name, destDir, destName);
        } else {
          await storage.moveFile(root, move.name, destDir, destName);
        }
      }
      journal.add(record);
      await afterMove?.call(record);
    }

    try {
      for (final move in moves) {
        if (move.skipped) {
          done += 1;
          progress(done, total);
          continue;
        }
        await performMove(move);
        done += 1;
        progress(done, total);
      }
    } catch (e) {
      final partial = HistoryEntry(
        timestamp: timestamp,
        action: copyInsteadOfMove ? 'copy' : 'move',
        root: root,
        createdDirs: List.of(createdDirs),
        moves: List.of(journal),
      );
      if (!rollbackOnError || journal.isEmpty) {
        throw OrganizeFailure(e, partial, rolledBack: journal.isEmpty);
      }
      try {
        await undoSelected(partial, partial.moves);
      } catch (rollbackError) {
        throw OrganizeFailure(
          e,
          partial,
          rolledBack: false,
          rollbackError: rollbackError,
        );
      }
      throw OrganizeFailure(e, _emptyEntry(partial), rolledBack: true);
    }

    return HistoryEntry(
      timestamp: timestamp,
      action: copyInsteadOfMove ? 'copy' : 'move',
      root: root,
      createdDirs: createdDirs,
      moves: journal,
    );
  }

  List<String> _segmentsFor(PlannedMove move) {
    final rawSegments = move.effectiveCategory == move.category
        ? move.destination.split('/')
        : <String>[move.effectiveCategory];
    final segments = <String>[];
    for (final raw in rawSegments) {
      final segment = raw.trim();
      if (!isSafePathSegment(segment)) {
        throw FormatException(
          'Refusing to create "$segment" for "${move.name}": the category '
          'must be a portable folder name and cannot contain "..", path '
          'separators or Windows reserved names.',
        );
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      throw FormatException('Empty destination for "${move.name}".');
    }
    return segments;
  }

  HistoryEntry _emptyEntry(HistoryEntry source) => HistoryEntry(
    timestamp: source.timestamp,
    action: source.action,
    root: source.root,
    createdDirs: const [],
    moves: const [],
  );

  /// Move [moves] into the reversible Trash folder inside the root.
  Future<HistoryEntry> trash(
    List<PlannedMove> moves, {
    void Function(String message)? log,
    Future<void> Function(MoveRecord record)? beforeMove,
    Future<void> Function(MoveRecord record)? afterMove,
    bool rollbackOnError = true,
  }) async {
    final trashDir = await _ensureTrash();
    final journal = <MoveRecord>[];
    final claimed = <String>{};
    final existing = (await storage.listDirectory(
      trashDir,
    )).map((e) => e.name).toSet();
    final timestamp = DateTime.now().toIso8601String();
    try {
      for (final move in moves) {
        final name = uniqueName(move.name, {
          ...existing,
          ...claimed,
        }, caseInsensitive: storage.caseInsensitiveNames);
        existing.add(name);
        claimed.add(name);
        log?.call('${move.name} → Trash/$name');
        final record = MoveRecord(
          srcDir: root,
          srcName: move.name,
          destDir: trashDir,
          destName: name,
        );
        await beforeMove?.call(record);
        await storage.moveFile(root, move.name, trashDir, name);
        journal.add(record);
        await afterMove?.call(record);
      }
    } catch (e) {
      final partial = HistoryEntry(
        timestamp: timestamp,
        action: 'trash',
        root: root,
        createdDirs: const [],
        moves: List.of(journal),
      );
      if (!rollbackOnError || journal.isEmpty) {
        throw OrganizeFailure(e, partial, rolledBack: journal.isEmpty);
      }
      try {
        await undoSelected(partial, partial.moves);
      } catch (rollbackError) {
        throw OrganizeFailure(
          e,
          partial,
          rolledBack: false,
          rollbackError: rollbackError,
        );
      }
      throw OrganizeFailure(e, _emptyEntry(partial), rolledBack: true);
    }
    return HistoryEntry(
      timestamp: timestamp,
      action: 'trash',
      root: root,
      createdDirs: <String>[trashDir],
      moves: journal,
    );
  }

  Future<String> _ensureTrash() async {
    return storage.ensureDirectory(root, trashFolder);
  }

  /// Reverse an entire [HistoryEntry]: move every file back and remove empty dirs.
  Future<void> undo(HistoryEntry entry, {void Function(String message)? log}) =>
      undoSelected(entry, entry.moves, log: log);

  /// Selectively reverse only the specified [selectedMoves] from a [HistoryEntry].
  ///
  /// Copies are deleted rather than moved back (the original still exists).
  /// Missing destinations are skipped so retrying an undo is safe. Every move
  /// is attempted even if one fails; failures are reported together in
  /// [UndoFailure] so the caller does not claim a partial undo succeeded.
  Future<void> undoSelected(
    HistoryEntry entry,
    List<MoveRecord> selectedMoves, {
    void Function(String message)? log,
  }) async {
    final failures = <String>[];
    for (final record in selectedMoves.reversed) {
      final exists = await storage.fileExists(record.destDir, record.destName);
      if (!exists) {
        log?.call('Skip ${record.destName}: already restored or removed.');
        continue;
      }
      try {
        if (entry.action == 'copy') {
          await storage.deleteFile(record.destDir, record.destName);
          log?.call('Removed copy ${record.destName}');
          continue;
        }
        var restoreName = record.srcName;
        if (await storage.fileExists(record.srcDir, record.srcName)) {
          final existing = (await storage.listDirectory(
            record.srcDir,
          )).map((e) => e.name).toSet();
          restoreName = uniqueName(
            record.srcName,
            existing,
            caseInsensitive: storage.caseInsensitiveNames,
          );
          log?.call(
            'Original name "${record.srcName}" is occupied; restoring as '
            '"$restoreName".',
          );
        }
        await storage.moveFile(
          record.destDir,
          record.destName,
          record.srcDir,
          restoreName,
        );
      } catch (e) {
        failures.add('${record.destName}: $e');
      }
    }
    for (final dir in entry.createdDirs.reversed) {
      try {
        await storage.removeEmptyDirectory(dir);
      } catch (_) {
        // A non-empty folder is expected when other files live there.
      }
    }
    if (failures.isNotEmpty) {
      throw UndoFailure(failures);
    }
  }
}
