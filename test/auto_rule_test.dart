import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_storage.dart';

void main() {
  group('AutoRule.matches', () {
    test('extension-only rule', () {
      final rule = AutoRule(name: 'pdfs', extensions: const ['.pdf']);
      expect(rule.matches(fileName: 'a.pdf', extension: '.pdf', size: 0, modified: DateTime(2026, 1, 1)), isTrue);
      expect(rule.matches(fileName: 'a.txt', extension: '.txt', size: 0, modified: DateTime(2026, 1, 1)), isFalse);
    });

    test('name pattern rule', () {
      final rule = AutoRule(name: 'img', namePattern: r'^IMG_');
      expect(rule.matches(fileName: 'IMG_001.jpg', extension: '.jpg', size: 0, modified: DateTime(2026, 1, 1)), isTrue);
      expect(rule.matches(fileName: 'PHOTO_001.jpg', extension: '.jpg', size: 0, modified: DateTime(2026, 1, 1)), isFalse);
    });

    test('size range rule', () {
      final rule = AutoRule(name: 'big', minSize: 100, maxSize: 1000);
      expect(rule.matches(fileName: 'a', extension: '', size: 500, modified: DateTime(2026, 1, 1)), isTrue);
      expect(rule.matches(fileName: 'a', extension: '', size: 99, modified: DateTime(2026, 1, 1)), isFalse);
      expect(rule.matches(fileName: 'a', extension: '', size: 1001, modified: DateTime(2026, 1, 1)), isFalse);
    });

    test('modified window rule', () {
      final rule = AutoRule(name: 'recent', modifiedAfter: DateTime(2026, 8, 1));
      expect(rule.matches(fileName: 'a', extension: '', size: 0, modified: DateTime(2026, 8, 10)), isTrue);
      expect(rule.matches(fileName: 'a', extension: '', size: 0, modified: DateTime(2026, 7, 31)), isFalse);
    });

    test('all conditions must match (AND)', () {
      final rule = AutoRule(
        name: 'scanner pdfs',
        extensions: const ['.pdf'],
        namePattern: r'^scan_',
        minSize: 10,
        modifiedAfter: DateTime(2026, 1, 1),
      );
      expect(rule.matches(fileName: 'scan_01.pdf', extension: '.pdf', size: 50, modified: DateTime(2026, 6, 1)), isTrue);
      expect(rule.matches(fileName: 'report.pdf', extension: '.pdf', size: 50, modified: DateTime(2026, 6, 1)), isFalse);
      expect(rule.matches(fileName: 'scan_01.txt', extension: '.txt', size: 50, modified: DateTime(2026, 6, 1)), isFalse);
      expect(rule.matches(fileName: 'scan_01.pdf', extension: '.pdf', size: 5, modified: DateTime(2026, 6, 1)), isFalse);
    });

    test('no conditions matches everything', () {
      final rule = AutoRule(name: 'catch all');
      expect(rule.matches(fileName: 'anything', extension: '.zzz', size: 1, modified: DateTime(2020, 1, 1)), isTrue);
    });

    test('disabled rule never matches', () {
      final rule = AutoRule(name: 'off', extensions: const ['.pdf'], enabled: false);
      expect(rule.matches(fileName: 'a.pdf', extension: '.pdf', size: 0, modified: DateTime(2026, 1, 1)), isFalse);
    });

    test('invalid regex is ignored', () {
      final rule = AutoRule(name: 'bad', namePattern: '(');
      expect(rule.nameRegex, isNull);
      expect(rule.matches(fileName: 'a', extension: '', size: 0, modified: DateTime(2026, 1, 1)), isTrue);
    });
  });

  group('AutoRule JSON', () {
    test('round-trips every field', () {
      final rule = AutoRule(
        name: 'scans',
        category: 'Scans',
        extensions: const ['.pdf'],
        namePattern: r'^scan',
        minSize: 5,
        maxSize: 9000,
        modifiedAfter: DateTime(2026, 1, 1, 12),
        modifiedBefore: DateTime(2026, 12, 31),
        enabled: false,
      );
      final restored = AutoRule.fromJson(rule.toJson());
      expect(restored.name, 'scans');
      expect(restored.category, 'Scans');
      expect(restored.extensions, ['.pdf']);
      expect(restored.namePattern, r'^scan');
      expect(restored.minSize, 5);
      expect(restored.maxSize, 9000);
      expect(restored.modifiedAfter, DateTime(2026, 1, 1, 12));
      expect(restored.modifiedBefore, DateTime(2026, 12, 31));
      expect(restored.enabled, isFalse);
    });
  });

  group('Organizer integration', () {
    test('auto rule overrides extension classification', () async {
      final storage = FakeStorage()
        ..seed('/root', ['scan_01.pdf', 'report.docx', 'notes.txt']);
      final organizer = Organizer(
        storage: storage,
        root: '/root',
        categories: defaultCategories,
        byExtension: true,
        autoRules: [
          AutoRule(name: 'scans', extensions: const ['.pdf'], namePattern: r'^scan_', category: 'Scans'),
        ],
      );
      final result = await organizer.scan();
      final byName = {for (final f in result.files) f.name: f};
      expect(byName['scan_01.pdf']!.category, 'Scans');
      expect(byName['report.docx']!.category, 'Documents');
      expect(byName['notes.txt']!.category, 'Documents');
    });

    test('first matching rule wins', () async {
      final storage = FakeStorage()..seed('/root', ['x.pdf']);
      final organizer = Organizer(
        storage: storage,
        root: '/root',
        categories: defaultCategories,
        byExtension: true,
        autoRules: [
          AutoRule(name: 'all pdfs', extensions: const ['.pdf'], category: 'Docs2'),
          AutoRule(name: 'scans', namePattern: r'^x', category: 'Scans'),
        ],
      );
      final result = await organizer.scan();
      expect(result.files.single.category, 'Docs2');
    });

    test('size condition routes only big files', () async {
      final storage = FakeStorage()
        ..seed('/root', ['small.bin'])
        ..seedWithSize('/root', 'big.bin', 200);
      final organizer = Organizer(
        storage: storage,
        root: '/root',
        categories: defaultCategories,
        byExtension: true,
        autoRules: [
          AutoRule(name: 'big files', minSize: 150, category: 'Backups'),
        ],
      );
      final result = await organizer.scan();
      final byName = {for (final f in result.files) f.name: f};
      expect(byName['big.bin']!.category, 'Backups');
      expect(byName['small.bin']!.category, 'Others');
    });
  });
}