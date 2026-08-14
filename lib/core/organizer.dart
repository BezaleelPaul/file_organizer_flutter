/// The core organizing engine: scan → plan → execute → undo.
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
  });

  final StorageService storage;
  final String root;
  final CategoryMap categories;
  final bool byExtension;
  final bool bySize;
  final bool byDate;
  final bool copyInsteadOfMove;

  /// Scan [root] and produce the planned moves (no changes made).
  Future<ScanResult> scan() async {
    final entries = await storage.listDirectory(root);
    final files = <PlannedMove>[];
    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final category = classifyFile(
        extension: extensionOf(entry.name),
        sizeBytes: entry.size,
        categories: categories,
        byExtension: byExtension,
        bySize: bySize,
      );
      final parts = <String>[category];
      if (byDate && category != 'Others') {
        parts.add(dateSubfolder(entry.modified));
      }
      files.add(PlannedMove(
        name: entry.name,
        size: entry.size,
        category: category,
        destination: parts.join('/'),
      ));
    }
    return ScanResult(root: root, files: files);
  }

  /// Execute a plan. Returns a journal entry that can be undone.
  ///
  /// [progress] is called with (done, total) after each file.
  Future<HistoryEntry> execute(
    List<PlannedMove> moves, {
    required void Function(int done, int total) progress,
    void Function(String message)? log,
  }) async {
    final total = moves.length;
    var done = 0;
    final journal = <MoveRecord>[];
    final createdDirs = <String>[];
    final claimed = <String, Set<String>>{};
    final existingNames = <String, Set<String>>{};
    final ensuredDirs = <String, String>{};

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
      final name = uniqueName(desired, {...pool, ...claimed[destDir]!});
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
      final destName = await freeName(destDir, move.name);
      log?.call('${move.name} → $destName');
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
