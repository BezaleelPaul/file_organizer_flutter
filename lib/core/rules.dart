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
  'Documents': [
    '.pdf',
    '.doc',
    '.docx',
    '.txt',
    '.md',
    '.rtf',
    '.odt',
    '.ppt',
    '.pptx',
    '.xls',
    '.xlsx',
    '.csv',
    '.ods',
    '.odp',
  ],
  'Images': [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.svg',
    '.webp',
    '.tif',
    '.tiff',
    '.heic',
    '.ico',
  ],
  'Videos': [
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.flv',
    '.webm',
    '.wmv',
    '.mpg',
    '.mpeg',
    '.m4v',
    '.3gp',
  ],
  'Music': ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus'],
  'Archives': [
    '.zip',
    '.rar',
    '.tar',
    '.gz',
    '.tgz',
    '.7z',
    '.bz2',
    '.xz',
    '.iso',
  ],
  'Programs': [
    '.exe',
    '.msi',
    '.dmg',
    '.deb',
    '.rpm',
    '.apk',
    '.appimage',
    '.pkg',
  ],
  'Scripts': [
    '.py',
    '.js',
    '.ts',
    '.html',
    '.css',
    '.sh',
    '.bat',
    '.cmd',
    '.ps1',
  ],
  'Code': [
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.java',
    '.go',
    '.rs',
    '.rb',
    '.php',
    '.swift',
    '.kt',
    '.json',
    '.xml',
    '.yaml',
    '.yml',
    '.toml',
    '.ini',
    '.conf',
  ],
  'Fonts': ['.ttf', '.otf', '.woff', '.woff2'],
  'CAD': [
    '.dwg',
    '.dxf',
    '.step',
    '.stp',
    '.stl',
    '.iges',
    '.igs',
    '.gcode',
    '.brd',
  ],
  'Data': [
    '.db',
    '.sqlite',
    '.sqlite3',
    '.sql',
    '.parquet',
    '.feather',
    '.npy',
    '.npz',
    '.h5',
  ],
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
///
/// Order: pattern-rule match on [fileName] (explicit rules win) → extension
/// match → size bucket. [fallback] is used when nothing matches (usually
/// `Others`).
String classifyFile({
  required String extension,
  required int sizeBytes,
  required CategoryMap categories,
  required bool byExtension,
  required bool bySize,
  List<PatternRule> patternRules = const [],
  String? fileName,
  String fallback = 'Others',
}) {
  if (fileName != null) {
    for (final rule in patternRules) {
      if (!rule.enabled || rule.pattern.isEmpty) continue;
      if (rule.regex.hasMatch(fileName)) return rule.category;
    }
  }
  if (byExtension) {
    for (final entry in categories.entries) {
      if (entry.value.isEmpty) continue;
      if (entry.value.contains(extension)) return entry.key;
    }
  }
  if (bySize) return sizeBucketFor(sizeBytes);
  return fallback;
}

/// The `YYYY-MM` subfolder for a modification date.
///
/// [template] may contain `{year}`, `{month}` and `{day}` tokens, so deeper
/// structures like `{year}/{month}` are possible.
String dateSubfolder(DateTime modified, {String template = '{year}-{month}'}) =>
    applyTemplate(template, modified: modified);

/// Replace `{name}`, `{ext}`, `{category}`, `{year}`, `{month}`, `{day}` and
/// `{counter}` tokens in [template] with values for this file.
String applyTemplate(
  String template, {
  String? stem,
  String? extension,
  String? category,
  DateTime? modified,
  int counter = 0,
}) {
  if (template.isEmpty) return template;
  var out = template;
  out = out.replaceAll('{name}', stem ?? '');
  out = out.replaceAll('{ext}', extension ?? '');
  out = out.replaceAll('{category}', category ?? '');
  final m = modified ?? DateTime.now();
  out = out.replaceAll('{year}', m.year.toString());
  out = out.replaceAll('{month}', m.month.toString().padLeft(2, '0'));
  out = out.replaceAll('{day}', m.day.toString().padLeft(2, '0'));
  out = out.replaceAll('{counter}', counter.toString());
  return out;
}

const _windowsReservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

final _invalidNameChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

/// Whether [name] can safely be used as a single file name inside a folder
/// without escaping that folder. This is deliberately permissive about
/// characters: it protects against traversal, not against odd but legal names.
bool isSafeRelativeName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return false;
  if (name.length > 255) return false;
  if (name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
    return false;
  }
  return true;
}

/// Whether [segment] is a safe, portable folder/file name on Windows, macOS
/// and Linux. Used for values that Mise generates or accepts as folder names.
bool isSafePathSegment(String segment) {
  if (!isSafeRelativeName(segment)) return false;
  if (_invalidNameChars.hasMatch(segment)) return false;
  if (segment.endsWith(' ') || segment.endsWith('.')) return false;
  final stem = segment.split('.').first.trim().toUpperCase();
  if (_windowsReservedNames.contains(stem)) return false;
  return true;
}

/// Make [name] safe to use as a single file name on every supported platform.
/// Returns null when nothing safe is left. Invalid characters are replaced
/// with `_`; trailing dots/spaces are stripped; reserved Windows names get a
/// leading underscore.
String? sanitizeFileName(String name) {
  var out = name.replaceAll(_invalidNameChars, '_').trim();
  out = out.replaceAll(RegExp(r'[. ]+$'), '');
  if (out.isEmpty || out == '.' || out == '..') return null;
  final stem = out.split('.').first.trim().toUpperCase();
  if (_windowsReservedNames.contains(stem)) out = '_$out';
  if (out.length > 255) {
    final dot = out.lastIndexOf('.');
    final ext = dot > 0 && dot >= out.length - 20 ? out.substring(dot) : '';
    final stemLength = 255 - ext.length;
    out = '${out.substring(0, stemLength)}$ext';
  }
  return out;
}

/// Split a folder template such as `{year}/{month}` into validated segments.
/// Throws [FormatException] when any segment could escape the target root or
/// is not portable across platforms.
List<String> splitTemplatePath(String template) {
  final parts = template
      .split(RegExp(r'[\\/]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  for (final part in parts) {
    if (!isSafePathSegment(part)) {
      throw FormatException(
        'Invalid folder name "$part": use a simple name without path '
        'separators, "..", control characters or Windows reserved names.',
      );
    }
  }
  return parts;
}

/// Whether [name] matches any entry in [excludePatterns] (regex sources).
bool isExcluded(String name, List<String> excludePatterns) {
  for (final pattern in excludePatterns) {
    if (pattern.isEmpty) continue;
    try {
      if (RegExp(pattern).hasMatch(name)) return true;
    } on FormatException {
      continue;
    }
  }
  return false;
}

/// Produce a unique file name inside a folder.
///
/// [existing] holds names already present in the destination folder plus any
/// names already claimed during this run. Returns `file (1).txt`, `file (2).txt`,
/// etc. until a free name is found. When [caseInsensitive] is true (Windows /
/// macOS filesystems), collisions ignore letter case.
String uniqueName(
  String fileName,
  Set<String> existing, {
  bool caseInsensitive = false,
}) {
  bool taken(String name) => caseInsensitive
      ? existing.any((e) => e.toLowerCase() == name.toLowerCase())
      : existing.contains(name);
  if (!taken(fileName)) return fileName;
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final suffix = dot > 0 ? fileName.substring(dot) : '';
  var counter = 1;
  while (true) {
    final candidate = '$stem ($counter)$suffix';
    if (!taken(candidate)) return candidate;
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

/// A curated culinary "Playbook Recipe" for Mise en Place file organization.
class ChefRecipe {
  const ChefRecipe({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.description,
    required this.dateTemplate,
    required this.patternRules,
  });

  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String description;
  final String dateTemplate;
  final List<PatternRule> patternRules;

  static final List<ChefRecipe> all = [
    ChefRecipe(
      id: 'download_janitor',
      title: 'Download Janitor',
      subtitle: 'Disposables & Inboxes',
      badge: '🧹 High Impact',
      description:
          'Sorts disposable installers (.exe, .dmg, .msi, .iso) to /Installers, '
          'screenshots to /Screenshots, and archives to /Archives.',
      dateTemplate: '',
      patternRules: [
        PatternRule(
          pattern: r'\.(exe|msi|dmg|pkg|iso|deb|rpm|apk|appimage)$',
          category: 'Installers',
        ),
        PatternRule(
          pattern:
              r'(?i)(screenshot|screen_shot|screen shot|schermata|captura|snip)',
          category: 'Screenshots',
        ),
        PatternRule(
          pattern: r'\.(zip|rar|7z|tar|gz|bz2|xz)$',
          category: 'Archives',
        ),
      ],
    ),
    ChefRecipe(
      id: 'tax_vault',
      title: 'Tax & Finance Vault',
      subtitle: 'Fiscal Stash & Receipts',
      badge: '🧾 Accounting',
      description:
          'Harvesters invoices, tax forms, receipts, and bills into a '
          'chronological fiscal vault (Finances/{year}).',
      dateTemplate: 'Finances/{year}',
      patternRules: [
        PatternRule(
          pattern:
              r'(?i)(invoice|receipt|tax|bill|statement|w2|1099|payroll|salary|factura|rechnung|recibo)',
          category: 'Finances',
        ),
      ],
    ),
    ChefRecipe(
      id: 'media_darkroom',
      title: 'Media Darkroom',
      subtitle: 'Photo & Footage Studio',
      badge: '📸 Studio',
      description:
          'Separates loose screenshots, camera photos/RAWs, and video '
          'footage into clean timeline folders.',
      dateTemplate: 'Media/{category}/{year}',
      patternRules: [
        PatternRule(
          pattern:
              r'(?i)(screenshot|screen_shot|screen shot|schermata|captura|snip)',
          category: 'Screenshots',
        ),
        PatternRule(
          pattern: r'\.(mp4|mov|avi|mkv|webm|m4v)$',
          category: 'Footage',
        ),
        PatternRule(
          pattern: r'\.(heic|cr2|nef|arw|dng|jpg|jpeg|png|webp)$',
          category: 'Photos',
        ),
      ],
    ),
    ChefRecipe(
      id: 'dev_forge',
      title: 'Developer Forge',
      subtitle: 'Code, Configs & Assets',
      badge: '💻 Dev',
      description:
          'Stashes loose source scripts, environment dumps, database '
          'exports, and 3D/vector design assets.',
      dateTemplate: '',
      patternRules: [
        PatternRule(
          pattern:
              r'\.(dart|py|js|ts|tsx|jsx|rs|go|c|cpp|java|kt|swift|html|css|sh)$',
          category: 'Code',
        ),
        PatternRule(
          pattern:
              r'\.(json|yaml|yml|toml|ini|env|sql|db|sqlite|sqlite3)$',
          category: 'Config & Data',
        ),
        PatternRule(
          pattern: r'\.(svg|psd|blend|stl|step|obj|fig)$',
          category: 'Design Assets',
        ),
      ],
    ),
  ];
}

/// An audit report of directory entropy and disorder.
class EntropyReport {
  const EntropyReport({
    required this.score,
    required this.status,
    required this.tip,
    required this.installerCount,
    required this.screenshotCount,
    required this.duplicateCount,
    required this.staleFileCount,
  });

  /// 0 = Pure Michelin Zen, 100 = Digital Wildfire Hazard.
  final int score;
  final String status;
  final String tip;
  final int installerCount;
  final int screenshotCount;
  final int duplicateCount;
  final int staleFileCount;
}

/// Calculate the entropy of a scanned directory.
EntropyReport calculateEntropy(List<PlannedMove> files) {
  if (files.isEmpty) {
    return const EntropyReport(
      score: 0,
      status: 'Michelin Star Zen ✨',
      tip: 'Folder is immaculate. Everything is in its place.',
      installerCount: 0,
      screenshotCount: 0,
      duplicateCount: 0,
      staleFileCount: 0,
    );
  }

  final total = files.length;
  final now = DateTime.now();

  var installers = 0;
  var screenshots = 0;
  var duplicates = 0;
  var staleFiles = 0;
  var unclassified = 0;

  final installerRegex = RegExp(
    r'\.(exe|msi|dmg|pkg|iso|deb|rpm|apk|appimage)$',
    caseSensitive: false,
  );
  final screenshotRegex = RegExp(
    r'(screenshot|screen_shot|screen shot|schermata|captura|snip)',
    caseSensitive: false,
  );

  for (final f in files) {
    if (installerRegex.hasMatch(f.name)) installers++;
    if (screenshotRegex.hasMatch(f.name)) screenshots++;
    if (f.isDuplicate) duplicates++;
    if (f.category == 'Others') unclassified++;
    if (now.difference(f.modified).inDays > 30) staleFiles++;
  }

  var rawScore = 0.0;
  rawScore += (total / 40.0).clamp(0.0, 1.0) * 25.0;
  rawScore += (unclassified / total) * 25.0;
  rawScore += (installers * 5.0).clamp(0.0, 20.0);
  rawScore += (duplicates * 5.0).clamp(0.0, 20.0);
  rawScore += (staleFiles / total) * 10.0;

  final score = rawScore.round().clamp(5, 100);

  final String status;
  final String tip;
  if (score < 30) {
    status = 'Near Zen ✨';
    tip = 'Folder is clean and well-structured.';
  } else if (score < 60) {
    status = 'Moderate Disorder 📦';
    tip = installers > 0
        ? 'Found $installers setup files that can be archived.'
        : 'Run a quick sweep to organize categories.';
  } else if (score < 80) {
    status = 'Clutter Hazard ⚠️';
    tip = screenshots > 0
        ? '$screenshots screenshots and $installers installers need triaging.'
        : 'Organize files before they spill out of hand.';
  } else {
    status = 'Pure Digital Chaos 🔥';
    tip = 'Heavy clutter detected. Blitz Triage can clean this in under 60s.';
  }

  return EntropyReport(
    score: score,
    status: status,
    tip: tip,
    installerCount: installers,
    screenshotCount: screenshots,
    duplicateCount: duplicates,
    staleFileCount: staleFiles,
  );
}
