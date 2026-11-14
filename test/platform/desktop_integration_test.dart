import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/platform/desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WindowsDesktopIntegration.channelName);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  Future<void> sendFromNative(String method, [Object? args]) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, args),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          WindowsDesktopIntegration.channelName,
          data,
          (_) {},
        );
  }

  test(
    'show sends the task, title and body and reports the native result',
    () async {
      mock((call) async => true);
      final desktop = WindowsDesktopIntegration();
      addTearDown(desktop.dispose);
      final shown = await desktop.show(
        taskId: 't1',
        title: 'Nexora reminder',
        body: 'Pay rent',
      );
      expect(shown, isTrue);
      expect(calls.single.method, 'showNotification');
      expect(calls.single.arguments, {
        'taskId': 't1',
        'title': 'Nexora reminder',
        'body': 'Pay rent',
      });
    },
  );

  test('a summary notification carries no task id', () async {
    mock((call) async => true);
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    await desktop.show(taskId: null, title: 'T', body: 'B');
    expect((calls.single.arguments as Map)['taskId'], '');
  });

  test('native "not shown" is reported as false', () async {
    mock((call) async => false);
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    expect(await desktop.show(taskId: 't', title: 'T', body: 'B'), isFalse);
  });

  test(
    'without the native runner the fallback applies and nothing throws',
    () async {
      // No handler registered: MissingPluginException.
      final desktop = WindowsDesktopIntegration();
      addTearDown(desktop.dispose);
      expect(await desktop.show(taskId: 't', title: 'T', body: 'B'), isFalse);
      expect(desktop.available, isFalse);
      await desktop.ready(); // must not throw
    },
  );

  test('a platform error is a false result, not an exception', () async {
    mock((call) async => throw PlatformException(code: 'x'));
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    expect(await desktop.show(taskId: 't', title: 'T', body: 'B'), isFalse);
  });

  test('a notification click becomes an event with the task id', () async {
    mock((call) async => null);
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    final events = <DesktopEvent>[];
    final sub = desktop.events.listen(events.add);
    addTearDown(sub.cancel);

    await sendFromNative('notificationClicked', {'taskId': 'abc'});
    await sendFromNative('notificationClicked', {'taskId': ''});
    await pumpEventQueue();

    expect(events, hasLength(2));
    expect((events[0] as NotificationClicked).taskId, 'abc');
    expect((events[1] as NotificationClicked).taskId, isNull);
  });

  test('tray Exit and window activation become events', () async {
    mock((call) async => null);
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    final events = <DesktopEvent>[];
    final sub = desktop.events.listen(events.add);
    addTearDown(sub.cancel);
    await sendFromNative('exitRequested');
    await sendFromNative('windowActivated');
    await pumpEventQueue();
    expect(events[0], isA<ExitRequested>());
    expect(events[1], isA<WindowActivated>());
  });

  test('ready and quit reach the native side', () async {
    mock((call) async => null);
    final desktop = WindowsDesktopIntegration();
    addTearDown(desktop.dispose);
    await desktop.ready();
    await desktop.quit();
    expect(calls.map((c) => c.method), ['ready', 'quit']);
  });

  test('the no-op integration reports not shown and never emits', () async {
    const none = NoDesktopIntegration();
    expect(none.available, isFalse);
    expect(await none.show(taskId: 't', title: 'T', body: 'B'), isFalse);
    expect(await none.events.isEmpty, isTrue);
  });
}
