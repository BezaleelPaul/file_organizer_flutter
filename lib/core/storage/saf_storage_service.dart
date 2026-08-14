/// Android Storage Access Framework backend.
///
/// Directories are addressed by `content://` tree URIs. The actual SAF work
/// happens on the Kotlin side (MainActivity) behind the
/// `com.bezaleel.file_organizer/saf` MethodChannel.
library;

import 'dart:async';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:flutter/services.dart';

class SafStorageService implements StorageService {
  static const _channel = MethodChannel('com.bezaleel.file_organizer/saf');

  @override
  bool get isSupported => true;

  @override
  String get label => 'Android storage';

  @override
  Future<String?> pickDirectory() async {
    try {
      final uri = await _channel.invokeMethod<String>('pickTree');
      return uri;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return null;
      rethrow;
    }
  }

  @override
  Future<List<FileEntry>> listDirectory(String directory) async {
    final raw = await _channel.invokeListMethod<Object?>('list', {'uri': directory});
    final entries = <FileEntry>[];
    for (final item in raw ?? <Object?>[]) {
      final map = Map<String, dynamic>.from(item as Map);
      final isDir = map['isDir'] == true;
      entries.add(FileEntry(
        name: map['name'] as String,
        size: (map['size'] as num?)?.toInt() ?? 0,
        isDirectory: isDir,
        modified: DateTime.fromMillisecondsSinceEpoch(
            (map['modified'] as num?)?.toInt() ?? 0),
      ));
    }
    return entries;
  }

  @override
  Future<bool> directoryExists(String directory, String name) async {
    final result = await _channel.invokeMethod<bool>(
        'existsDir', {'uri': directory, 'name': name});
    return result ?? false;
  }

  @override
  Future<String> ensureDirectory(String directory, String name) async {
    final result = await _channel.invokeMethod<String>(
        'ensureDir', {'uri': directory, 'name': name});
    return result!;
  }

  @override
  Future<void> moveFile(String srcDir, String srcName, String destDir, String destName) async {
    final srcUri = await _channel.invokeMethod<String>('childUri', {'uri': srcDir, 'name': srcName});
    if (srcUri == null) {
      throw StateError('Source file not found: $srcName');
    }
    await _channel.invokeMethod<void>('move', {'srcUri': srcUri, 'destDir': destDir, 'destName': destName});
  }

  @override
  Future<void> copyFile(String srcDir, String srcName, String destDir, String destName) async {
    final srcUri = await _channel.invokeMethod<String>('childUri', {'uri': srcDir, 'name': srcName});
    if (srcUri == null) {
      throw StateError('Source file not found: $srcName');
    }
    await _channel.invokeMethod<void>('copy', {'srcUri': srcUri, 'destDir': destDir, 'destName': destName});
  }

  @override
  Future<void> deleteFile(String directory, String name) async {
    final srcUri = await _channel.invokeMethod<String>('childUri', {'uri': directory, 'name': name});
    if (srcUri != null) {
      await _channel.invokeMethod<void>('delete', {'uri': srcUri});
    }
  }

  @override
  Future<String?> fileHash(String directory, String name) async => null;

  @override
  Future<bool> removeEmptyDirectory(String directory) async {
    // DocumentFile has no reliable empty-dir delete across providers; skip.
    return false;
  }
}