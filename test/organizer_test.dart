import 'package:file_organizer/core/models.dart';
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
      final photo = result.files.firstWhere((f) => f.name == 'photo.jpg');
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
      final journal = await organizer.execute(plan.files, progress: (_, _) {});

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

    test('failed execute rolls back moves that already completed', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.png']);
      storage.failOn('b.png');

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        bySize: false,
        byDate: false,
      );

      final plan = await organizer.scan();
      final intents = <MoveRecord>[];
      final done = <MoveRecord>[];

      await expectLater(
        organizer.execute(
          plan.files,
          progress: (_, _) {},
          beforeMove: (record) async => intents.add(record),
          afterMove: (record) async => done.add(record),
        ),
        throwsA(
          isA<OrganizeFailure>()
              .having((e) => e.rolledBack, 'rolledBack', isTrue)
              .having((e) => e.entry.moves, 'entry.moves', isEmpty),
        ),
      );

      expect(intents, hasLength(2));
      expect(done, hasLength(1));
      expect(
        storage.dirs['/dl']!.map((e) => e.name),
        containsAll(['a.png', 'b.png']),
      );
      expect(storage.dirs.containsKey('/dl/Images'), isFalse);
    });

    test('undo of a copy deletes the copy instead of renaming it', () async {
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
      expect(storage.dirs['/dl/Images'], hasLength(1));

      await organizer.undo(journal);

      expect(storage.dirs['/dl']!.single.name, 'a.png');
      expect(storage.dirs.containsKey('/dl/Images'), isFalse);
    });

    test(
      'traversal in an override category is rejected before any move',
      () async {
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
        plan.files.single.overrideCategory = '../evil';

        await expectLater(
          organizer.execute(plan.files, progress: (_, _) {}),
          throwsA(isA<FormatException>()),
        );
        expect(storage.dirs['/dl']!.single.name, 'a.png');
      },
    );

    test('traversal in the date template is rejected during scan', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png']);

      final organizer = Organizer(
        storage: storage,
        root: '/dl',
        categories: defaultCategories,
        byExtension: true,
        byDate: true,
        dateTemplate: '../{year}',
      );

      await expectLater(organizer.scan(), throwsA(isA<FormatException>()));
    });

    test('undo restores to a free name instead of overwriting', () async {
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
      storage.seed('/dl', ['a.png']);

      await organizer.undo(journal);

      final names = storage.dirs['/dl']!.map((e) => e.name).toList();
      expect(names, containsAll(['a.png', 'a (1).png']));
    });

    test('undo reports failures and leaves the file in place', () async {
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
      storage.failOn('a.png');

      await expectLater(organizer.undo(journal), throwsA(isA<UndoFailure>()));
      expect(storage.dirs['/dl/Images'], hasLength(1));
    });

    test('case-insensitive storage avoids case-name collisions', () async {
      final storage = FakeStorage()..setCaseInsensitive();
      storage.seed('/dl', ['report.PDF']);
      storage.seed('/dl/Documents', ['report.pdf'], realDirectory: true);

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

      final names = storage.dirs['/dl/Documents']!.map((e) => e.name).toList();
      expect(names, contains('report.pdf'));
      expect(names, contains('report (1).PDF'));
    });
  });
}
