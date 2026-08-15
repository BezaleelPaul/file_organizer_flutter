/// The core organizing engine: scan → plan → execute → undo.
///
/// Supports extension/pattern/size classification, date-token subfolders,
/// rename templates, duplicate detection, exclude patterns, category
/// whitelists and a reversible in-folder Trash.
library;

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

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
      if (allowedCategories.isNotEmpty && !allowedCategories.contains(category)) {
        category = 'Others';
      }
      final parts = <String>[category];
      if (byDate && category != 'Others') {
        final sub = dateSubfolder(entry.modified, template: dateTemplate);
        if (sub.isNotEmpty) parts.add(sub);
      }
      files.add(PlannedMove(
        name: name,
        size: entry.size,
        category: category,
        destination: parts.join('/'),
        modified: entry.modified,
      ));
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
  Future<HistoryEntry> execute(
    List<PlannedMove> moves, {
    required void Function(int done, int total) progress,
    void Function(String message)? log,
    bool duplicatesToTrash = false,
  }) async {
    final total = moves.length;
    var done = 0;
    final journal = <MoveRecord>[];
    final createdDirs = <String>[];
    final claimed = <String, Set<String>>{};
    final existingNames = <String, Set<String>>{};
    final ensuredDirs = <String, String>{};
    var renameCounter = 0;

    Future<Set<String>> namesFor(String destDir) async {
      var names = existingNames[destDir];
      if (names == null) {
        names = (await storage.listDirectory(destDir))
            .map((e) => e.name)
            .toSet();
        existingNames[destDir] = names;
      }
      return names;
    }

    Future<String> destDirFor(PlannedMove move) async {
      final segments = move.effectiveCategory == move.category
          ? move.destination.split('/')
          : <String>[move.effectiveCategory];
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
        if (!existed) createdDirs.add(current);
      }
      return current;
    }

    Future<String> freeName(String destDir, String desired) async {
      final pool = await namesFor(destDir);
      claimed.putIfAbsent(destDir, () => <String>{});
      final name = uniqueName(desired, {...pool, ...claimed[destDir]!},
          caseInsensitive: storage.caseInsensitiveNames);
      pool.add(name);
      claimed[destDir]!.add(name);
      return name;
    }

    for (final move in moves) {
      if (move.skipped) {
        done += 1;
        progress(done, total);
        continue;
      }
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
        if (!renameTemplate.contains('{ext}') && ext.isNotEmpty &&
            !rendered.endsWith(ext)) {
          rendered = '$rendered$ext';
        }
        destName = rendered;
        renameCounter += 1;
      }
      destName = await freeName(destDir, destName);
      log?.call('${move.name} → $destName');
      if (move.isDuplicate && duplicatesToTrash) {
        final trashDir = await _ensureTrash();
        final trashName = await freeName(trashDir, move.name);
        await storage.moveFile(root, move.name, trashDir, trashName);
        journal.add(MoveRecord(
          srcDir: root,
          srcName: move.name,
          destDir: trashDir,
          destName: trashName,
        ));
      } else {
        if (copyInsteadOfMove) {
          await storage.copyFile(root, move.name, destDir, destName);
        } else {
          await storage.moveFile(root, move.name, destDir, destName);
        }
        journal.add(MoveRecord(
          srcDir: root,
          srcName: move.name,
          destDir: destDir,
          destName: destName,
        ));
      }
      done += 1;
      progress(done, total);
    }

    return HistoryEntry(
      timestamp: DateTime.now().toIso8601String(),
      action: copyInsteadOfMove ? 'copy' : 'move',
      root: root,
      createdDirs: createdDirs,
      moves: journal,
    );
  }

  /// Move [moves] into the reversible Trash folder inside the root.
  Future<HistoryEntry> trash(
    List<PlannedMove> moves, {
    void Function(String message)? log,
  }) async {
    final trashDir = await _ensureTrash();
    final journal = <MoveRecord>[];
    final claimed = <String>{};
    final existing =
        (await storage.listDirectory(trashDir)).map((e) => e.name).toSet();
    for (final move in moves) {
      final name = uniqueName(move.name, {...existing, ...claimed},
          caseInsensitive: storage.caseInsensitiveNames);
      existing.add(name);
      claimed.add(name);
      log?.call('${move.name} → Trash/$name');
      await storage.moveFile(root, move.name, trashDir, name);
      journal.add(MoveRecord(
        srcDir: root,
        srcName: move.name,
        destDir: trashDir,
        destName: name,
      ));
    }
    return HistoryEntry(
      timestamp: DateTime.now().toIso8601String(),
      action: 'trash',
      root: root,
      createdDirs: <String>[trashDir],
      moves: journal,
    );
  }

  Future<String> _ensureTrash() async {
    return storage.ensureDirectory(root, trashFolder);
  }

  /// Reverse a [HistoryEntry]: move every file back and remove empty dirs.
  Future<void> undo(
    HistoryEntry entry, {
    void Function(String message)? log,
  }) async {
    for (final record in entry.moves.reversed) {
      log?.call('Undo ${record.destName}');
      await storage.moveFile(
        record.destDir,
        record.destName,
        record.srcDir,
        record.srcName,
      );
    }
    for (final dir in entry.createdDirs.reversed) {
      await storage.removeEmptyDirectory(dir);
    }
  }
}
