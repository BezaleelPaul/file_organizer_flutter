/// Platform-agnostic file storage interface.
///
/// A directory is addressed by an opaque [String] handle: an absolute path on
/// desktop, or a SAF `content://` tree URI on Android. All operations go
/// through this interface so the organizer logic stays platform-free.
library;

import 'dart:typed_data';

import 'package:file_organizer/core/models.dart';

abstract class StorageService {
  /// Whether this platform can actually touch the user's files.
  bool get isSupported;

  /// Human-readable description of this storage backend.
  String get label;

  /// Let the user pick a folder to work on. Returns its handle, or null if
  /// cancelled or unsupported.
  Future<String?> pickDirectory();

  /// List the direct children of [directory].
  Future<List<FileEntry>> listDirectory(String directory);

  /// Whether a sub-directory named [name] exists inside [directory].
  Future<bool> directoryExists(String directory, String name);

  /// The handle for a child directory named [name] (creates it if needed).
  Future<String> ensureDirectory(String directory, String name);

  /// Move [srcName] from [srcDir] into [destDir] as [destName].
  Future<void> moveFile(String srcDir, String srcName, String destDir, String destName);

  /// Copy [srcName] from [srcDir] into [destDir] as [destName].
  Future<void> copyFile(String srcDir, String srcName, String destDir, String destName);

  /// Delete [name] inside [directory].
  Future<void> deleteFile(String directory, String name);

  /// Content hash for duplicate detection, or null when unsupported
  /// (e.g. Android SAF). The hash is stable for identical bytes.
  Future<String?> fileHash(String directory, String name);

  /// The first [length] bytes of a file, for content-based classification.
  /// Returns null when the backend cannot read contents.
  Future<Uint8List?> readHead(String directory, String name, int length);

  /// Remove [directory] if it is now empty. Returns true if removed.
  Future<bool> removeEmptyDirectory(String directory);
}