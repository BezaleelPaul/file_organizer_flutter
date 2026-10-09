/// Controller for watch jobs, scheduled recurring runs, and OS file watchers.
library;

import 'dart:async';

import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/state/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:watcher/watcher.dart';

class WatchController extends ChangeNotifier {
  WatchController({
    required this.store,
    required this.onRunWatch,
    required bool isOsWatchSupported,
  }) : _osWatchSupported = isOsWatchSupported;

  final SettingsStore store;
  final Future<void> Function(WatchJob watch) onRunWatch;
  final bool _osWatchSupported;

  List<WatchJob> watches = [];
  List<ScheduleJob> schedules = [];
  String? error;

  Timer? _watchTimer;
  Timer? _scheduleTimer;
  final Map<String, StreamSubscription<WatchEvent>> _osWatchers = {};
  final Map<String, Timer> _watchDebounces = {};

  Future<void> init() async {
    watches = await store.loadWatches();
    schedules = await store.loadSchedules();
    startWatching();
    startScheduling();
    notifyListeners();
  }

  void startWatching() {
    _watchTimer?.cancel();
    for (final sub in _osWatchers.values) {
      sub.cancel();
    }
    _osWatchers.clear();
    for (final timer in _watchDebounces.values) {
      timer.cancel();
    }
    _watchDebounces.clear();

    if (watches.isEmpty) return;

    if (_osWatchSupported) {
      for (final watch in watches) {
        if (!watch.running) continue;
        try {
          final watcher = DirectoryWatcher(watch.root);
          final sub = watcher.events.listen((event) {
            if (event.type == ChangeType.REMOVE) return;
            _scheduleOsWatch(watch);
          }, onError: (Object e) {
            watch.error = e.toString();
            notifyListeners();
          });
          _osWatchers[watch.root] = sub;
        } catch (_) {}
      }
    }

    _watchTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = DateTime.now();
      for (final watch in watches) {
        if (!watch.running) continue;
        if (_osWatchers.containsKey(watch.root)) continue;
        final last =
            watch.lastRun == null ? null : DateTime.tryParse(watch.lastRun!);
        if (last != null && now.difference(last).inSeconds < watch.interval) {
          continue;
        }
        onRunWatch(watch);
      }
    });
  }

  void _scheduleOsWatch(WatchJob watch) {
    _watchDebounces[watch.root]?.cancel();
    _watchDebounces[watch.root] = Timer(const Duration(seconds: 1), () {
      onRunWatch(watch);
    });
  }

  void startScheduling() {
    _scheduleTimer?.cancel();
    if (schedules.isEmpty) return;
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      checkSchedules();
    });
  }

  void checkSchedules() {
    final now = DateTime.now();
    for (final schedule in schedules) {
      if (!schedule.enabled) continue;
      final next = schedule.nextRun(now);
      if (next.difference(now).inSeconds.abs() < 60) {
        // Trigger schedule run
      }
    }
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _scheduleTimer?.cancel();
    for (final sub in _osWatchers.values) {
      sub.cancel();
    }
    for (final timer in _watchDebounces.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
