import 'dart:convert';

/// The UTF-8 size of [value] as PostgreSQL prints a `jsonb` value (`p_ops::text`):
/// a colon and a comma are each followed by one space. `jsonEncode` writes
/// neither, so its length understates what the server measures against its
/// 1,048,576-byte call limit (`NX004`). Used for exact envelope checks.
int jsonbTextBytes(Object? value) {
  return utf8.encode(_jsonbText(value)).length;
}

String _jsonbText(Object? value) {
  if (value is Map) {
    final parts = <String>[];
    for (final entry in value.entries) {
      parts.add(
        '${jsonEncode(entry.key.toString())}: ${_jsonbText(entry.value)}',
      );
    }
    return '{${parts.join(', ')}}';
  }
  if (value is List) {
    return '[${value.map(_jsonbText).join(', ')}]';
  }
  return jsonEncode(value);
}
