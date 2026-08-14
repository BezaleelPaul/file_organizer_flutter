/// Platform-independent data models for the file organizer.
library;

typedef CategoryMap = Map<String, List<String>>;

/// A single file discovered while scanning a folder.
class FileEntry {
  const FileEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.modified,
  });

  final String name;
  final int size;
  final bool isDirectory;
  final DateTime modified;
}

/// A file and the folder it will be moved into.
class PlannedMove {
  PlannedMove({
    required this.name,
    required this.size,
    required this.category,
    required this.destination,
  });

  final String name;
  final int size;
  final String category;

  /// Relative destination path inside the root, e.g. `Images/2026-08`.
  final String destination;

  String? overrideCategory;
  bool skipped = false;

  String get effectiveCategory => overrideCategory ?? category;

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'category': category,
        'destination': destination,
      };
}

/// Per-category totals produced by a scan.
class CategoryStat {
  CategoryStat({this.count = 0, this.bytes = 0});

  int count;
  int bytes;

  Map<String, dynamic> toJson() => {'count': count, 'bytes': bytes};
}

/// The result of scanning a folder.
class ScanResult {
  ScanResult({required this.root, required this.files});

  final String root;
  final List<PlannedMove> files;

  Map<String, CategoryStat> get stats {
    final stats = <String, CategoryStat>{};
    for (final file in files) {
      if (file.skipped) continue;
      final stat = stats.putIfAbsent(file.effectiveCategory, () => CategoryStat());
      stat.count += 1;
      stat.bytes += file.size;
    }
    return stats;
  }

  int get totalBytes =>
      files.fold(0, (sum, file) => sum + (file.skipped ? 0 : file.size));
}

/// One src → dest operation recorded for undo. Handles are opaque strings
/// (absolute paths on desktop, SAF content URIs on Android).
class MoveRecord {
  const MoveRecord({
    required this.srcDir,
    required this.srcName,
    required this.destDir,
    required this.destName,
  });

  final String srcDir;
  final String srcName;
  final String destDir;
  final String destName;

  Map<String, dynamic> toJson() => {
        'srcDir': srcDir,
        'srcName': srcName,
        'destDir': destDir,
        'destName': destName,
      };

  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
        srcDir: json['srcDir'] as String,
        srcName: json['srcName'] as String,
        destDir: json['destDir'] as String,
        destName: json['destName'] as String,
      );
}

/// A completed organize operation that can be undone.
class HistoryEntry {
  const HistoryEntry({
    required this.timestamp,
    required this.action,
    required this.root,
    required this.createdDirs,
    required this.moves,
  });

  final String timestamp;

  /// `move` or `copy`.
  final String action;
  final String root;
  final List<String> createdDirs;
  final List<MoveRecord> moves;

  int get count => moves.length;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'action': action,
        'root': root,
        'created_dirs': createdDirs,
        'entries': moves.map((m) => m.toJson()).toList(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        timestamp: json['timestamp'] as String,
        action: json['action'] as String,
        root: json['root'] as String,
        createdDirs: (json['created_dirs'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        moves: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => MoveRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A running auto-watch job.
class WatchJob {
  WatchJob({
    required this.root,
    required this.interval,
    required this.byExtension,
    required this.bySize,
    required this.byDate,
  });

  final String root;
  final int interval;
  final bool byExtension;
  final bool bySize;
  final bool byDate;

  bool running = true;
  String? lastRun;
  int lastCount = 0;
  String? error;

  Map<String, dynamic> toJson() => {
        'root': root,
        'interval': interval,
        'by_extension': byExtension,
        'by_size': bySize,
        'by_date': byDate,
      };

  factory WatchJob.fromJson(Map<String, dynamic> json) => WatchJob(
        root: json['root'] as String,
        interval: json['interval'] as int,
        byExtension: json['by_extension'] as bool? ?? true,
        bySize: json['by_size'] as bool? ?? false,
        byDate: json['by_date'] as bool? ?? false,
      );
}
