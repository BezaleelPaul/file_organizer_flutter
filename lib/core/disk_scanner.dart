/// Recursive disk scanning for Storage Center and Search: walk a folder,
/// collect every file/directory with absolute paths, sizes and dates, and
/// classify files into categories. Desktop (dart:io) only.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:path/path.dart' as p;

/// One file or directory found by a deep scan.
class DiskItem {
  DiskItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.isDirectory,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
  final bool isDirectory;

  String get extension => extensionOf(name);
}

/// The result of recursively scanning [root].
class DiskScan {
  DiskScan({required this.root, required this.files, required this.dirs});

  final String root;
  final List<DiskItem> files;
  final List<DiskItem> dirs;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// A set of byte-identical files.
class DuplicateGroup {
  DuplicateGroup({required this.files});

  final List<DiskItem> files;

  int get size => files.first.size;

  /// Bytes freed by keeping a single copy.
  int get reclaimable => size * (files.length - 1);
}

/// Recursively walk [root] collecting every file and directory.
Future<DiskScan> scanTree(
  String root, {
  void Function(int files)? onProgress,
}) async {
  final files = <DiskItem>[];
  final dirs = <DiskItem>[];
  var count = 0;

  Future<void> walk(String dir) async {
    try {
      await for (final entity in Directory(dir).list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (name == 'undo_history.json') continue;
        try {
          if (entity is File) {
            final stat = entity.statSync();
            files.add(DiskItem(
              path: entity.path,
              name: name,
              size: stat.size,
              modified: stat.modified,
              isDirectory: false,
            ));
            count += 1;
            onProgress?.call(count);
          } else if (entity is Directory) {
            dirs.add(DiskItem(
              path: entity.path,
              name: name,
              size: 0,
              modified: entity.statSync().modified,
              isDirectory: true,
            ));
            await walk(entity.path);
          }
        } catch (_) {
          // Skip files that are locked or disappear mid-scan.
        }
      }
    } catch (_) {
      // Skip folders we cannot read.
    }
  }

  await walk(root);
  return DiskScan(root: root, files: files, dirs: dirs);
}

/// Group byte-identical files by (size, sha256).
Future<List<DuplicateGroup>> findDuplicates(
  DiskScan scan, {
  void Function(String message)? log,
}) async {
  final bySize = <int, List<DiskItem>>{};
  for (final file in scan.files) {
    bySize.putIfAbsent(file.size, () => []).add(file);
  }
  final groups = <DuplicateGroup>[];
  for (final sameSize in bySize.values) {
    if (sameSize.length < 2) continue;
    final byHash = <String, List<DiskItem>>{};
    for (final file in sameSize) {
      final hash = await _fileHash(file.path);
      if (hash == null) continue;
      byHash.putIfAbsent(hash, () => []).add(file);
    }
    for (final group in byHash.values) {
      if (group.length >= 2) groups.add(DuplicateGroup(files: group));
    }
  }
  groups.sort((a, b) => b.reclaimable.compareTo(a.reclaimable));
  return groups;
}

Future<String?> _fileHash(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return sha256.convert(await file.readAsBytes()).toString();
  } catch (_) {
    return null;
  }
}

/// The [files] sorted by size, largest first.
List<DiskItem> largestFiles(DiskScan scan, {int top = 100}) {
  final sorted = [...scan.files]..sort((a, b) => b.size.compareTo(a.size));
  return sorted.take(top).toList();
}

/// Directories that contain no visible files or sub-directories.
List<DiskItem> emptyFolders(DiskScan scan) {
  final empty = <DiskItem>[];
  for (final dir in scan.dirs) {
    try {
      final children = Directory(dir.path).listSync(followLinks: false);
      final visible =
          children.where((e) => !p.basename(e.path).startsWith('.'));
      if (visible.isEmpty) empty.add(dir);
    } catch (_) {}
  }
  empty.sort((a, b) => a.path.compareTo(b.path));
  return empty;
}

/// Used space per category, using the default extension rules.
Map<String, CategoryStat> storageByCategory(List<DiskItem> files) {
  final stats = <String, CategoryStat>{};
  for (final file in files) {
    final category = classifyFile(
      extension: file.extension,
      sizeBytes: file.size,
      categories: normalizeCategories(defaultCategories),
      byExtension: true,
      bySize: false,
      patternRules: const [],
      fileName: file.name,
    );
    final stat = stats.putIfAbsent(category, () => CategoryStat());
    stat.count += 1;
    stat.bytes += file.size;
  }
  return stats;
}

/// Move [items] into a reversible `Trash` folder inside [root].
/// Returns the destination paths (for undo).
Future<List<String>> trashItems(String root, List<DiskItem> items) async {
  final trashDir = Directory(p.join(root, 'Trash'));
  trashDir.createSync(recursive: true);
  final moved = <String>[];
  for (final item in items) {
    try {
      final source = File(item.path);
      if (!await source.exists()) continue;
      var name = item.name;
      var target = File(p.join(trashDir.path, name));
      var counter = 1;
      while (await target.exists()) {
        final dot = item.name.lastIndexOf('.');
        final stem = dot > 0 ? item.name.substring(0, dot) : item.name;
        final ext = dot > 0 ? item.name.substring(dot) : '';
        name = '$stem ($counter)$ext';
        target = File(p.join(trashDir.path, name));
        counter += 1;
      }
      await source.rename(target.path);
      moved.add(target.path);
    } catch (_) {}
  }
  return moved;
}

/// Restore [trashed] paths back to their original location (best effort).
Future<void> restoreItems(String root, List<String> trashed) async {
  final prefix = p.join(root, 'Trash') + p.separator;
  for (final path in trashed) {
    if (!path.startsWith(prefix)) continue;
    try {
      final source = File(path);
      if (!await source.exists()) continue;
      final original = p.join(root, p.basename(path));
      if (await File(original).exists()) continue;
      await source.rename(original);
    } catch (_) {}
  }
}