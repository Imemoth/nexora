import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';

/// Something the Windows shell asked the app to do.
sealed class DesktopEvent {
  const DesktopEvent();
}

/// The user clicked a Nexora notification. [taskId] is null for a summary
/// notification or when the notification does not belong to one task.
final class NotificationClicked extends DesktopEvent {
  const NotificationClicked(this.taskId);

  final String? taskId;
}

/// The user chose Exit in the tray menu (or the shell asked the app to quit).
/// The app should save what it must and then call [DesktopIntegration.quit].
final class ExitRequested extends DesktopEvent {
  const ExitRequested();
}

/// The main window was restored from the tray (informational).
final class WindowActivated extends DesktopEvent {
  const WindowActivated();
}

/// The Windows shell features: tray icon, native notifications, window restore.
///
/// This is the only place that talks to the native runner (channel
/// `nexora/desktop`, see `windows/runner/desktop_integration.cpp`). Everything
/// else depends on this interface, so tests and non-Windows runs use a fake or
/// [NoDesktopIntegration].
abstract interface class DesktopIntegration implements ReminderNotifier {
  /// Whether native notifications and the tray are active in this process.
  bool get available;

  Stream<DesktopEvent> get events;

  /// Tells the native side that the app can now receive events (clicks that
  /// arrived during start-up are delivered then).
  Future<void> ready();

  /// Ends the process (tray icon removed, window destroyed).
  Future<void> quit();

  Future<void> dispose();
}

/// Used when the native shell features do not exist (other platforms, tests,
/// `flutter run` on a runner without them): notifications report "not shown",
/// so the in-app reminder list is the only channel.
final class NoDesktopIntegration implements DesktopIntegration {
  const NoDesktopIntegration();

  @override
  bool get available => false;

  @override
  Stream<DesktopEvent> get events => const Stream<DesktopEvent>.empty();

  @override
  Future<void> ready() async {}

  @override
  Future<void> quit() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  }) async => false;
}

/// The real implementation over the `nexora/desktop` method channel.
final class WindowsDesktopIntegration implements DesktopIntegration {
  WindowsDesktopIntegration({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'nexora/desktop';

  /// The integration for this process: native on Windows, none elsewhere.
  static DesktopIntegration forPlatform() => Platform.isWindows
      ? WindowsDesktopIntegration()
      : const NoDesktopIntegration();

  final MethodChannel _channel;
  final StreamController<DesktopEvent> _events =
      StreamController<DesktopEvent>.broadcast();
  bool _available = true;

  @override
  bool get available => _available;

  @override
  Stream<DesktopEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'notificationClicked':
        final args = call.arguments;
        final taskId = args is Map ? args['taskId'] as String? : null;
        _events.add(
          NotificationClicked(taskId == null || taskId.isEmpty ? null : taskId),
        );
      case 'exitRequested':
        _events.add(const ExitRequested());
      case 'windowActivated':
        _events.add(const WindowActivated());
    }
    return null;
  }

  @override
  Future<void> ready() async {
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
  }

  @override
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  }) async {
    try {
      final shown = await _channel.invokeMethod<bool>('showNotification', {
        'taskId': taskId ?? '',
        'title': title,
        'body': body,
      });
      return shown ?? false;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> quit() async {
    try {
      await _channel.invokeMethod<void>('quit');
    } on MissingPluginException {
      exit(0);
    } on PlatformException {
      exit(0);
    }
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
