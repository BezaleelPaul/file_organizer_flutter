import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/core/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyFile', () {
    test('extension match wins', () {
      expect(
        classifyFile(
          extension: '.jpg',
          sizeBytes: 5,
          categories: defaultCategories,
          byExtension: true,
          bySize: false,
        ),
        'Images',
      );
    });

    test('falls back to Others when no match', () {
      expect(
        classifyFile(
          extension: '.xyz',
          sizeBytes: 5,
          categories: defaultCategories,
          byExtension: true,
          bySize: false,
        ),
        'Others',
      );
    });

    test('size bucket when extension disabled', () {
      expect(
        classifyFile(
          extension: '.jpg',
          sizeBytes: 5,
          categories: defaultCategories,
          byExtension: false,
          bySize: true,
        ),
        'Small',
      );
      expect(
        classifyFile(
          extension: '.jpg',
          sizeBytes: 50 * 1024 * 1024,
          categories: defaultCategories,
          byExtension: false,
          bySize: true,
        ),
        'Medium',
      );
    });
  });

  group('uniqueName', () {
    test('keeps name when free', () {
      expect(uniqueName('a.txt', {'b.txt'}), 'a.txt');
    });

    test('adds numeric suffix', () {
      expect(uniqueName('a.txt', {'a.txt'}), 'a (1).txt');
      expect(uniqueName('a.txt', {'a.txt', 'a (1).txt'}), 'a (2).txt');
    });

    test('handles files without extension', () {
      expect(uniqueName('LICENSE', {'LICENSE'}), 'LICENSE (1)');
    });

    test('case-insensitive mode avoids case collisions', () {
      expect(
        uniqueName('a.txt', {'A.txt'}, caseInsensitive: true),
        'a (1).txt',
      );
      expect(
        uniqueName('A.txt', {'a.txt', 'a (1).txt'}, caseInsensitive: true),
        'A (2).txt',
      );
    });
  });

  test('sizeBucketFor boundaries', () {
    expect(sizeBucketFor(0), 'Small');
    expect(sizeBucketFor(1024 * 1024 - 1), 'Small');
    expect(sizeBucketFor(1024 * 1024), 'Medium');
    expect(sizeBucketFor(100 * 1024 * 1024), 'Large');
  });

  test('extensionOf', () {
    expect(extensionOf('photo.JPG'), '.jpg');
    expect(extensionOf('README'), '');
    expect(extensionOf('archive.tar.gz'), '.gz');
  });

  test('dateSubfolder zero-pads month', () {
    expect(dateSubfolder(DateTime(2026, 8, 1)), '2026-08');
    expect(dateSubfolder(DateTime(2026, 1, 1)), '2026-01');
  });

  test('normalizeCategories adds Others and lower-cases', () {
    final result = normalizeCategories({
      'Images': ['.PNG', '.jpg'],
      'Empty': [],
    });
    expect(result['Images'], ['.png', '.jpg']);
    expect(result.containsKey('Others'), isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });

  group('path safety', () {
    test('rejects traversal and separators', () {
      expect(isSafePathSegment('..'), isFalse);
      expect(isSafePathSegment('.'), isFalse);
      expect(isSafePathSegment('a/b'), isFalse);
      expect(isSafePathSegment(r'a\b'), isFalse);
      expect(isSafePathSegment('/etc'), isFalse);
      expect(isSafePathSegment('C:\\Windows'), isFalse);
      expect(isSafePathSegment(''), isFalse);
    });

    test('rejects Windows reserved names and trailing dots', () {
      expect(isSafePathSegment('CON'), isFalse);
      expect(isSafePathSegment('con.txt'), isFalse);
      expect(isSafePathSegment('LPT1'), isFalse);
      expect(isSafePathSegment('folder.'), isFalse);
      expect(isSafePathSegment('folder '), isFalse);
      expect(isSafePathSegment('Images'), isTrue);
      expect(isSafePathSegment('2026-08'), isTrue);
    });

    test('splitTemplatePath validates each segment', () {
      expect(splitTemplatePath('{year}/{month}'), ['{year}', '{month}']);
      expect(
        () => splitTemplatePath('../{year}'),
        throwsA(isA<FormatException>()),
      );
      expect(() => splitTemplatePath('{year}//{month}'), returnsNormally);
    });

    test('sanitizeFileName makes portable names', () {
      expect(sanitizeFileName('a/b:c?.txt'), 'a_b_c_.txt');
      expect(sanitizeFileName('CON.txt'), startsWith('_CON'));
      expect(sanitizeFileName('name.  '), 'name');
      expect(sanitizeFileName('..'), isNull);
      expect(sanitizeFileName('   '), isNull);
    });
  });

  group('ChefRecipe', () {
    test('contains curated playbook recipes', () {
      expect(ChefRecipe.all, isNotEmpty);
      final ids = ChefRecipe.all.map((r) => r.id).toList();
      expect(ids, contains('download_janitor'));
      expect(ids, contains('tax_vault'));
      expect(ids, contains('media_darkroom'));
      expect(ids, contains('dev_forge'));
    });

    test('download_janitor recipe matches installer and screenshot patterns', () {
      final janitor = ChefRecipe.all.firstWhere((r) => r.id == 'download_janitor');
      final installerRule = janitor.patternRules.firstWhere((r) => r.category == 'Installers');
      expect(installerRule.regex.hasMatch('setup_v2.exe'), isTrue);
      expect(installerRule.regex.hasMatch('archive.dmg'), isTrue);

      final screenshotRule = janitor.patternRules.firstWhere((r) => r.category == 'Screenshots');
      expect(screenshotRule.regex.hasMatch('Screenshot_2026-10-25.png'), isTrue);
    });
  });

  group('calculateEntropy', () {
    test('empty files yields Michelin Star Zen', () {
      final report = calculateEntropy([]);
      expect(report.score, 0);
      expect(report.status, contains('Zen'));
    });

    test('installer clutter elevates entropy score', () {
      final now = DateTime.now();
      final files = List.generate(
        10,
        (i) => PlannedMove(
          name: 'installer_$i.exe',
          size: 50 * 1024 * 1024,
          category: 'Programs',
          destination: 'Programs',
          modified: now,
        ),
      );

      final report = calculateEntropy(files);
      expect(report.installerCount, 10);
      expect(report.score, greaterThan(25));
    });
  });
}

