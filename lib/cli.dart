/// Headless CLI for Mise. Run `dart run file_organizer:mise plan <dir>` to
/// preview, `dart run file_organizer:mise organize <dir>` to sort, or
/// `dart run file_organizer:mise stats <dir>`.
///
/// Shares the same core engine as the app; settings come from sensible
/// defaults or a `--config <file>` JSON with the keys `categories`,
/// `pattern_rules`, `auto_rules`, `exclude_patterns`, `rename_template`,
/// `date_template`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:path/path.dart' as p;

void Function(String message)? _out;
void Function(String message)? _err;
void Function(int code)? _exit;

/// Entry point used by `bin/mise.dart` and tests. Sinks default to real
/// stdout/stderr/exit; tests inject their own.
Future<void> runCli(
  List<String> args, {
  void Function(String message)? out,
  void Function(String message)? err,
  void Function(int code)? exitFn,
}) async {
  _out = out;
  _err = err;
  _exit = exitFn;
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _usage();
    _callExit(0);
    return;
  }
  final cmd = args.first;
  final opts = _Opts.parse(args.sublist(1));
  try {
    final config = await _loadConfig(opts.value('config'));
    final storage = CliStorage();
    switch (cmd) {
      case 'plan':
        await _plan(opts, config, storage);
      case 'organize':
        await _organize(opts, config, storage);
      case 'stats':
        await _stats(opts, config, storage);
      default:
        _error('Unknown command: $cmd');
        _usage();
        _callExit(1);
    }
  } on Exception catch (e) {
    _error('Error: $e');
    _callExit(1);
  }
}

void _write(String message) => (_out ?? stdout.writeln)(message);

void _error(String message) => (_err ?? stderr.writeln)(message);

void _callExit(int code) => (_exit ?? exit)(code);

void _usage() {
  _write('''
Mise — file organizer for the terminal.

Usage:
  dart run file_organizer:mise <command> <folder> [options]

Commands:
  plan <folder>      Preview what would move (no changes).
  organize <folder>  Sort the folder's files.
  stats <folder>     Show category totals for the folder.

Options:
  --by-extension / --no-by-extension   Sort by file type (default: on)
  --by-size                            Sort by size buckets instead
  --by-date                            Add date subfolders (e.g. 2026-08)
  --date-template <tpl>                Date subfolder template, default {year}-{month}
  --rename <template>                  Rename template ({name}, {category}, {counter})
  --detect-duplicates                  Flag byte-identical duplicates
  --duplicates-to-trash                Move duplicates to Trash/ instead of skipping
  --copy                               Copy instead of moving
  --exclude <regex>                    Skip files whose name matches (repeatable)
  --config <file>                      JSON settings file
  --json                               Machine-readable output
  --quiet                              Suppress per-file logging
  --help                               This help
''');
}

Future<_Config> _loadConfig(String? path) async {
  final config = _Config();
  if (path == null) return config;
  final file = File(path);
  if (!await file.exists()) {
    _error('Config file not found: $path');
    _callExit(2);
  }
  final json = jsonDecode(await file.readAsString());
  if (json is! Map<String, dynamic>) {
    _error('Config must be a JSON object.');
    _callExit(2);
  }
  final categories = json['categories'];
  if (categories is Map) {
    config.categories = categories.map((k, v) => MapEntry(
        k.toString(), (v as List).map((e) => e.toString()).toList()));
  }
  final patternRules = json['pattern_rules'];
  if (patternRules is List) {
    config.patternRules = patternRules
        .map((e) => PatternRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  final autoRules = json['auto_rules'];
  if (autoRules is List) {
    config.autoRules = autoRules
        .map((e) => AutoRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  final excludes = json['exclude_patterns'];
  if (excludes is List) {
    config.excludePatterns = excludes.map((e) => e.toString()).toList();
  }
  config.renameTemplate =
      json['rename_template'] as String? ?? config.renameTemplate;
  config.dateTemplate =
      json['date_template'] as String? ?? config.dateTemplate;
  return config;
}

Future<void> _plan(_Opts opts, _Config config, StorageService storage) async {
  final root = opts.positionals.single;
  final organizer = _organizerFor(root, opts, config, storage);
  final scan = await organizer.scan();
  final actionable =
      scan.files.where((f) => !f.skipped && !f.isDuplicate).toList();
  final duplicates =
      scan.files.where((f) => !f.skipped && f.isDuplicate).toList();
  if (opts.flag('json')) {
    _write(jsonEncode(_summaryJson(root, actionable, duplicates)));
    return;
  }
  for (final file in actionable) {
    _write('${file.name}  →  ${file.destination}');
  }
  _write(
      '${actionable.length} file(s), ${formatBytes(scan.totalBytes)} — nothing was changed.');
  if (duplicates.isNotEmpty) {
    _write('${duplicates.length} duplicate(s) detected (would be skipped).');
  }
}

Future<void> _organize(_Opts opts, _Config config, StorageService storage) async {
  final root = opts.positionals.single;
  final organizer = _organizerFor(root, opts, config, storage);
  final scan = await organizer.scan();
  final duplicatesToTrash = opts.flag('duplicates-to-trash');
  final moves = scan.files
      .where((f) => !f.skipped && (!f.isDuplicate || duplicatesToTrash))
      .toList();
  if (moves.isEmpty) {
    if (!opts.flag('quiet')) _write('Nothing to organize in $root');
    return;
  }
  final entry = await organizer.execute(
    moves,
    progress: (done, total) {},
    log: opts.flag('quiet') || opts.flag('json') ? null : (m) => _write('  $m'),
    duplicatesToTrash: duplicatesToTrash,
  );
  final byCategory = <String, int>{};
  var bytes = 0;
  for (final file in moves) {
    byCategory[file.effectiveCategory] =
        (byCategory[file.effectiveCategory] ?? 0) + 1;
    bytes += file.size;
  }
  if (opts.flag('json')) {
    _write(jsonEncode({
      'root': root,
      'action': entry.action,
      'moved': moves.length,
      'bytes': bytes,
      'by_category': byCategory,
      'created_dirs': entry.createdDirs,
    }));
    return;
  }
  _write(
      'Organized ${moves.length} file(s) (${formatBytes(bytes)}) into '
      '${byCategory.length} '
      '${byCategory.length == 1 ? 'category' : 'categories'}.');
}

Future<void> _stats(_Opts opts, _Config config, StorageService storage) async {
  final root = opts.positionals.single;
  final organizer = _organizerFor(root, opts, config, storage);
  final scan = await organizer.scan();
  final stats = scan.stats;
  final duplicates = opts.flag('detect-duplicates')
      ? scan.files.where((f) => f.isDuplicate).length
      : 0;
  if (opts.flag('json')) {
    final rows = stats.map((name, stat) =>
        MapEntry(name, {'count': stat.count, 'bytes': stat.bytes}));
    _write(jsonEncode({
      'root': root,
      'files': scan.files.where((f) => !f.skipped).length,
      'bytes': scan.totalBytes,
      'duplicates': duplicates,
      'categories': rows,
    }));
    return;
  }
  final names = stats.keys.toList()..sort();
  final width = names.fold<int>(0, (w, n) => n.length > w ? n.length : w);
  _write(root);
  _write('---');
  for (final name in names) {
    final stat = stats[name]!;
    _write(
        '${name.padRight(width)}  ${stat.count.toString().padLeft(4)}  ${formatBytes(stat.bytes)}');
  }
  _write('---');
  _write(
      '${scan.files.where((f) => !f.skipped).length} file(s), ${formatBytes(scan.totalBytes)}');
  if (duplicates > 0) _write('$duplicates duplicate(s)');
}

Organizer _organizerFor(
    String root, _Opts opts, _Config config, StorageService storage) {
  return Organizer(
    storage: storage,
    root: root,
    categories: normalizeCategories(config.categories),
    byExtension: opts.boolFlag('by-extension', def: true),
    bySize: opts.flag('by-size'),
    byDate: opts.flag('by-date'),
    copyInsteadOfMove: opts.flag('copy'),
    patternRules: config.patternRules,
    autoRules: config.autoRules,
    detectDuplicates: opts.flag('detect-duplicates'),
    renameTemplate: config.renameTemplate,
    dateTemplate: config.dateTemplate,
    excludePatterns: config.excludePatterns,
  );
}

Map<String, dynamic> _summaryJson(
    String root, List<PlannedMove> moves, List<PlannedMove> duplicates) {
  final byCategory = <String, int>{};
  var bytes = 0;
  for (final file in moves) {
    byCategory[file.effectiveCategory] =
        (byCategory[file.effectiveCategory] ?? 0) + 1;
    bytes += file.size;
  }
  return {
    'root': root,
    'would_move': moves.length,
    'bytes': bytes,
    'by_category': byCategory,
    'duplicates': duplicates.length,
  };
}

class _Config {
  CategoryMap categories = {...defaultCategories};
  List<PatternRule> patternRules = [];
  List<AutoRule> autoRules = [];
  List<String> excludePatterns = [];
  String renameTemplate = '';
  String dateTemplate = '{year}-{month}';
}

/// Minimal flag parser: `--flag`, `--no-flag`, `--key value`, `--key=value`.
class _Opts {
  _Opts();

  final List<String> positionals = [];
  final Set<String> flags = {};
  final Map<String, List<String>> values = {};

  factory _Opts.parse(List<String> args) {
    final opts = _Opts();
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a.startsWith('--')) {
        final body = a.substring(2);
        if (body.contains('=')) {
          final eq = body.indexOf('=');
          opts._add(body.substring(0, eq), body.substring(eq + 1));
        } else if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          opts._add(body, args[i + 1]);
          i += 1;
        } else {
          opts.flags.add(body);
        }
      } else {
        opts.positionals.add(a);
      }
    }
    return opts;
  }

  void _add(String key, String value) {
    values.putIfAbsent(key, () => []).add(value);
  }

  bool flag(String name) => flags.contains(name);

  bool boolFlag(String name, {required bool def}) {
    if (flags.contains('no-$name')) return false;
    if (flags.contains(name)) return true;
    return def;
  }

  String? value(String name) {
    final list = values[name];
    return list == null || list.isEmpty ? null : list.last;
  }

  List<String> all(String name) => values[name] ?? const [];
}

/// dart:io storage backend for the CLI (no file_picker dependency).
class CliStorage implements StorageService {
  @override
  bool get isSupported => true;

  @override
  String get label => 'Local file system';

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<FileEntry>> listDirectory(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      throw FileSystemException('No such directory', directory);
    }
    final entries = <FileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is File) {
        final stat = entity.statSync();
        entries.add(FileEntry(
          name: name,
          size: stat.size,
          isDirectory: false,
          modified: stat.modified,
        ));
      } else if (entity is Directory) {
        final stat = entity.statSync();
        entries.add(FileEntry(
          name: name,
          size: 0,
          isDirectory: true,
          modified: stat.modified,
        ));
      }
    }
    return entries;
  }

  @override
  Future<bool> directoryExists(String directory, String name) =>
      Directory(p.join(directory, name)).exists();

  @override
  Future<String> ensureDirectory(String directory, String name) async {
    final dir = Directory(p.join(directory, name));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<void> moveFile(
      String srcDir, String srcName, String destDir, String destName) {
    return File(p.join(srcDir, srcName)).rename(p.join(destDir, destName));
  }

  @override
  Future<void> copyFile(
      String srcDir, String srcName, String destDir, String destName) {
    return File(p.join(srcDir, srcName)).copy(p.join(destDir, destName));
  }

  @override
  Future<void> deleteFile(String directory, String name) =>
      File(p.join(directory, name)).delete();

  @override
  Future<String?> fileHash(String directory, String name) async {
    final file = File(p.join(directory, name));
    if (!await file.exists()) return null;
    return sha256.convert(await file.readAsBytes()).toString();
  }

  @override
  Future<bool> removeEmptyDirectory(String directory) async {
    try {
      await Directory(directory).delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}