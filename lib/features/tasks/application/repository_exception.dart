/// Thrown by a [TaskRepository] when a load or save cannot complete.
final class RepositoryException implements Exception {
  const RepositoryException(this.message);

  /// Diagnostic text for developers. Never shown to users verbatim.
  final String message;

  @override
  String toString() => 'RepositoryException: $message';
}
