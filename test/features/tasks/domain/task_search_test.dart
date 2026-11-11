import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_search.dart';

import '../../../support/task_fixtures.dart';

void main() {
  group('matchesSearch', () {
    test('matches title case-insensitively', () {
      final task = makeTask(id: 't', title: 'Buy Milk');

      expect(matchesSearch(task, 'MILK'), isTrue);
    });

    test('matches notes', () {
      final task = makeTask(id: 't', title: 'Groceries', notes: 'two litres');

      expect(matchesSearch(task, 'litres'), isTrue);
    });

    test('empty and whitespace-only queries match everything', () {
      final task = makeTask(id: 't', title: 'Anything');

      expect(matchesSearch(task, ''), isTrue);
      expect(matchesSearch(task, '   '), isTrue);
    });

    test('a query matching neither title nor notes does not match', () {
      final task = makeTask(id: 't', title: 'Pay rent', notes: 'bank');

      expect(matchesSearch(task, 'dentist'), isFalse);
    });

    test('surrounding whitespace in the query is ignored', () {
      final task = makeTask(id: 't', title: 'Pay rent');

      expect(matchesSearch(task, '  rent  '), isTrue);
    });
  });
}
