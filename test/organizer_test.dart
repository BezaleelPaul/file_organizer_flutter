import 'package:file_organizer/core/organizer.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_storage.dart';

void main() {
  group('Organizer', () {
    test('scan plans moves by extension and date', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['photo.jpg', 'notes.pdf', 'song.mp3']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: true,
      );

      final result = await organizer.scan();
      expect(result.files, hasLength(3));
      final photo =
          result.files.firstWhere((f) => f.name == 'photo.jpg');
      expect(photo.category, 'Images');
      expect(photo.destination, 'Images/2026-08');
    });

    test('execute moves files and records journal', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt', 'notes.pdf']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      final journal = await organizer.execute(
        plan.files,
        progress: (_, _) {},
      );

      expect(journal.count, 3);
      expect(storage.dirs['/dl'], isEmpty);
      expect(storage.dirs['/dl/Images'], hasLength(1));
      expect(storage.dirs['/dl/Images']!.first.name, 'a.png');
      expect(storage.dirs['/dl/Documents'], hasLength(2));
    });

    test('skipped files are left alone', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'keep.txt']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      plan.files.firstWhere((f) => f.name == 'keep.txt').skipped = true;

      await organizer.execute(plan.files, progress: (_, _) {});

      expect(storage.dirs['/dl'], hasLength(1));
      expect(storage.dirs['/dl']!.first.name, 'keep.txt');
    });

    test('unique naming when destination already has the file', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'logo.png']);
      storage.seed('/dl/Images', ['a.png'], realDirectory: true);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      await organizer.execute(plan.files, progress: (_, _) {});

      final names = storage.dirs['/dl/Images']!.map((e) => e.name).toList();
      expect(names, contains('a.png'));
      expect(names, contains('a (1).png'));
    });

    test('override category redirects to its folder', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      plan.files.first.overrideCategory = 'Music';

      await organizer.execute(plan.files, progress: (_, _) {});

      expect(storage.dirs['/dl/Music'], hasLength(1));
      expect(storage.dirs.containsKey('/dl/Images'), isFalse);
    });

    test('undo restores files and removes created dirs', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      final journal = await organizer.execute(plan.files, progress: (_, _) {});

      expect(storage.dirs['/dl'], isEmpty);

      await organizer.undo(journal);

      expect(storage.dirs['/dl'], hasLength(1));
      expect(storage.dirs['/dl']!.first.name, 'a.png');
      expect(storage.dirs.containsKey('/dl/Images'), isFalse);
    });

    test('copy keeps the original', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
        copyInsteadOfMove: true,
      );

      final plan = await organizer.scan();
      final journal = await organizer.execute(plan.files, progress: (_, _) {});

      expect(journal.action, 'copy');
      expect(storage.dirs['/dl'], hasLength(1));
      expect(storage.dirs['/dl/Images'], hasLength(1));
    });
  });
}