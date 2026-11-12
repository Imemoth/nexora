import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('produces RFC 4122 version 4 identifiers', () {
    final id = RandomIdGenerator().nextId();

    expect(id, hasLength(36));
    expect(_uuidV4.hasMatch(id), isTrue, reason: id);
  });

  test('produces unique identifiers', () {
    final generator = RandomIdGenerator();
    final ids = {for (var i = 0; i < 1000; i++) generator.nextId()};

    expect(ids, hasLength(1000));
  });

  test('is reproducible with a seeded random source', () {
    final a = RandomIdGenerator(random: Random(42)).nextId();
    final b = RandomIdGenerator(random: Random(42)).nextId();

    expect(a, b);
  });
}
