import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// A content digest of the user data tables, used to prove that a migration
/// backup holds exactly the snapshot that is being migrated. It is an integrity
/// check, not a security feature.
///
/// The digest covers every row of `meta`, `projects`, `tasks` and the outbox
/// (`sync_outbox` of schema v1), in a fixed order. The outbox is read in `rowid`
/// order, and the digest depends on that **order** but not on the `rowid` values
/// themselves: SQLite may renumber rowids when it copies a database, so a copy is
/// equal to its source when it holds the same rows in the same order.
String snapshotDigest(Database db) {
  final digest = _Digest();
  const tables = [
    ['meta', 'key'],
    ['projects', 'id'],
    ['tasks', 'id'],
    ['sync_outbox', 'rowid'],
  ];
  for (final entry in tables) {
    final table = entry[0];
    final order = entry[1];
    digest.addText('table:$table');
    final rows = db.select('SELECT * FROM $table ORDER BY $order');
    for (final row in rows) {
      digest.addText('row');
      for (final key in row.keys) {
        final value = row[key];
        digest.addText('$key=${value.runtimeType}:$value');
      }
    }
  }
  return digest.hex();
}

/// Four independent 32-bit FNV-1a lanes (128 bits). Pure Dart; products stay
/// below 2^57, so it is exact on every platform.
final class _Digest {
  final List<int> _lanes = [0x811c9dc5, 0x01000193, 0x9e3779b1, 0x85ebca6b];

  void addText(String text) {
    final bytes = utf8.encode(text);
    _mix(bytes.length & 0xff);
    _mix((bytes.length >> 8) & 0xff);
    _mix((bytes.length >> 16) & 0xff);
    for (final byte in bytes) {
      _mix(byte);
    }
    _mix(0xff);
  }

  void _mix(int byte) {
    for (var i = 0; i < _lanes.length; i++) {
      _lanes[i] = ((_lanes[i] ^ (byte + i)) * 16777619) & 0xffffffff;
    }
  }

  String hex() {
    return _lanes.map((lane) => lane.toRadixString(16).padLeft(8, '0')).join();
  }
}
