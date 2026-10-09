/// Controller for storage analytics, duplicate detection, large files, and disk health.
library;

import 'package:file_organizer/core/disk_scanner.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:flutter/foundation.dart';

class StorageController extends ChangeNotifier {
  StorageController({required this.storage});

  final StorageService storage;

  DiskScan? _scan;
  List<DuplicateGroup>? _duplicates;
  bool _scanning = false;
  bool _hashing = false;
  double _progress = 0;
  String? _error;

  DiskScan? get scan => _scan;
  List<DuplicateGroup>? get duplicates => _duplicates;
  bool get isScanning => _scanning;
  bool get isHashing => _hashing;
  double get progress => _progress;
  String? get error => _error;

  int get totalReclaimableBytes {
    if (_duplicates == null) return 0;
    return _duplicates!.fold(0, (sum, g) => sum + g.reclaimable);
  }

  /// Run deep disk analysis on [rootPath].
  Future<void> runScan(String rootPath) async {
    _scanning = true;
    _hashing = false;
    _duplicates = null;
    _error = null;
    _progress = 0;
    notifyListeners();

    try {
      final result = await scanTree(
        rootPath,
        onProgress: (count) {
          _progress = (count % 100) / 100.0;
          notifyListeners();
        },
      );
      _scan = result;
      _scanning = false;
      _progress = 1.0;
      notifyListeners();
      await findDuplicatesForCurrentScan();
    } catch (e) {
      _error = e.toString();
      _scanning = false;
      notifyListeners();
    }
  }

  /// Compute byte duplicates using the 3-stage cascade.
  Future<void> findDuplicatesForCurrentScan() async {
    final s = _scan;
    if (s == null || _hashing) return;
    _hashing = true;
    notifyListeners();

    try {
      final groups = await findDuplicates(s);
      _duplicates = groups;
    } catch (e) {
      _error = e.toString();
    } finally {
      _hashing = false;
      notifyListeners();
    }
  }

  void clear() {
    _scan = null;
    _duplicates = null;
    _scanning = false;
    _hashing = false;
    _progress = 0;
    _error = null;
    notifyListeners();
  }
}
