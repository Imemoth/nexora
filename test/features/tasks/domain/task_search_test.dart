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

  group('notesMatchExcerpt', () {
    test('explains a task found only by its notes', () {
      final task = makeTask(
        id: 't',
        title: 'Groceries',
        notes: 'Remember two litres of milk',
      );
      final x = notesMatchExcerpt(task, 'litres')!;
      expect(x.before, 'Remember two ');
      expect(x.match, 'litres');
      expect(x.after, ' of milk');
      expect(x.leading, isFalse);
      expect(x.trailing, isFalse);
    });

    test('matches case-insensitively and keeps the notes spelling', () {
      final task = makeTask(id: 't', title: 'x', notes: 'Call DENTIST today');
      expect(notesMatchExcerpt(task, 'dentist')!.match, 'DENTIST');
    });

    test('nothing to explain: title match, blank query, empty or no match', () {
      expect(
        notesMatchExcerpt(
          makeTask(id: 't', title: 'Milk run', notes: 'milk'),
          'milk',
        ),
        isNull,
        reason: 'the title already shows why',
      );
      final task = makeTask(id: 't', title: 'A', notes: 'abc');
      expect(notesMatchExcerpt(task, ''), isNull);
      expect(notesMatchExcerpt(task, '   '), isNull);
      expect(
        notesMatchExcerpt(makeTask(id: 't', title: 'A', notes: ''), 'a b'),
        isNull,
      );
      expect(notesMatchExcerpt(task, 'zzz'), isNull);
    });

    test('long notes are cut around the match with ellipses', () {
      final notes = '${'before ' * 20}NEEDLE${' after' * 20}';
      final x = notesMatchExcerpt(
        makeTask(id: 't', title: 'T', notes: notes),
        'needle',
        radius: 12,
      )!;
      expect(x.leading, isTrue);
      expect(x.trailing, isTrue);
      expect(x.match, 'NEEDLE');
      expect(x.text.length, lessThan(12 * 2 + 6 + 3));
      expect(x.text.startsWith('…'), isTrue);
      expect(x.text.endsWith('…'), isTrue);
    });

    test('line breaks and runs of spaces collapse to one space', () {
      final x = notesMatchExcerpt(
        makeTask(id: 't', title: 'T', notes: 'first line\n\n  second   line'),
        'second',
      )!;
      expect(x.before, 'first line ');
      expect(x.after, ' line');
    });

    test('agrees with matchesSearch: shown exactly for notes-only matches', () {
      final tasks = [
        makeTask(id: '1', title: 'Alpha', notes: 'beta gamma'),
        makeTask(id: '2', title: 'beta', notes: 'beta'),
        makeTask(id: '3', title: 'Delta', notes: ''),
      ];
      for (final t in tasks) {
        final notesOnly =
            matchesSearch(t, 'BETA') && !t.title.toLowerCase().contains('beta');
        expect(notesMatchExcerpt(t, 'BETA') != null, notesOnly, reason: t.id);
      }
    });

    test('a notes text with special lower-casing never throws', () {
      final task = makeTask(id: 't', title: 'T', notes: 'İstanbul trip plan');
      final x = notesMatchExcerpt(task, 'trip');
      expect(x, isNotNull);
      expect(x!.text, contains('trip'));
    });
  });
}
