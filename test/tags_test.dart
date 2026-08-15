import 'package:file_organizer/core/models.dart';
import 'package:file_organizer/search/query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tag: query', () {
    bool matchesWithTags(String query, Set<String> tags) {
      final parsed = parseQuery(query);
      return matchQuery(
        parsed,
        name: 'report.pdf',
        path: '/root/report.pdf',
        ext: '.pdf',
        size: 100,
        modified: DateTime(2026, 1, 1),
        tags: tags,
      );
    }

    test('matches files carrying the tag', () {
      expect(matchesWithTags('tag:work', {'work', 'taxes'}), isTrue);
      expect(matchesWithTags('tag:work', {'taxes'}), isFalse);
      expect(matchesWithTags('tag:work', {}), isFalse);
    });

    test('multiple tags must all be present', () {
      expect(matchesWithTags('tag:work tag:urgent', {'work', 'urgent'}), isTrue);
      expect(matchesWithTags('tag:work tag:urgent', {'work'}), isFalse);
    });

    test('combined with other clauses', () {
      final parsed = parseQuery('*.pdf tag:taxes');
      expect(
        matchQuery(parsed, name: 'w2.pdf', path: '/w2.pdf', ext: '.pdf', size: 1, modified: DateTime(2026, 1, 1), tags: {'taxes'}),
        isTrue,
      );
      expect(
        matchQuery(parsed, name: 'w2.pdf', path: '/w2.pdf', ext: '.pdf', size: 1, modified: DateTime(2026, 1, 1), tags: {'work'}),
        isFalse,
      );
    });
  });

  group('Tag JSON', () {
    test('round-trips', () {
      final tag = Tag(name: 'Work', color: 3);
      final restored = Tag.fromJson(tag.toJson());
      expect(restored.name, 'Work');
      expect(restored.color, 3);
    });
  });

  group('SmartCollection JSON', () {
    test('round-trips', () {
      final collection = SmartCollection(name: 'Invoices', query: '*.pdf tag:taxes');
      final restored = SmartCollection.fromJson(collection.toJson());
      expect(restored.name, 'Invoices');
      expect(restored.query, '*.pdf tag:taxes');
    });
  });
}