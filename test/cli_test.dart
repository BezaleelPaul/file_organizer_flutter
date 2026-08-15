import 'dart:convert';
import 'dart:io';

import 'package:file_organizer/cli.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end tests for the headless CLI. They exercise the shared engine
/// exactly as a script would, running the CLI in-process with captured output.
void main() {
  test('plan lists destinations without moving anything', () async {
    final dir = Directory.systemTemp.createTempSync('mise_plan');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'a.jpg', 'img');
    _write(dir.path, 'b.pdf', 'doc');

    final output = await _runCli(['plan', dir.path]);
    expect(output.exitCode, 0);
    expect(output.out, contains('a.jpg  →  Images'));
    expect(output.out, contains('b.pdf  →  Documents'));
    expect(output.out, contains('nothing was changed'));
    expect(dir.listSync().whereType<File>().length, 2);
  });

  test('organize moves files into category folders', () async {
    final dir = Directory.systemTemp.createTempSync('mise_organize');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'a.jpg', 'img');
    _write(dir.path, 'b.pdf', 'doc');

    final output = await _runCli(['organize', dir.path, '--json']);
    expect(output.exitCode, 0);
    final json = jsonDecode(output.out.trim()) as Map<String, dynamic>;
    expect(json['moved'], 2);
    expect(json['by_category'], {'Images': 1, 'Documents': 1});
    expect(File('${dir.path}/Images/a.jpg').existsSync(), isTrue);
    expect(File('${dir.path}/Documents/b.pdf').existsSync(), isTrue);
  });

  test('--no-by-extension with --by-size buckets by size', () async {
    final dir = Directory.systemTemp.createTempSync('mise_size');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'tiny.dat', 'x');
    _write(dir.path, 'big.dat', 'x' * (5 * 1024 * 1024));

    final output = await _runCli(
        ['plan', dir.path, '--no-by-extension', '--by-size']);
    expect(output.exitCode, 0);
    expect(output.out, contains('tiny.dat  →  Small'));
    expect(output.out, contains('big.dat  →  Medium'));
  });

  test('stats reports per-category totals', () async {
    final dir = Directory.systemTemp.createTempSync('mise_stats');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'a.jpg', 'img');
    _write(dir.path, 'b.jpg', 'img');

    final output = await _runCli(['stats', dir.path, '--json']);
    expect(output.exitCode, 0);
    final json = jsonDecode(output.out.trim()) as Map<String, dynamic>;
    expect(json['files'], 2);
    expect((json['categories'] as Map)['Images'], isNotNull);
  });

  test('boolean flags may come before the folder', () async {
    final dir = Directory.systemTemp.createTempSync('mise_plan_json');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'a.jpg', 'img');

    final output = await _runCli(['plan', '--json', dir.path]);
    expect(output.exitCode, 0);
    final json = jsonDecode(output.out.trim()) as Map<String, dynamic>;
    expect(json['would_move'], 1);
  });

  test('--quiet before the folder still organizes', () async {
    final dir = Directory.systemTemp.createTempSync('mise_quiet');
    addTearDown(() => dir.deleteSync(recursive: true));
    _write(dir.path, 'a.jpg', 'img');

    final output = await _runCli(['organize', '--quiet', dir.path]);
    expect(output.exitCode, 0);
    expect(output.out, isNot(contains('Images')));
    expect(File('${dir.path}/Images/a.jpg').existsSync(), isTrue);
  });
}

void _write(String dir, String name, String content) {
  File('$dir${Platform.pathSeparator}$name').writeAsStringSync(content);
}

Future<({String out, String err, int exitCode})> _runCli(List<String> args) async {
  final out = <String>[];
  final err = <String>[];
  var exitCode = 0;
  await runCli(
    args,
    out: out.add,
    err: err.add,
    exitFn: (code) => exitCode = code,
  );
  return (out: out.join('\n'), err: err.join('\n'), exitCode: exitCode);
}