import 'package:nexora/core/result.dart';

T okValue<T, E>(Result<T, E> result) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw StateError('expected Ok, got Err($error)'),
  };
}

E errValue<T, E>(Result<T, E> result) {
  return switch (result) {
    Ok(:final value) => throw StateError('expected Err, got Ok($value)'),
    Err(:final error) => error,
  };
}
