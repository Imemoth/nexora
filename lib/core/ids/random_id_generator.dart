import 'dart:math';

import 'id_generator.dart';

/// Random RFC 4122 version 4 identifiers.
final class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String nextId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final part1 = hex.substring(0, 8);
    final part2 = hex.substring(8, 12);
    final part3 = hex.substring(12, 16);
    final part4 = hex.substring(16, 20);
    final part5 = hex.substring(20, 32);
    return '$part1-$part2-$part3-$part4-$part5';
  }
}
