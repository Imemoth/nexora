import 'dart:async';

/// Runs a sync callback every [interval] and on demand. It exists only while
/// synchronization is enabled and an account is signed in: with the flag off, or
/// signed out, no scheduler is created, so there are no timers and no traffic.
final class SyncScheduler {
  SyncScheduler({
    required this.run,
    this.interval = const Duration(seconds: 60),
  });

  final Future<void> Function() run;
  final Duration interval;
  Timer? _timer;
  Future<void>? _inflight;

  bool get running => _timer != null;

  void start() {
    _timer ??= Timer.periodic(
      interval,
      (_) => unawaited(kick().then<void>((_) {}, onError: (Object _) {})),
    );
  }

  /// Runs a cycle now, or joins the one that is already running.
  Future<void> kick() {
    final running = _inflight;
    if (running != null) {
      return running;
    }
    final future = run().whenComplete(() => _inflight = null);
    _inflight = future;
    return future;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
