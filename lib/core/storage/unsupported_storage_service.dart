/// Storage backends that cannot touch the user's file system (web).
library;

import 'dart:typed_data';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';

class UnsupportedStorageService implements StorageService {
  @override
  bool get isSupported => false;

  @override
  String get label => 'Browser (no file access)';

  @override
  bool get caseInsensitiveNames => false;

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<FileEntry>> listDirectory(String directory) async => const [];

  @override
  Future<bool> directoryExists(String directory, String name) async => false;

  @override
  Future<String> ensureDirectory(String directory, String name) async => throw UnsupportedError('File access is not available on this platform.');

  @override
  Future<void> moveFile(String srcDir, String srcName, String destDir, String destName) async =>
      throw UnsupportedError('File access is not available on this platform.');

  @override
  Future<void> copyFile(String srcDir, String srcName, String destDir, String destName) async =>
      throw UnsupportedError('File access is not available on this platform.');

  @override
  Future<void> deleteFile(String directory, String name) async =>
      throw UnsupportedError('File access is not available on this platform.');

  @override
  Future<String?> fileHash(String directory, String name) async => null;

  @override
  Future<Uint8List?> readHead(String directory, String name, int length) async =>
      null;

  @override
  Future<bool> removeEmptyDirectory(String directory) async => false;
}