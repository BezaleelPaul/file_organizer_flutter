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

/// A user-defined label that can be attached to files and used to filter
/// search results (`tag:work`).
class Tag {
  Tag({required this.name, this.color = 0});

  final String name;

  /// Index into the tag color palette shown in the UI.
  int color;

  Map<String, dynamic> toJson() => {'name': name, 'color': color};

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        name: json['name'] as String,
        color: json['color'] as int? ?? 0,
      );
}

/// A saved search query shown as a live collection of matching files.
class SmartCollection {
  SmartCollection({required this.name, required this.query});

  String name;
  String query;

  Map<String, dynamic> toJson() => {'name': name, 'query': query};

  factory SmartCollection.fromJson(Map<String, dynamic> json) => SmartCollection(
        name: json['name'] as String? ?? 'Untitled collection',
        query: json['query'] as String? ?? '',
      );
}

/// A custom regex pattern rule: files whose name matches [pattern] go to
/// [category]. Works alongside extension-based sorting.
class PatternRule {
  PatternRule({
    required this.pattern,
    required this.category,
    this.enabled = true,
  });

  /// Regular-expression source matched against the file name.
  final String pattern;
  final String category;
  bool enabled;

  RegExp get regex => RegExp(pattern);

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        'category': category,
        'enabled': enabled,
      };

  factory PatternRule.fromJson(Map<String, dynamic> json) => PatternRule(
        pattern: json['pattern'] as String? ?? '',
        category: json['category'] as String? ?? 'Others',
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// A first-class automation rule built in the visual rule builder: files whose
/// extension, name, size and modification time all match are sent to
/// [category]. First matching rule wins (list order).
class AutoRule {
  AutoRule({
    required this.name,
    this.category = 'Others',
    this.extensions = const [],
    this.namePattern = '',
    this.minSize,
    this.maxSize,
    this.modifiedAfter,
    this.modifiedBefore,
    this.enabled = true,
  });

  String name;
  String category;

  /// Lower-cased extensions with the leading dot (e.g. `.pdf`). Empty = any.
  List<String> extensions;

  /// Regex matched against the file name. Empty = any.
  String namePattern;

  int? minSize;
  int? maxSize;
  DateTime? modifiedAfter;
  DateTime? modifiedBefore;
  bool enabled;

  RegExp? get nameRegex {
    if (namePattern.isEmpty) return null;
    try {
      return RegExp(namePattern);
    } on FormatException {
      return null;
    }
  }

  /// Whether a file matches every active condition.
  bool matches({
    required String fileName,
    required String extension,
    required int size,
    required DateTime modified,
  }) {
    if (!enabled) return false;
    if (extensions.isNotEmpty && !extensions.contains(extension)) return false;
    final regex = nameRegex;
    if (regex != null && !regex.hasMatch(fileName)) return false;
    if (minSize != null && size < minSize!) return false;
    if (maxSize != null && size > maxSize!) return false;
    if (modifiedAfter != null && modified.isBefore(modifiedAfter!)) return false;
    if (modifiedBefore != null && modified.isAfter(modifiedBefore!)) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'extensions': extensions,
        'name_pattern': namePattern,
        'min_size': minSize,
        'max_size': maxSize,
        'modified_after': modifiedAfter?.toIso8601String(),
        'modified_before': modifiedBefore?.toIso8601String(),
        'enabled': enabled,
      };

  factory AutoRule.fromJson(Map<String, dynamic> json) => AutoRule(
        name: json['name'] as String? ?? 'Untitled rule',
        category: json['category'] as String? ?? 'Others',
        extensions: (json['extensions'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        namePattern: json['name_pattern'] as String? ?? '',
        minSize: json['min_size'] as int?,
        maxSize: json['max_size'] as int?,
        modifiedAfter: json['modified_after'] == null
            ? null
            : DateTime.tryParse(json['modified_after'] as String),
        modifiedBefore: json['modified_before'] == null
            ? null
            : DateTime.tryParse(json['modified_before'] as String),
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// A file and the folder it will be moved into.
class PlannedMove {
  PlannedMove({
    required this.name,
    required this.size,
    required this.category,
    required this.destination,
    required this.modified,
  });

  final String name;
  final int size;
  final String category;

  /// Relative destination path inside the root, e.g. `Images/2026-08`.
  final String destination;

  /// Last-modified time, used for date tokens and rename templates.
  final DateTime modified;

  String? overrideCategory;
  bool skipped = false;

  /// True when this file is a byte-identical duplicate of another file found
  /// in the same scan (set by duplicate detection).
  bool isDuplicate = false;

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

/// A scheduled background organize: run on an interval, daily, or on chosen
/// weekdays. Active while Mise is running (including in the tray).
class ScheduleJob {
  ScheduleJob({
    required this.root,
    this.mode = 'interval',
    this.intervalHours = 6,
    this.hour = 2,
    this.minute = 0,
    this.weekdays = const [],
    this.byExtension = true,
    this.bySize = false,
    this.byDate = false,
  });

  final String root;

  /// `interval` | `daily` | `weekly`.
  String mode;

  /// Hours between runs in interval mode.
  int intervalHours;

  /// Time of day (24h) for daily/weekly modes.
  int hour;
  int minute;

  /// 1 (Mon) … 7 (Sun). Empty in weekly mode means every day.
  List<int> weekdays;

  bool byExtension;
  bool bySize;
  bool byDate;

  bool enabled = true;
  String? lastRun;
  int lastCount = 0;
  String? error;

  /// The next time this job should run, based on [now].
  DateTime nextRun(DateTime now) {
    final last = lastRun == null ? null : DateTime.tryParse(lastRun!);
    switch (mode) {
      case 'interval':
        final base = last ?? now;
        return base.add(Duration(hours: intervalHours));
      case 'daily':
        final today = DateTime(now.year, now.month, now.day, hour, minute);
        return now.isBefore(today) ? today : today.add(const Duration(days: 1));
      case 'weekly':
        final days = weekdays.isEmpty ? const <int>[] : weekdays;
        for (var d = 0; d < 7; d++) {
          final day = now.add(Duration(days: d));
          if (days.isNotEmpty && !days.contains(day.weekday)) continue;
          final candidate = DateTime(day.year, day.month, day.day, hour, minute);
          if (candidate.isAfter(now)) return candidate;
        }
        return now.add(const Duration(days: 1));
      default:
        return now;
    }
  }

  /// Human-readable schedule summary, e.g. `Every 6h` or `Mon, Wed at 09:00`.
  String describe() {
    final flags = <String>[
      if (byExtension) 'extension',
      if (bySize) 'size',
      if (byDate) 'date',
    ];
    final by = flags.isEmpty ? '' : ' (${flags.join('+')})';
    switch (mode) {
      case 'interval':
        return 'Every $intervalHours h$by';
      case 'daily':
        return 'Daily at $hour:${minute.toString().padLeft(2, '0')}$by';
      case 'weekly':
        const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final days = weekdays.isEmpty
            ? 'every day'
            : weekdays.map((w) => names[w]).join(', ');
        return '$days at $hour:${minute.toString().padLeft(2, '0')}$by';
      default:
        return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'root': root,
        'mode': mode,
        'interval_hours': intervalHours,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'by_extension': byExtension,
        'by_size': bySize,
        'by_date': byDate,
      };

  factory ScheduleJob.fromJson(Map<String, dynamic> json) => ScheduleJob(
        root: json['root'] as String,
        mode: json['mode'] as String? ?? 'interval',
        intervalHours: json['interval_hours'] as int? ?? 6,
        hour: json['hour'] as int? ?? 2,
        minute: json['minute'] as int? ?? 0,
        weekdays: (json['weekdays'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        byExtension: json['by_extension'] as bool? ?? true,
        bySize: json['by_size'] as bool? ?? false,
        byDate: json['by_date'] as bool? ?? false,
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
