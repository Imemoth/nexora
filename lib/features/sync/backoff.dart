import 'dart:math';

/// Exponential backoff with jitter: `initial * factor^attempt`, capped at [max],
/// then spread by +/- [jitter] so devices do not retry in lockstep. [attempt]
/// counts from 0. Deterministic when given a seeded [Random].
final class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 2),
    this.factor = 2.0,
    this.max = const Duration(minutes: 5),
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration initial;
  final double factor;
  final Duration max;

  /// Fraction of the delay that may be added or removed, 0 to 1.
  final double jitter;
  final Random _random;

  Duration delay(int attempt) {
    final exponent = attempt < 0 ? 0 : (attempt > 30 ? 30 : attempt);
    final base = initial.inMilliseconds * pow(factor, exponent);
    final capped = base > max.inMilliseconds
        ? max.inMilliseconds.toDouble()
        : base.toDouble();
    final spread = capped * jitter * (2 * _random.nextDouble() - 1);
    final value = (capped + spread).round();
    final bounded = value > max.inMilliseconds ? max.inMilliseconds : value;
    return Duration(milliseconds: bounded < 0 ? 0 : bounded);
  }
}
