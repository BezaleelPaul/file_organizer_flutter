/// Reproducible benchmark for Mise's scan and duplicate pipeline.
///
/// Generates a throwaway fixture, then measures the two claims the README
/// makes: isolate-based recursive scanning and streamed duplicate detection.
///
/// Usage:
///   dart run scripts/bench.dart
///   dart run scripts/bench.dart --files 20000 --size-kb 16 --dup-groups 1000
///   dart run scripts/bench.dart --json
///   dart run scripts/bench.dart --keep        # keep the fixture directory
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_organizer/core/disk_scanner.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) {
    stderr.writeln(_usage);
    exit(64);
  }

  if (options.files < 1 || options.sizeKb < 1) {
    stderr.writeln('--files and --size-kb must be >= 1');
    exit(64);
  }
  if (options.dupGroups < 0 || options.dupGroups > options.files) {
    stderr.writeln('--dup-groups must be between 0 and --files');
    exit(64);
  }

  final root = await Directory.systemTemp.createTemp('mise_bench_');
  try {
    final fixtureClock = Stopwatch()..start();
    final fixture = await _buildFixture(root, options);
    fixtureClock.stop();

    final scanClock = Stopwatch()..start();
    final rssBeforeScan = ProcessInfo.currentRss;
    final scan = await scanTree(root.path);
    final rssAfterScan = ProcessInfo.currentRss;
    scanClock.stop();

    final dupClock = Stopwatch()..start();
    final duplicates = await findDuplicates(scan);
    final rssAfterDup = ProcessInfo.currentRss;
    dupClock.stop();

    final result = _Result(
      options: options,
      scan: scan,
      duplicates: duplicates,
      fixtureMs: fixtureClock.elapsedMilliseconds,
      scanMs: scanClock.elapsedMilliseconds,
      duplicateMs: dupClock.elapsedMilliseconds,
      fixtureBytes: fixture,
      scanRssDelta: max(0, rssAfterScan - rssBeforeScan),
      duplicateRssDelta: max(0, rssAfterDup - rssAfterScan),
    );

    if (options.json) {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    } else {
      stdout.writeln(result.toText(root));
    }
  } catch (error, stack) {
    stderr.writeln('Benchmark failed: $error');
    stderr.writeln(stack);
    exitCode = 1;
  } finally {
    if (options.keep) {
      stdout.writeln('Fixture kept at ${root.path}');
    } else {
      try {
        await root.delete(recursive: true);
      } catch (_) {
        // Best effort; the OS temp cleaner will get it.
      }
    }
  }
}

const _usage = '''
Mise benchmark

Options:
  --files <n>       Unique files to generate (default: 5000)
  --size-kb <n>     Size of each file in KiB (default: 8)
  --dup-groups <n>  Exact copies of existing files (default: 250)
  --json            Print machine-readable JSON
  --keep            Keep the generated fixture directory
  --help            Show this help

Example (about 1 GB):
  dart run scripts/bench.dart --files 15000 --size-kb 64 --dup-groups 1000
''';

class _Options {
  const _Options({
    required this.files,
    required this.sizeKb,
    required this.dupGroups,
    required this.json,
    required this.keep,
  });

  final int files;
  final int sizeKb;
  final int dupGroups;
  final bool json;
  final bool keep;

  static _Options? parse(List<String> args) {
    var files = 5000;
    var sizeKb = 8;
    var dupGroups = 250;
    var json = false;
    var keep = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? value() {
        if (arg.contains('=')) return arg.split('=').last;
        if (i + 1 < args.length) return args[++i];
        return null;
      }

      switch (arg.split('=').first) {
        case '--files':
          final parsed = int.tryParse(value() ?? '');
          if (parsed == null) return null;
          files = parsed;
        case '--size-kb':
          final parsed = int.tryParse(value() ?? '');
          if (parsed == null) return null;
          sizeKb = parsed;
        case '--dup-groups':
          final parsed = int.tryParse(value() ?? '');
          if (parsed == null) return null;
          dupGroups = parsed;
        case '--json':
          json = true;
        case '--keep':
          keep = true;
        case '--help':
        case '-h':
          return null;
        default:
          if (arg.trim().isEmpty) continue;
          return null;
      }
    }

    return _Options(
      files: files,
      sizeKb: sizeKb,
      dupGroups: dupGroups,
      json: json,
      keep: keep,
    );
  }
}

/// Writes [options.files] unique files plus [options.dupGroups] exact copies.
/// Returns the total bytes written.
Future<int> _buildFixture(Directory root, _Options options) async {
  final size = options.sizeKb * 1024;
  var written = 0;

  String path(String name) => '${root.path}${Platform.pathSeparator}$name';

  // Write in small batches: sequential awaits are dominated by per-file
  // syscall latency and make fixture creation slower than the benchmark.
  const batchSize = 64;
  for (var start = 0; start < options.files; start += batchSize) {
    final end = min(start + batchSize, options.files);
    final batch = <Future<void>>[];
    for (var i = start; i < end; i++) {
      final payload = _payload(size, i + 1);
      batch.add(
        File(path('unique_${_pad(i)}.bin')).writeAsBytes(payload, flush: false),
      );
      written += payload.length;
    }
    await Future.wait(batch);
  }

  for (var start = 0; start < options.dupGroups; start += batchSize) {
    final end = min(start + batchSize, options.dupGroups);
    final batch = <Future<void>>[];
    for (var i = start; i < end; i++) {
      final sourceIndex = i % options.files;
      final source = File(path('unique_${_pad(sourceIndex)}.bin'));
      final payload = await source.readAsBytes();
      batch.add(
        File(path('dup_${_pad(i)}.bin')).writeAsBytes(payload, flush: false),
      );
      written += payload.length;
    }
    await Future.wait(batch);
  }

  return written;
}

/// Deterministic bytes: fast LCG plus the seed in the first 8 bytes so files
/// with the same size still get distinct head signatures.
Uint8List _payload(int size, int seed) {
  final bytes = Uint8List(size);
  var state = (seed * 2654435761) & 0xFFFFFFFF;
  for (var i = 0; i < size; i++) {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    bytes[i] = (state >> 24) & 0xFF;
  }
  for (var i = 0; i < 8 && i < size; i++) {
    bytes[i] = (seed >> (8 * i)) & 0xFF;
  }
  return bytes;
}

String _pad(int value) => value.toString().padLeft(6, '0');

class _Result {
  const _Result({
    required this.options,
    required this.scan,
    required this.duplicates,
    required this.fixtureMs,
    required this.scanMs,
    required this.duplicateMs,
    required this.fixtureBytes,
    required this.scanRssDelta,
    required this.duplicateRssDelta,
  });

  final _Options options;
  final DiskScan scan;
  final List<DuplicateGroup> duplicates;
  final int fixtureMs;
  final int scanMs;
  final int duplicateMs;
  final int fixtureBytes;
  final int scanRssDelta;
  final int duplicateRssDelta;

  int get reclaimable =>
      duplicates.fold(0, (sum, group) => sum + group.reclaimable);

  double get scanFilesPerSecond =>
      scanMs == 0 ? 0 : scan.files.length / (scanMs / 1000);

  Map<String, Object?> toJson() => {
    'fixture': {
      'files': scan.files.length,
      'bytes': scan.totalBytes,
      'sizeKb': options.sizeKb,
      'dupGroups': options.dupGroups,
      'buildMs': fixtureMs,
    },
    'scan': {
      'ms': scanMs,
      'files': scan.files.length,
      'filesPerSecond': scanFilesPerSecond.round(),
    },
    'duplicates': {
      'ms': duplicateMs,
      'groups': duplicates.length,
      'reclaimableBytes': reclaimable,
    },
    'rssDeltaBytes': {'scan': scanRssDelta, 'duplicates': duplicateRssDelta},
  };

  String toText(Directory root) {
    final lines = <String>[
      'Mise benchmark',
      'Root: ${root.path}',
      'Fixture: ${_n(options.files)} unique + ${_n(options.dupGroups)} copies, '
          '${options.sizeKb} KiB each (${_mb(fixtureBytes)}) '
          'built in ${_n(fixtureMs)} ms',
      '',
      'Scan (isolate)        ${_n(scanMs)} ms   '
          '${_n(scan.files.length)} files, ${_mb(scan.totalBytes)}   '
          '${_n(scanFilesPerSecond.round())} files/s',
      'Duplicate detection   ${_n(duplicateMs)} ms   '
          '${_n(duplicates.length)} groups, ${_mb(reclaimable)} reclaimable',
      'RSS delta             ${_mb(scanRssDelta)} during scan, '
          '${_mb(duplicateRssDelta)} during hashing',
      '',
      'Note: RSS includes isolate startup and Dart VM noise. '
          'Hashing memory is bounded by design, not by file size.',
    ];
    return lines.join('\n');
  }
}

String _n(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
