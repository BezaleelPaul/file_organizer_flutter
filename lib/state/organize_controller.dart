/// Controller for directory scanning, planning moves, execution, and rollback.
library;

import 'package:file_organizer/ai/suggestion_engine.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:file_organizer/services/operation_queue.dart';
import 'package:file_organizer/services/organize_service.dart';
import 'package:flutter/foundation.dart';

class OrganizeController extends ChangeNotifier {
  OrganizeController({required this.storage})
      : _organizeService = OrganizeService(storage: storage);

  final StorageService storage;
  final OrganizeService _organizeService;
  final OperationQueue operations = OperationQueue();

  String? root;
  String? rootLabel;
  ScanResult? scan;
  List<Suggestion> suggestions = [];
  bool suggestionsLoading = false;

  bool isBusy = false;
  double progress = 0;
  String status = '';
  List<String> logLines = [];
  String? error;

  void addLog(String message) {
    logLines.add(message);
    if (logLines.length > 500) logLines.removeAt(0);
    notifyListeners();
  }

  void clearLogs() {
    logLines.clear();
    error = null;
    notifyListeners();
  }

  /// Run scan and plan generation.
  Future<ScanResult?> scanFolder(String path, OrganizeConfig config) async {
    isBusy = true;
    error = null;
    notifyListeners();

    try {
      final result = await _organizeService.scan(path, config);
      root = path;
      scan = result;
      isBusy = false;
      notifyListeners();
      return result;
    } catch (e) {
      error = e.toString();
      isBusy = false;
      notifyListeners();
      return null;
    }
  }

  /// Execute planned moves.
  Future<HistoryEntry?> execute(
    List<PlannedMove> moves,
    OrganizeConfig config, {
    bool duplicatesToTrash = false,
  }) async {
    final currentRoot = root;
    if (currentRoot == null) return null;

    isBusy = true;
    notifyListeners();

    try {
      final entry = await _organizeService.executePlan(
        currentRoot,
        moves,
        config,
        progress: (done, total) {
          progress = total > 0 ? done / total : 0;
          notifyListeners();
        },
        log: addLog,
      );
      isBusy = false;
      notifyListeners();
      return entry;
    } catch (e) {
      error = e.toString();
      isBusy = false;
      notifyListeners();
      return null;
    }
  }
}
