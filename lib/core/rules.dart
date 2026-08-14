/// Classification rules: which folder a file goes to, unique naming,
/// and size/date buckets. Pure Dart — no I/O, easily unit-testable.
library;

import 'package:file_organizer/core/models.dart';

const sizeBuckets = <(String, int, int?)>[
  ('Small', 0, 1024 * 1024),
  ('Medium', 1024 * 1024, 100 * 1024 * 1024),
  ('Large', 100 * 1024 * 1024, null),
];

const defaultCategories = <String, List<String>>{
  'Documents': ['.pdf', '.doc', '.docx', '.txt', '.md', '.rtf', '.odt', '.ppt', '.pptx', '.xls', '.xlsx', '.csv', '.ods', '.odp'],
  'Images': ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.svg', '.webp', '.tif', '.tiff', '.heic', '.ico'],
  'Videos': ['.mp4', '.mov', '.avi', '.mkv', '.flv', '.webm', '.wmv', '.mpg', '.mpeg', '.m4v', '.3gp'],
  'Music': ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus'],
  'Archives': ['.zip', '.rar', '.tar', '.gz', '.tgz', '.7z', '.bz2', '.xz', '.iso'],
  'Programs': ['.exe', '.msi', '.dmg', '.deb', '.rpm', '.apk', '.appimage', '.pkg'],
  'Scripts': ['.py', '.js', '.ts', '.html', '.css', '.sh', '.bat', '.cmd', '.ps1'],
  'Code': ['.c', '.cpp', '.h', '.hpp', '.java', '.go', '.rs', '.rb', '.php', '.swift', '.kt', '.json', '.xml', '.yaml', '.yml', '.toml', '.ini', '.conf'],
  'Fonts': ['.ttf', '.otf', '.woff', '.woff2'],
  'CAD': ['.dwg', '.dxf', '.step', '.stp', '.stl', '.iges', '.igs', '.gcode', '.brd'],
  'Data': ['.db', '.sqlite', '.sqlite3', '.sql', '.parquet', '.feather', '.npy', '.npz', '.h5'],
  'Others': [],
};

/// Sanitize a category map: lower-case extensions, ensure `Others` exists.
CategoryMap normalizeCategories(CategoryMap categories) {
  final result = <String, List<String>>{};
  categories.forEach((name, exts) {
    result[name] = exts
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
  });
  result.putIfAbsent('Others', () => <String>[]);
  return result;
}

/// The size bucket (Small / Medium / Large) for [sizeBytes] bytes.
String sizeBucketFor(int sizeBytes) {
  for (final (name, low, high) in sizeBuckets) {
    if (sizeBytes >= low && (high == null || sizeBytes < high)) {
      return name;
    }
  }
  return 'Small';
}

/// Choose a category for a file with the given lower-cased extension.
String classifyFile({
  required String extension,
  required int sizeBytes,
  required CategoryMap categories,
  required bool byExtension,
  required bool bySize,
}) {
  if (byExtension) {
    for (final entry in categories.entries) {
      if (entry.value.isEmpty) continue;
      if (entry.value.contains(extension)) return entry.key;
    }
  }
  if (bySize) return sizeBucketFor(sizeBytes);
  return 'Others';
}

/// The `YYYY-MM` subfolder for a modification date.
String dateSubfolder(DateTime modified) => '${modified.year}-${modified.month.toString().padLeft(2, '0')}';

/// Produce a unique file name inside a folder.
///
/// [existing] holds names already present in the destination folder plus any
/// names already claimed during this run. Returns `file (1).txt`, `file (2).txt`,
/// etc. until a free name is found.
String uniqueName(String fileName, Set<String> existing) {
  if (!existing.contains(fileName)) return fileName;
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final suffix = dot > 0 ? fileName.substring(dot) : '';
  var counter = 1;
  while (true) {
    final candidate = '$stem ($counter)$suffix';
    if (!existing.contains(candidate)) return candidate;
    counter += 1;
  }
}

/// Human-readable byte formatting.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = -1;
  do {
    value /= 1024;
    index += 1;
  } while (value >= 1024 && index < units.length - 1);
  return '${value.toStringAsFixed(1)} ${units[index]}';
}

/// Extension of a file name, lower-cased and dot-included ('' when none).
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  return name.substring(dot).toLowerCase();
}
