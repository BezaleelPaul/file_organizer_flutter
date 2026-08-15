import 'package:file_organizer/search/query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 8, 15);

  bool matches(SearchQuery q, String name,
      {String path = '/root/',
      String ext = '',
      int size = 0,
      DateTime? modified}) {
    return matchQuery(
      q,
      name: name,
      path: '$path$name',
      ext: ext,
      size: size,
      modified: modified ?? base,
    );
  }

  group('parseQuery', () {
    test('free text becomes a name substring', () {
      final q = parseQuery('report');
      expect(q.terms, ['report']);
      expect(matches(q, 'final_report.pdf'), isTrue);
      expect(matches(q, 'invoice.pdf'), isFalse);
    });

    test('wildcard extension', () {
      final q = parseQuery('*.pdf');
      expect(q.extension, '.pdf');
      expect(matches(q, 'a.pdf', ext: '.pdf'), isTrue);
      expect(matches(q, 'a.txt', ext: '.txt'), isFalse);
    });

    test('ext: prefix', () {
      final q = parseQuery('ext:png');
      expect(q.extension, 'png');
      expect(matches(q, 'a.PNG', ext: '.png'), isTrue);
      expect(matches(q, 'a.jpg', ext: '.jpg'), isFalse);
    });

    test('type:image matches known extensions', () {
      final q = parseQuery('type:image');
      expect(matches(q, 'photo.JPEG', ext: '.jpeg'), isTrue);
      expect(matches(q, 'movie.mp4', ext: '.mp4'), isFalse);
    });

    test('name: prefix', () {
      final q = parseQuery('name:invoice');
      expect(matches(q, 'invoice_2026.pdf'), isTrue);
      expect(matches(q, 'receipt.pdf'), isFalse);
    });

    test('folder: prefix', () {
      final q = parseQuery('folder:Projects');
      expect(
        matchQuery(q, name: 'a.txt', path: '/root/Projects/x/a.txt', ext: '.txt', size: 0, modified: base),
        isTrue,
      );
      expect(
        matchQuery(q, name: 'a.txt', path: '/root/Backup/a.txt', ext: '.txt', size: 0, modified: base),
        isFalse,
      );
    });

    test('size comparisons', () {
      expect(matches(parseQuery('>1MB'), 'a.bin', size: 2 * 1024 * 1024), isTrue);
      expect(matches(parseQuery('>1MB'), 'a.bin', size: 1024), isFalse);
      expect(matches(parseQuery('<1MB'), 'a.bin', size: 500 * 1024), isTrue);
      expect(matches(parseQuery('>=1MB'), 'a.bin', size: 1024 * 1024), isTrue);
      expect(matches(parseQuery('size:>2GB'), 'a.bin', size: 3 * 1024 * 1024 * 1024), isTrue);
      expect(matches(parseQuery('size:>2GB'), 'a.bin', size: 1024 * 1024), isFalse);
    });

    test('modified:last-week', () {
      final q = parseQuery('modified:last-week');
      final now = DateTime.now();
      expect(
        matchQuery(q, name: 'a', path: '/a', ext: '', size: 0, modified: now.subtract(const Duration(days: 2))),
        isTrue,
      );
      expect(
        matchQuery(q, name: 'a', path: '/a', ext: '', size: 0, modified: now.subtract(const Duration(days: 30))),
        isFalse,
      );
    });

    test('modified:year range', () {
      final q = parseQuery('modified:2025');
      expect(
        matchQuery(q, name: 'a', path: '/a', ext: '', size: 0, modified: DateTime(2025, 6, 1)),
        isTrue,
      );
      expect(
        matchQuery(q, name: 'a', path: '/a', ext: '', size: 0, modified: DateTime(2026, 1, 1)),
        isFalse,
      );
    });

    test('after:/before: dates', () {
      final after = parseQuery('after:2026-01-01');
      expect(matches(after, 'a', modified: DateTime(2026, 3, 1)), isTrue);
      expect(matches(after, 'a', modified: DateTime(2025, 12, 31)), isFalse);
      final before = parseQuery('before:2026-01-01');
      expect(matches(before, 'a', modified: DateTime(2025, 6, 1)), isTrue);
      expect(matches(before, 'a', modified: DateTime(2026, 6, 1)), isFalse);
    });

    test('combined query ANDs every clause', () {
      final q = parseQuery('report ext:pdf >500KB');
      expect(matches(q, 'report.pdf', ext: '.pdf', size: 600 * 1024), isTrue);
      expect(matches(q, 'report.txt', ext: '.txt', size: 600 * 1024), isFalse);
      expect(matches(q, 'report.pdf', ext: '.pdf', size: 100 * 1024), isFalse);
    });
  });

  group('sortResults', () {
    test('sorts by name then size descending', () {
      final sorted = sortResults<String>(
        ['b_small', 'a_big', 'a_small'],
        (s) => s,
        (s) => s.length,
      );
      expect(sorted, ['a_big', 'a_small', 'b_small']);
    });
  });
}