/// Conversion of values from a server row (PostgreSQL `jsonb`) to the local
/// representation, shared by the pull applier and the recovery actions.
library;

/// A server timestamp such as `2026-11-12T19:57:16.87415+00:00` as local ISO UTC.
String? normalizeServerTimestamp(Object? value) {
  if (value is! String) {
    return null;
  }
  return DateTime.parse(value).toUtc().toIso8601String();
}

/// The local column value of [field] from a server [row].
Object? serverColumnValue(String field, Map<String, Object?> row) {
  final value = row[field];
  switch (field) {
    case 'notes':
      return value ?? '';
    case 'sort_order':
      return value is num ? value.toInt() : 0;
    case 'completed_at':
    case 'deleted_at':
      return normalizeServerTimestamp(value);
    default:
      return value;
  }
}
