import 'package:file_organizer/ai/suggestion_engine.dart';
import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_storage.dart';

void main() {
  late FakeStorage storage;
  late SuggestionEngine engine;

  setUp(() {
    storage = FakeStorage();
    engine = SuggestionEngine(storage: storage, categories: defaultCategories);
  });

  ScanResult scanOf(String root, List<(String, String)> files) {
    storage.seed(root, files.map((f) => f.$1).toList());
    return ScanResult(
      root: root,
      files: [
        for (final (name, category) in files)
          PlannedMove(
            name: name,
            size: 100,
            category: category,
            destination: category,
            modified: DateTime(2026, 8, 1),
          ),
      ],
    );
  }

  test('keyword suggestion for an unclassified extension', () async {
    storage.seedHead('/x', 'receipt.scan', []);
    final scan = scanOf('/x', [('receipt.scan', 'Others')]);
    final suggestions = await engine.suggestAll(scan);
    expect(suggestions, hasLength(1));
    final s = suggestions.single;
    expect(s.toCategory, 'Documents');
    expect(s.fromCategory, 'Others');
    expect(s.reason, contains('receipt'));
  });

  test('content signature suggests a category without keywords', () async {
    storage.seedHead('/x', 'scan0001.bin', [0x25, 0x50, 0x44, 0x46]);
    final scan = scanOf('/x', [('scan0001.bin', 'Others')]);
    final suggestions = await engine.suggestAll(scan);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.toCategory, 'Documents');
    expect(suggestions.single.reason, contains('documents content signature'));
  });

  test('PNG content routes to Images', () async {
    storage.seedHead('/x', 'blob', [0x89, 0x50, 0x4E, 0x47]);
    final scan = scanOf('/x', [('blob', 'Others')]);
    final suggestions = await engine.suggestAll(scan);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.toCategory, 'Images');
  });

  test('no suggestion when the current category is already the winner', () async {
    final scan = scanOf('/x', [('report.pdf', 'Documents')]);
    expect(await engine.suggestAll(scan), isEmpty);
  });

  test('no suggestion when candidates are too close', () async {
    final scan = scanOf('/x', [('video_letter.docx', 'Documents')]);
    expect(await engine.suggestAll(scan), isEmpty);
  });

  test('skipped files are ignored', () async {
    final scan = scanOf('/x', [('receipt.scan', 'Others')]);
    scan.files.single.skipped = true;
    expect(await engine.suggestAll(scan), isEmpty);
  });
}