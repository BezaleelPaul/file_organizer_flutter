/// Centralized History and Undo Journal Store.
///
/// Stores operation journals and undo transactions in the platform's
/// application support directory (e.g. `%APPDATA%\Mise` on Windows,
/// `~/Library/Application Support/Mise` on macOS, and app-private storage on mobile).
///
/// Replaces in-target folder journals with a centralized, tamper-resistant store.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_organizer/core/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class HistoryStore {
  HistoryStore({Directory? baseDir}) : _customBaseDir = baseDir;

  final Directory? _customBaseDir;
  static const _historyFileName = 'history.json';
  List<HistoryEntry>? _cached;

  Future<File> _getFile() async {
    Directory dir;
    if (_customBaseDir != null) {
      dir = _customBaseDir;
    } else {
      try {
        final support = await getApplicationSupportDirectory();
        dir = Directory(p.join(support.path, 'Mise'));
      } catch (_) {
        dir = Directory(p.join(Directory.current.path, '.mise_data'));
      }
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dir.path, _historyFileName));
  }

  /// Load all history entries, newest first.
  Future<List<HistoryEntry>> loadHistory() async {
    if (_cached != null) return _cached!;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cached = [];
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cached = [];
        return [];
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cached = decoded
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return _cached!;
    } catch (e) {
      debugPrint('Error loading centralized history: $e');
      _cached = [];
      return [];
    }
  }

  /// Save the entire history list to the app support directory.
  Future<void> saveHistory(List<HistoryEntry> entries) async {
    _cached = entries;
    try {
      final file = await _getFile();
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
    } catch (e) {
      debugPrint('Error saving centralized history: $e');
    }
  }

  /// Record a new completed run at the top of history.
  Future<void> record(HistoryEntry entry) async {
    final list = await loadHistory();
    list.insert(0, entry);
    if (list.length > 200) {
      list.removeRange(200, list.length);
    }
    await saveHistory(list);
  }

  /// Mark an entry as rolled back rather than deleting it, preserving the audit trail.
  Future<void> markRolledBack(HistoryEntry entry) async {
    final list = await loadHistory();
    final index = list.indexWhere(
      (e) => e.timestamp == entry.timestamp && e.root == entry.root,
    );
    if (index >= 0) {
      list[index] = list[index].copyWith(status: 'rolled_back');
      await saveHistory(list);
    }
  }

  /// Start an append-only, crash-safe journal for one organize/trash run.
  Future<JournalWriter> startJournal({
    required String action,
    required String root,
  }) async {
    final historyFile = await _getFile();
    return JournalWriter.create(
      directory: historyFile.parent,
      action: action,
      root: root,
    );
  }

  /// Read and remove any journal left behind by a crash or forced shutdown.
  ///
  /// Only moves that were confirmed (a `done` line) or that can be verified on
  /// disk (destination exists, source gone) are returned. The result is marked
  /// `incomplete` so the UI can show that the run did not finish and still
  /// offer undo.
  Future<List<HistoryEntry>> recoverInFlight() async {
    final entries = <HistoryEntry>[];
    try {
      final historyFile = await _getFile();
      final dir = historyFile.parent;
      if (!dir.existsSync()) return entries;
      final files = dir.listSync().whereType<File>().where((file) {
        final name = p.basename(file.path);
        return name.startsWith('in_flight_') && name.endsWith('.jsonl');
      }).toList();
      for (final file in files) {
        final entry = await _readJournal(file);
        if (entry != null && entry.moves.isNotEmpty) {
          entries.add(entry);
        }
        try {
          await file.delete();
        } catch (e) {
          debugPrint('Error deleting recovered journal ${file.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('Error recovering in-flight journals: $e');
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<HistoryEntry?> _readJournal(File file) async {
    String? timestamp;
    String? action;
    String? root;
    final intents = <String, MoveRecord>{};
    final done = <String, MoveRecord>{};
    final dirs = <String>[];

    String keyOf(MoveRecord record) =>
        '${record.srcDir}|${record.srcName}|${record.destDir}|${record.destName}';

    final lines = await file.readAsLines();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        switch (data['type']) {
          case 'header':
            timestamp = data['timestamp'] as String?;
            action = data['action'] as String?;
            root = data['root'] as String?;
          case 'intent':
            final record = MoveRecord.fromJson(data);
            intents[keyOf(record)] = record;
          case 'done':
            final record = MoveRecord.fromJson(data);
            done[keyOf(record)] = record;
          case 'dir':
            final path = data['path'] as String?;
            if (path != null) dirs.add(path);
        }
      } catch (e) {
        // A crash can leave a partial final line. Keep the lines before it.
        debugPrint('Skipping malformed journal line in ${file.path}: $e');
      }
    }
    if (timestamp == null || action == null || root == null) return null;

    final confirmed = <String, MoveRecord>{...done};
    for (final entry in intents.entries) {
      if (confirmed.containsKey(entry.key)) continue;
      final record = entry.value;
      final dest = File(p.join(record.destDir, record.destName));
      if (!dest.existsSync()) continue;
      final src = File(p.join(record.srcDir, record.srcName));
      final applied = action == 'copy' || !src.existsSync();
      if (applied) confirmed[entry.key] = record;
    }

    return HistoryEntry(
      timestamp: timestamp,
      action: action,
      root: root,
      createdDirs: dirs,
      moves: confirmed.values.toList(),
      status: 'incomplete',
    );
  }
}

/// Append-only journal for a single organize/trash transaction.
///
/// Every intent is flushed to disk before the move, and every completed move
/// is flushed afterwards. [commit] deletes the journal once the final history
/// entry is safely stored; [discard] deletes it after a successful rollback.
class JournalWriter {
  JournalWriter._(
    this._file,
    this._raf,
    this._timestamp,
    this.action,
    this.root,
  );

  final File _file;
  final RandomAccessFile _raf;
  final String _timestamp;
  final String action;
  final String root;
  bool _closed = false;

  static Future<JournalWriter> create({
    required Directory directory,
    required String action,
    required String root,
  }) async {
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final now = DateTime.now();
    final file = File(
      p.join(directory.path, 'in_flight_${now.microsecondsSinceEpoch}.jsonl'),
    );
    final raf = await file.open(mode: FileMode.write);
    final writer = JournalWriter._(
      file,
      raf,
      now.toIso8601String(),
      action,
      root,
    );
    await writer._write({
      'type': 'header',
      'timestamp': writer._timestamp,
      'action': action,
      'root': root,
    });
    return writer;
  }

  Future<void> _write(Map<String, dynamic> data) async {
    if (_closed) return;
    await _raf.writeString('${jsonEncode(data)}\n');
    await _raf.flush();
  }

  Future<void> intent(MoveRecord record) =>
      _write({'type': 'intent', ...record.toJson()});

  Future<void> done(MoveRecord record) =>
      _write({'type': 'done', ...record.toJson()});

  Future<void> createdDir(String path) => _write({'type': 'dir', 'path': path});

  /// Close and delete the journal. The caller must have persisted the final
  /// history entry first.
  Future<void> commit() => _close(deleteFile: true);

  /// Close and delete the journal after a successful rollback, or after the
  /// caller has recorded the partial entry itself.
  Future<void> discard() => _close(deleteFile: true);

  /// Close the handle but leave the journal on disk for recovery.
  Future<void> leaveForRecovery() => _close(deleteFile: false);

  Future<void> _close({required bool deleteFile}) async {
    if (_closed) return;
    _closed = true;
    try {
      await _raf.flush();
    } catch (_) {
      // The journal may already be on disk after a failed flush.
    }
    await _raf.close();
    if (deleteFile && _file.existsSync()) {
      try {
        await _file.delete();
      } catch (e) {
        debugPrint('Error deleting journal ${_file.path}: $e');
      }
    }
  }
}
