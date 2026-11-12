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
  bool _busy = false;

  bool get running => _timer != null;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => kick());
  }

  /// Runs a cycle now unless one is already running.
  Future<void> kick() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await run();
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
