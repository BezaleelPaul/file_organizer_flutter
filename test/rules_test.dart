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
      expect(uniqueName('a.txt', {'A.txt'}, caseInsensitive: true), 'a (1).txt');
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
    final result = normalizeCategories({'Images': ['.PNG', '.jpg'], 'Empty': []});
    expect(result['Images'], ['.png', '.jpg']);
    expect(result.containsKey('Others'), isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}