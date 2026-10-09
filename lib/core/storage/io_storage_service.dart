/// dart:io storage backend for Windows, macOS and Linux.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class IoStorageService implements StorageService {
  @override
  bool get isSupported => true;

  @override
  String get label => 'Local file system';

  @override
  bool get caseInsensitiveNames => Platform.isWindows || Platform.isMacOS;

  @override
  Future<String?> pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select a folder to organize',
    );
    if (result == null || result.isEmpty) return null;
    final directory = Directory(result);
    if (!await directory.exists()) return null;
    return directory.absolute.path;
  }

  @override
  Future<List<FileEntry>> listDirectory(String directory) async {
    final list = Directory(directory).listSync(followLinks: false);
    final entries = <FileEntry>[];
    for (final entity in list) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (name == 'undo_history.json') continue;
      if (entity is File) {
        final stat = entity.statSync();
        entries.add(FileEntry(
          name: name,
          size: stat.size,
          isDirectory: false,
          modified: stat.modified,
        ));
      }
    }
    return entries;
  }

  @override
  Future<bool> directoryExists(String directory, String name) async {
    final dir = Directory(p.join(directory, name));
    return dir.existsSync();
  }

  @override
  Future<String> ensureDirectory(String directory, String name) async {
    final dir = Directory(p.join(directory, name));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.absolute.path;
  }

  @override
  Future<void> moveFile(String srcDir, String srcName, String destDir, String destName) async {
    final src = File(p.join(srcDir, srcName));
    final dest = File(p.join(destDir, destName));
    if (!dest.existsSync()) {
      src.renameSync(dest.path);
    } else {
      // Should not happen (unique names are pre-computed), but stay safe.
      final unique = _freePath(destDir, destName);
      src.renameSync(unique);
    }
  }

  @override
  Future<void> copyFile(String srcDir, String srcName, String destDir, String destName) async {
    final src = File(p.join(srcDir, srcName));
    final dest = File(p.join(destDir, destName));
    if (!dest.existsSync()) {
      src.copySync(dest.path);
    } else {
      // Should not happen (unique names are pre-computed), but never
      // overwrite an existing file — pick a free name instead.
      final unique = _freePath(destDir, destName);
      src.copySync(unique);
    }
  }

  @override
  Future<void> deleteFile(String directory, String name) async {
    final file = File(p.join(directory, name));
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<String?> fileHash(String directory, String name) async {
    final file = File(p.join(directory, name));
    if (!await file.exists()) return null;
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> readHead(String directory, String name, int length) async {
    final file = File(p.join(directory, name));
    if (!file.existsSync()) return null;
    final raf = await file.open();
    try {
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<bool> removeEmptyDirectory(String directory) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return false;
    final remaining = dir.listSync().where((e) => e.path.isNotEmpty).toList();
    if (remaining.isEmpty) {
      dir.deleteSync();
      return true;
    }
    return false;
  }

  String _freePath(String directory, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final suffix = dot > 0 ? name.substring(dot) : '';
    var counter = 1;
    while (File(p.join(directory, '$stem ($counter)$suffix')).existsSync()) {
      counter += 1;
    }
    return p.join(directory, '$stem ($counter)$suffix');
  }
}