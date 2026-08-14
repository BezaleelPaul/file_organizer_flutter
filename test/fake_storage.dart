import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

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
  Future<bool> removeEmptyDirectory(String directory) async {
    if (dirs[directory]?.isEmpty ?? false) {
      dirs.remove(directory);
      realDirs.remove(directory);
      return true;
    }
    return false;
  }
}