import 'package:crypto/crypto.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'dart:convert';

/// In-memory fake storage for unit tests.
class FakeStorage implements StorageService {
  final Map<String, List<FileEntry>> dirs = {};
  final Set<String> realDirs = {};

  void seed(String dir, List<String> names, {bool realDirectory = true}) {
    dirs[dir] = [
      for (final name in names)
        FileEntry(
          name: name,
          size: 100,
          isDirectory: false,
          modified: DateTime(2026, 8, 1),
        ),
    ];
    if (realDirectory) realDirs.add(dir);
  }

  /// Seed a file with an explicit size, so duplicate detection can group by
  /// (size, content hash). Files with the same name hash identically.
  void seedWithSize(String dir, String name, int size) {
    dirs[dir] ??= [];
    dirs[dir]!.add(FileEntry(
      name: name,
      size: size,
      isDirectory: false,
      modified: DateTime(2026, 8, 1),
    ));
    realDirs.add(dir);
  }

  @override
  bool get isSupported => true;

  @override
  String get label => 'fake';

  @override
  Future<String?> pickDirectory() async => '/fake';

  @override
  Future<List<FileEntry>> listDirectory(String directory) async {
    return List.of(dirs[directory] ?? []);
  }

  @override
  Future<bool> directoryExists(String directory, String name) async {
    final child = '$directory/$name';
    return realDirs.contains(child);
  }

  @override
  Future<String> ensureDirectory(String directory, String name) async {
    final child = '$directory/$name';
    realDirs.add(child);
    dirs.putIfAbsent(child, () => <FileEntry>[]);
    return child;
  }

  @override
  Future<void> moveFile(
      String srcDir, String srcName, String destDir, String destName) async {
    final src = dirs[srcDir]!.firstWhere((e) => e.name == srcName);
    dirs[srcDir]!.remove(src);
    dirs.putIfAbsent(destDir, () => <FileEntry>[]);
    dirs[destDir]!.add(FileEntry(
      name: destName,
      size: src.size,
      isDirectory: false,
      modified: src.modified,
    ));
  }

  @override
  Future<void> copyFile(
      String srcDir, String srcName, String destDir, String destName) async {
    final src = dirs[srcDir]!.firstWhere((e) => e.name == srcName);
    dirs.putIfAbsent(destDir, () => <FileEntry>[]);
    dirs[destDir]!.add(FileEntry(
      name: destName,
      size: src.size,
      isDirectory: false,
      modified: src.modified,
    ));
  }

  @override
  Future<void> deleteFile(String directory, String name) async {
    dirs[directory]?.removeWhere((e) => e.name == name);
  }

  @override
  Future<String?> fileHash(String directory, String name) async {
    final entry = dirs[directory]?.where((e) => e.name == name).firstOrNull;
    if (entry == null) return null;
    // Deterministic per size: two files with the same size in the fake are
    // treated as byte-identical, which is enough to exercise detection.
    return sha256.convert(utf8.encode('${entry.size}')).toString();
  }

  @override
  Future<bool> removeEmptyDirectory(String directory) async {
    if (dirs[directory]?.isEmpty ?? false) {
      dirs.remove(directory);
      realDirs.remove(directory);
      return true;
    }
    return false;
  }
}