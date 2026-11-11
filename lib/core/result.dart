/// Explicit success-or-error value for rules and validation.
///
/// Expected failures are returned, not thrown, so pure rules can be tested
/// without try/catch.
sealed class Result<T, E> {
  const Result();
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  final T value;
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  final E error;
}
