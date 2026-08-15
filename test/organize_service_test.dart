import 'package:file_organizer/core/rules.dart';
import 'package:file_organizer/services/organize_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_storage.dart';

OrganizeConfig _config() => OrganizeConfig(
      categories: defaultCategories,
      byExtension: true,
      bySize: false,
      byDate: false,
      copyInsteadOfMove: false,
      detectDuplicates: false,
      renameTemplate: '',
      dateTemplate: '{year}-{month}',
      patternRules: const [],
      autoRules: const [],
      excludePatterns: const [],
      allowedCategories: const {},
    );

void main() {
  group('OrganizeService', () {
    test('scan plans moves without executing', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt']);

      final service = OrganizeService(storage: storage);
      final plan = await service.scan('/dl', _config());

      expect(plan.files, hasLength(2));
      expect(plan.files.first.category, 'Images');
      expect(storage.dirs['/dl'], hasLength(2));
    });

    test('organize scans, filters and executes, returning a journal', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt', 'c.mp3']);

      final service = OrganizeService(storage: storage);
      final result = await service.organize('/dl', _config());

      expect(result.hasChanges, isTrue);
      expect(result.entry!.count, 3);
      expect(storage.dirs['/dl'], isEmpty);
      expect(storage.dirs['/dl/Images'], hasLength(1));
      expect(storage.dirs['/dl/Documents'], hasLength(1));
      expect(storage.dirs['/dl/Music'], hasLength(1));
    });

    test('organize reports no changes when nothing is actionable', () async {
      final storage = FakeStorage();
      storage.seed('/dl', []);

      final service = OrganizeService(storage: storage);
      final result = await service.organize('/dl', _config());

      expect(result.hasChanges, isFalse);
      expect(result.entry, isNull);
    });

    test('organize honors skipped files', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt']);

      final service = OrganizeService(storage: storage);
      final plan = await service.scan('/dl', _config());
      plan.files.firstWhere((f) => f.name == 'b.txt').skipped = true;

      // Execute the reviewed plan through the service.
      final entry = await service.executePlan('/dl', plan.files, _config());
      expect(entry.count, 1);
      expect(storage.dirs['/dl'], hasLength(1));
      expect(storage.dirs['/dl']!.first.name, 'b.txt');
    });

    test('trash moves files into the reversible Trash folder', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png', 'b.txt']);

      final service = OrganizeService(storage: storage);
      final plan = await service.scan('/dl', _config());
      final entry = await service.trash('/dl', plan.files, _config());

      expect(entry.count, 2);
      expect(storage.dirs['/dl'], isEmpty);
      expect(storage.dirs['/dl/Trash'], hasLength(2));
    });

    test('undo restores files and removes created dirs', () async {
      final storage = FakeStorage();
      storage.seed('/dl', ['a.png']);

      final service = OrganizeService(storage: storage);
      final entry = await service.executePlan(
        '/dl',
        (await service.scan('/dl', _config())).files,
        _config(),
      );

      expect(storage.dirs['/dl'], isEmpty);
      await service.undo(entry);
      expect(storage.dirs['/dl'], hasLength(1));
    });
  });
}