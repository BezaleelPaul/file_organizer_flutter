import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_storage.dart';

void main() {
  group('Pattern rules', () {
    test('regex pattern routes files by name', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['IMG_001.jpg', 'report.pdf']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        patternRules: [
          PatternRule(pattern: r'^IMG_', category: 'Screenshots'),
        ],
      );

      final result = await organizer.scan();
      final img = result.files.firstWhere((f) => f.name == 'IMG_001.jpg');
      expect(img.category, 'Screenshots');
      final report = result.files.firstWhere((f) => f.name == 'report.pdf');
      expect(report.category, 'Documents');
    });

    test('disabled pattern rules are ignored', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['IMG_001.jpg']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        patternRules: [
          PatternRule(pattern: r'^IMG_', category: 'Screenshots', enabled: false),
        ],
      );

      final result = await organizer.scan();
      expect(result.files.single.category, 'Images');
    });
  });

  group('Templates', () {
    test('date template supports nested year/month', () async {
      expect(
        dateSubfolder(DateTime(2026, 8, 14), template: '{year}/{month}'),
        '2026/08',
      );
      expect(
        dateSubfolder(DateTime(2026, 8, 14), template: '{year}-{month}-{day}'),
        '2026-08-14',
      );
    });

    test('scan builds nested date destinations', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['photo.jpg']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        byDate: true,
        dateTemplate: '{year}/{month}',
      );

      final result = await organizer.scan();
      expect(result.files.single.destination, 'Images/2026/08');
    });

    test('rename template renames files during execute', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['IMG_1.jpg', 'IMG_2.jpg']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        renameTemplate: 'shot_{counter}',
      );

      final plan = await organizer.scan();
      await organizer.execute(plan.files, progress: (_, _) {});

      final names = storage.dirs['/dl/Images']!.map((e) => e.name).toList();
      expect(names, contains('shot_0.jpg'));
      expect(names, contains('shot_1.jpg'));
    });

    test('rename template preserves extension when absent', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['IMG_1.jpg']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        renameTemplate: '{category}_{name}',
      );

      final plan = await organizer.scan();
      await organizer.execute(plan.files, progress: (_, _) {});

      final names = storage.dirs['/dl/Images']!.map((e) => e.name).toList();
      expect(names, contains('Images_IMG_1.jpg'));
    });
  });

  group('Excludes', () {
    test('excluded files are skipped during scan', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['photo.jpg', 'photo.tmp', 'draft.pdf']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        excludePatterns: [r'\.tmp$'],
      );

      final result = await organizer.scan();
      expect(result.files.map((f) => f.name).toList(), ['photo.jpg', 'draft.pdf']);
    });
  });

  group('Category whitelist', () {
    test('non-whitelisted categories fall back to Others', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['photo.jpg', 'song.mp3']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        allowedCategories: {'Images'},
      );

      final result = await organizer.scan();
      final photo = result.files.firstWhere((f) => f.name == 'photo.jpg');
      final song = result.files.firstWhere((f) => f.name == 'song.mp3');
      expect(photo.category, 'Images');
      expect(song.category, 'Others');
    });
  });

  group('Duplicates', () {
    test('byte-identical files are flagged', () async {
      final storage = FakeStorage();
      storage.seedWithSize('/dl', 'a.png', 100);
      storage.seedWithSize('/dl', 'a copy.png', 100);
      storage.seedWithSize('/dl', 'different.png', 500);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        detectDuplicates: true,
      );

      final result = await organizer.scan();
      final flagged = result.files.where((f) => f.isDuplicate).toList();
      expect(flagged, hasLength(1));
      expect(flagged.single.name, 'a copy.png');
    });

    test('duplicates are sent to Trash during execute', () async {
      final storage = FakeStorage();
      storage.seedWithSize('/dl', 'a.png', 100);
      storage.seedWithSize('/dl', 'a copy.png', 100);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        detectDuplicates: true,
      );

      final plan = await organizer.scan();
      await organizer.execute(plan.files, progress: (_, _) {},
          duplicatesToTrash: true);

      final trashNames =
          storage.dirs['/dl/Trash']!.map((e) => e.name).toList();
      expect(trashNames, ['a copy.png']);
      expect(storage.dirs['/dl/Images']!.map((e) => e.name).toList(), ['a.png']);
    });
  });

  group('Trash', () {
    test('trash moves files into reversible folder', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
      );

      final plan = await organizer.scan();
      final entry = await organizer.trash([plan.files.first]);

      expect(entry.action, 'trash');
      expect(storage.dirs['/dl/Trash']!.map((e) => e.name).toList(), ['a.png']);
      expect(storage.dirs['/dl'], hasLength(1));

      await organizer.undo(entry);
      expect(storage.dirs['/dl']!.map((e) => e.name).toList(), contains('a.png'));
    });
  });
}
