import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/jsonb_size.dart';

void main() {
  test(
    'sizes a value the way PostgreSQL prints jsonb, with spaces after : and ,',
    () {
      expect(
        jsonbTextBytes({
          'a': 1,
          'b': [1, 2],
        }),
        utf8.encode('{"a": 1, "b": [1, 2]}').length,
      );
      expect(jsonbTextBytes([]), 2);
      expect(jsonbTextBytes(<String, Object?>{}), 2);
      expect(jsonbTextBytes(null), 4);
    },
  );

  test('is larger than jsonEncode for the same value, so the check is not optimistic', () {
    final value = [
      {
        'operation_id': 'x',
        'patch': {'title': 'T', 'notes': 'n'},
      },
      {
        'operation_id': 'y',
        'patch': {'title': 'U'},
      },
    ];

    expect(
      jsonbTextBytes(value),
      greaterThan(utf8.encode(jsonEncode(value)).length),
    );
  });

  test('counts UTF-8 bytes, not characters', () {
    expect(jsonbTextBytes('é'), 4); // "é" is two bytes plus two quotes
  });
}
