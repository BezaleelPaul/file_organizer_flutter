/// Search query parsing and matching. Pure Dart — no I/O.
///
/// Supported syntax:
///   report            name contains "report"
///   "*.pdf"           extension filter
///   name:report       name contains
///   ext:pdf           extension
///   type:image        extension groups (image, video, audio, document, ...)
///   folder:Projects   path contains
///   >100MB  <2GB  >=500KB  size filters (b/kb/mb/gb/tb)
///   size:>100MB       same as above
///   modified:last-week / last-month / last-year / 2026 / 2026-01-01
///   after:2026-01-01  before:2026-01-01
library;

/// Extension groups usable with `type:`.
const typeExtensions = <String, Set<String>>{
  'image': {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'tif', 'tiff', 'heic', 'heif', 'ico'},
  'video': {'mp4', 'mov', 'mkv', 'webm', 'avi', 'flv', 'wmv', 'mpg', 'mpeg', 'm4v', '3gp'},
  'audio': {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus'},
  'document': {'pdf', 'doc', 'docx', 'txt', 'md', 'rtf', 'odt', 'ppt', 'pptx', 'xls', 'xlsx', 'csv', 'ods', 'html', 'htm', 'tex'},
  'archive': {'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'iso'},
  'code': {'dart', 'py', 'js', 'ts', 'java', 'c', 'cpp', 'h', 'hpp', 'go', 'rs', 'rb', 'php', 'swift', 'kt', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'sh', 'bat', 'ps1'},
  'installer': {'exe', 'msi', 'msix', 'dmg', 'deb', 'rpm', 'apk', 'appimage', 'pkg'},
  'data': {'db', 'sqlite', 'sqlite3', 'sql', 'parquet', 'npy', 'h5'},
};

/// A parsed search query.
class SearchQuery {
  const SearchQuery({
    this.terms = const [],
    this.nameContains,
    this.extension,
    this.types = const {},
    this.folderContains,
    this.minBytes,
    this.maxBytes,
    this.modifiedAfter,
    this.modifiedBefore,
  });

  /// Free-text substrings that must all appear in the file name.
  final List<String> terms;
  final String? nameContains;
  final String? extension;
  final Set<String> types;
  final String? folderContains;
  final int? minBytes;
  final int? maxBytes;
  final DateTime? modifiedAfter;
  final DateTime? modifiedBefore;

  bool get isEmpty =>
      terms.isEmpty &&
      nameContains == null &&
      extension == null &&
      types.isEmpty &&
      folderContains == null &&
      minBytes == null &&
      maxBytes == null &&
      modifiedAfter == null &&
      modifiedBefore == null;
}

/// Parse [input] into a [SearchQuery]. Unknown tokens become free-text terms.
SearchQuery parseQuery(String input) {
  var terms = <String>[];
  String? nameContains;
  String? extension;
  final types = <String>{};
  String? folderContains;
  int? minBytes;
  int? maxBytes;
  DateTime? modifiedAfter;
  DateTime? modifiedBefore;

  for (final raw in input.split(RegExp(r'\s+'))) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final lower = token.toLowerCase();

    if (lower.startsWith('*.') && lower.length > 2) {
      extension = lower.substring(1);
      continue;
    }

    final colon = token.indexOf(':');
    final key = colon > 0 ? token.substring(0, colon).toLowerCase() : null;
    final value = colon > 0 ? token.substring(colon + 1) : null;

    if (key == 'name' && value != null && value.isNotEmpty) {
      nameContains = value;
      continue;
    }
    if (key == 'ext' && value != null && value.isNotEmpty) {
      extension = value.toLowerCase();
      continue;
    }
    if (key == 'type' && value != null && value.isNotEmpty) {
      types.add(value.toLowerCase());
      continue;
    }
    if (key == 'folder' && value != null && value.isNotEmpty) {
      folderContains = value.toLowerCase();
      continue;
    }
    if (key == 'size' && value != null && value.isNotEmpty) {
      final (op, bytes) = _parseSizeToken(value);
      if (op != null || bytes > 0) {
        _applySizeOp(op, bytes, (min, max) {
          if (min != null) minBytes = min;
          if (max != null) maxBytes = max;
        });
      }
      continue;
    }
    if (key == 'modified' && value != null && value.isNotEmpty) {
      final (after, before) = _parseModified(value);
      if (after != null) modifiedAfter = after;
      if (before != null) modifiedBefore = before;
      continue;
    }
    if (key == 'after' && value != null && value.isNotEmpty) {
      final date = _parseDate(value);
      if (date != null) modifiedAfter = date;
      continue;
    }
    if (key == 'before' && value != null && value.isNotEmpty) {
      final date = _parseDate(value);
      if (date != null) modifiedBefore = date;
      continue;
    }

    if (RegExp(r'^[<>]=?').hasMatch(lower)) {
      final (op, bytes) = _parseSizeToken(token);
      if (op != null) {
        _applySizeOp(op, bytes, (min, max) {
          if (min != null) minBytes = min;
          if (max != null) maxBytes = max;
        });
      }
      continue;
    }

    terms.add(value != null && key != null ? value : token);
  }

  return SearchQuery(
    terms: terms,
    nameContains: nameContains,
    extension: extension,
    types: types,
    folderContains: folderContains,
    minBytes: minBytes,
    maxBytes: maxBytes,
    modifiedAfter: modifiedAfter,
    modifiedBefore: modifiedBefore,
  );
}

void _applySizeOp(
  String? op,
  int bytes,
  void Function(int? min, int? max) set,
) {
  switch (op) {
    case '>':
      set(bytes + 1, null);
    case '>=':
      set(bytes, null);
    case '<':
      set(null, bytes - 1);
    case '<=':
      set(null, bytes);
    default:
      set(bytes, bytes);
  }
}

/// Parse a bare size value like `5MB` or `500` into bytes, or null when it
/// is not a valid size. Public so the rule builder reuses the same syntax.
int? parseSizeValue(String token) {
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb|tb|k|m|g|t)?$',
    caseSensitive: false,
  ).firstMatch(token.trim());
  if (match == null) return null;
  final value = double.parse(match.group(1)!);
  final unit = (match.group(2) ?? 'b').toLowerCase();
  final multiplier = switch (unit) {
    'k' || 'kb' => 1024,
    'm' || 'mb' => 1024 * 1024,
    'g' || 'gb' => 1024 * 1024 * 1024,
    't' || 'tb' => 1024 * 1024 * 1024 * 1024,
    _ => 1,
  };
  return (value * multiplier).round();
}

/// Returns (comparator, bytes) for values like `100MB`, `>1GB`, `500kb`.
(String?, int) _parseSizeToken(String token) {
  final match = RegExp(
    r'^([<>]=?)?\s*(\d+(?:\.\d+)?)\s*(b|kb|mb|gb|tb|k|m|g|t)?$',
    caseSensitive: false,
  ).firstMatch(token);
  if (match == null) return (null, 0);
  final value = double.parse(match.group(2)!);
  final unit = (match.group(3) ?? 'b').toLowerCase();
  final multiplier = switch (unit) {
    'k' || 'kb' => 1024,
    'm' || 'mb' => 1024 * 1024,
    'g' || 'gb' => 1024 * 1024 * 1024,
    't' || 'tb' => 1024 * 1024 * 1024 * 1024,
    _ => 1,
  };
  return (match.group(1), (value * multiplier).round());
}

/// Returns (after, before) for a `modified:` value.
(DateTime?, DateTime?) _parseModified(String value) {
  final lower = value.toLowerCase();
  final now = DateTime.now();
  switch (lower) {
    case 'today':
      final start = DateTime(now.year, now.month, now.day);
      return (start, null);
    case 'last-week':
      return (now.subtract(const Duration(days: 7)), null);
    case 'last-month':
      return (now.subtract(const Duration(days: 30)), null);
    case 'last-year':
      return (now.subtract(const Duration(days: 365)), null);
  }
  final yearMatch = RegExp(r'^\d{4}$').firstMatch(lower);
  if (yearMatch != null) {
    final year = int.parse(lower);
    return (
      DateTime(year, 1, 1),
      DateTime(year + 1, 1, 1).subtract(const Duration(milliseconds: 1)),
    );
  }
  final date = _parseDate(value);
  if (date != null) return (date, null);
  return (null, null);
}

DateTime? _parseDate(String value) {
  try {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  } catch (_) {
    return null;
  }
}

/// Whether [entry] satisfies [query]. Called per file with [ext] already
/// lower-cased with the leading dot (e.g. `.pdf`), [name] and [path] as
/// found on disk, and [modified] as the last-modified time.
bool matchQuery(
  SearchQuery query, {
  required String name,
  required String path,
  required String ext,
  required int size,
  required DateTime modified,
}) {
  final lowerName = name.toLowerCase();

  for (final term in query.terms) {
    if (!lowerName.contains(term.toLowerCase())) return false;
  }
  if (query.nameContains != null &&
      !lowerName.contains(query.nameContains!.toLowerCase())) {
    return false;
  }
  if (query.extension != null) {
    final want = query.extension!.startsWith('.')
        ? query.extension!
        : '.${query.extension}';
    if (ext.toLowerCase() != want) return false;
  }
  if (query.types.isNotEmpty) {
    final bare = ext.replaceAll('.', '').toLowerCase();
    final ok = query.types.any(
      (t) => typeExtensions[t]?.contains(bare) ?? false,
    );
    if (!ok) return false;
  }
  if (query.folderContains != null &&
      !path.toLowerCase().contains(query.folderContains!.toLowerCase())) {
    return false;
  }
  if (query.minBytes != null && size < query.minBytes!) return false;
  if (query.maxBytes != null && size > query.maxBytes!) return false;
  if (query.modifiedAfter != null && modified.isBefore(query.modifiedAfter!)) {
    return false;
  }
  if (query.modifiedBefore != null && modified.isAfter(query.modifiedBefore!)) {
    return false;
  }
  return true;
}

/// Sort by name, then size (descending) for stable results.
List<T> sortResults<T>(List<T> items, String Function(T) nameOf, int Function(T) sizeOf) {
  final copy = [...items];
  copy.sort((a, b) {
    final byName = nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
    if (byName != 0) return byName;
    return sizeOf(b).compareTo(sizeOf(a));
  });
  return copy;
}

/// Human-readable example shown in the search box.
const searchHint = 'Search everything…  e.g. report, *.pdf, type:image, '
    '>100MB, modified:last-week';