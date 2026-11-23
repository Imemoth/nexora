import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/platform/desktop_integration.dart';
import 'package:nexora/platform/window_placement.dart';
import 'package:nexora/platform/window_state.dart';

/// The rule that decides where the window opens, the persistence in the shared
/// per-device settings file, and the controller. (The Win32 side only reads and
/// applies the numbers; it is built and checked on Windows.)
const _primary = DisplayArea(0, 0, 1920, 1040); // 1920x1080 minus the taskbar
const _second = DisplayArea(1920, 0, 3840, 1040); // to the right
const _left = DisplayArea(-1280, 100, 0, 1024); // to the left, offset

WindowPlacement _p(int l, int t, int w, int h, {bool maximized = false}) =>
    WindowPlacement(WindowRect(l, t, w, h), maximized: maximized);

void main() {
  group('first launch and damaged data', () {
    test(
      'nothing saved: no placement, so the native window opens maximized',
      () {
        expect(resolveStartupPlacement(null, [_primary]), isNull);
      },
    );

    test('no display information: the default stays', () {
      expect(
        resolveStartupPlacement(_p(100, 100, 1000, 700), const []),
        isNull,
      );
    });

    test('damaged stored data is read as nothing saved', () {
      for (final bad in <Object?>[
        null,
        'x',
        42,
        <String, Object?>{},
        {'left': 1, 'top': 1, 'width': 1000, 'height': 700}, // no flag
        {
          'left': 1.5,
          'top': 1,
          'width': 1000,
          'height': 700,
          'maximized': false,
        },
        {'left': 1, 'top': 1, 'width': 10, 'height': 700, 'maximized': false},
        {'left': 1, 'top': 1, 'width': 1000, 'height': 5, 'maximized': true},
        {'left': 1, 'top': 1, 'width': 1000, 'height': 700, 'maximized': 'yes'},
        {
          'left': 1 << 40,
          'top': 1,
          'width': 1000,
          'height': 700,
          'maximized': true,
        },
      ]) {
        expect(WindowPlacement.tryFromJson(bad), isNull, reason: '$bad');
      }
    });

    test('a valid placement survives JSON', () {
      final saved = _p(-30, 12, 1100, 760, maximized: true);
      expect(WindowPlacement.tryFromJson(saved.toJson()), saved);
    });
  });

  group('restoring a normal, maximized and restored window', () {
    test('a normal window on the primary display opens exactly there', () {
      final saved = _p(200, 120, 1280, 800);
      expect(resolveStartupPlacement(saved, [_primary]), saved);
    });

    test('a maximized window keeps its restored bounds and the flag', () {
      final saved = _p(200, 120, 1280, 800, maximized: true);
      final resolved = resolveStartupPlacement(saved, [_primary])!;
      expect(resolved.maximized, isTrue);
      expect(resolved.rect, saved.rect); // Restore lands where it did
    });

    test('a window on the second display opens there while it exists', () {
      final saved = _p(2100, 80, 1200, 800);
      expect(resolveStartupPlacement(saved, [_primary, _second]), saved);
    });

    test('a window left of the primary (negative coordinates) is valid', () {
      final saved = _p(-1200, 200, 1000, 700);
      expect(resolveStartupPlacement(saved, [_primary, _left]), saved);
    });

    test('a window spanning two displays stays spanning', () {
      final saved = _p(1500, 100, 1000, 700);
      expect(resolveStartupPlacement(saved, [_primary, _second]), saved);
    });
  });

  group('monitor removal and layout changes keep the window reachable', () {
    test('the second display was unplugged: onto the primary, centred', () {
      final saved = _p(2100, 80, 1200, 800, maximized: false);
      final resolved = resolveStartupPlacement(saved, [_primary])!;
      expect(resolved.rect, const WindowRect(360, 120, 1200, 800));
      expect(resolved.maximized, isFalse);
    });

    test('the maximized flag is kept when the window had to move', () {
      final saved = _p(2100, 80, 1200, 800, maximized: true);
      expect(resolveStartupPlacement(saved, [_primary])!.maximized, isTrue);
    });

    test('a window entirely below the bottom edge is brought back', () {
      final saved = _p(100, 3000, 1000, 700);
      final resolved = resolveStartupPlacement(saved, [_primary])!;
      expect(resolved.rect.top, inInclusiveRange(0, 1040 - 700));
      expect(resolved.rect.left, inInclusiveRange(0, 1920 - 1000));
    });

    test('only a sliver of title bar visible is not reachable', () {
      // 40 px of the window's width on screen: too little to grab.
      final saved = _p(1880, 100, 1000, 700);
      final resolved = resolveStartupPlacement(saved, [_primary])!;
      expect(resolved.rect.left + resolved.rect.width, lessThanOrEqualTo(1920));
      expect(resolved.rect.left, greaterThanOrEqualTo(0));
    });

    test('a title bar above the top of the display is not reachable', () {
      final saved = _p(100, -400, 1000, 700);
      final resolved = resolveStartupPlacement(saved, [_primary])!;
      expect(resolved.rect.top, greaterThanOrEqualTo(0));
    });

    test('a resolution drop shrinks an oversized window to the display', () {
      const small = DisplayArea(0, 0, 1280, 680); // 1280x720 minus the taskbar
      final saved = _p(100, 50, 1700, 950);
      final resolved = resolveStartupPlacement(saved, [small])!;
      expect(resolved.rect.width, lessThanOrEqualTo(1280));
      expect(resolved.rect.height, lessThanOrEqualTo(680));
      expect(resolved.rect.left, greaterThanOrEqualTo(0));
      expect(resolved.rect.top, greaterThanOrEqualTo(0));
      expect(resolved.rect.right, lessThanOrEqualTo(1280));
      expect(resolved.rect.bottom, lessThanOrEqualTo(680));
    });

    test(
      'the display with most overlap is chosen when none shows the title',
      () {
        final saved = _p(
          3000,
          900,
          1500,
          600,
        ); // mostly past the second display
        final resolved = resolveStartupPlacement(saved, [_primary, _second])!;
        // The title bar (y 900..932) is on the second display: kept as is.
        expect(resolved, saved);
      },
    );

    test(
      'a different display layout (second display now left): onto the best one',
      () {
        final saved = _p(2100, 80, 1200, 800); // was right of the primary
        final resolved = resolveStartupPlacement(saved, [_primary, _left])!;
        expect(resolved.rect.left, greaterThanOrEqualTo(0));
        expect(resolved.rect.right, lessThanOrEqualTo(1920));
      },
    );
  });

  group('persistence in the shared per-device settings file', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('nexora-window-');
      file = File('${dir.path}${Platform.pathSeparator}settings.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('save and load round-trip', () {
      final store = FileWindowPlacementStore(file);
      expect(store.load(), isNull);
      store.save(_p(10, 20, 1000, 700, maximized: true));
      expect(store.load(), _p(10, 20, 1000, 700, maximized: true));
    });

    test('it shares the file with the theme and never drops it', () {
      file.writeAsStringSync(jsonEncode({'theme_preference': 'dark'}));
      FileWindowPlacementStore(file).save(_p(1, 2, 900, 600));
      final json = jsonDecode(file.readAsStringSync()) as Map;
      expect(json['theme_preference'], 'dark');
      expect(json['window'], isA<Map>());
    });

    test('a damaged file loads as nothing and is replaced on save', () {
      file.writeAsStringSync('{not json');
      final store = FileWindowPlacementStore(file);
      expect(store.load(), isNull);
      store.save(_p(1, 2, 900, 600));
      expect(store.load(), _p(1, 2, 900, 600));
    });
  });

  group('WindowStateController', () {
    test('restore applies the corrected placement', () async {
      final bridge = _FakeBridge([_primary]);
      final store = _MemoryStore(_p(2100, 80, 1200, 800));
      await WindowStateController(bridge: bridge, store: store).restore();
      expect(bridge.applied, [_p(360, 120, 1200, 800)]);
    });

    test('first launch applies nothing', () async {
      final bridge = _FakeBridge([_primary]);
      await WindowStateController(
        bridge: bridge,
        store: _MemoryStore(null),
      ).restore();
      expect(bridge.applied, isEmpty);
    });

    test('a failing bridge leaves the default and does not throw', () async {
      final bridge = _FakeBridge([_primary])..fail = true;
      await WindowStateController(
        bridge: bridge,
        store: _MemoryStore(_p(100, 100, 1000, 700)),
      ).restore();
      expect(bridge.applied, isEmpty);
    });

    test('changes are saved after the delay, only the latest', () async {
      final bridge = _FakeBridge([_primary]);
      final store = _MemoryStore(null);
      final controller = WindowStateController(
        bridge: bridge,
        store: store,
        saveDelay: const Duration(milliseconds: 20),
      )..start();
      bridge.emit(_p(1, 1, 900, 600));
      bridge.emit(_p(5, 5, 1000, 700, maximized: true));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(store.saved, [_p(5, 5, 1000, 700, maximized: true)]);
      await controller.dispose();
    });

    test('flush and dispose write a pending change at once', () async {
      final bridge = _FakeBridge([_primary]);
      final store = _MemoryStore(null);
      final controller = WindowStateController(
        bridge: bridge,
        store: store,
        saveDelay: const Duration(hours: 1),
      )..start();
      bridge.emit(_p(1, 1, 900, 600));
      await Future<void>.delayed(Duration.zero);
      await controller.dispose();
      expect(store.saved, [_p(1, 1, 900, 600)]);
    });

    test('a store that cannot write never interrupts the app', () async {
      final bridge = _FakeBridge([_primary]);
      final store = _MemoryStore(null)..fail = true;
      final controller = WindowStateController(
        bridge: bridge,
        store: store,
        saveDelay: Duration.zero,
      )..start();
      bridge.emit(_p(1, 1, 900, 600));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.dispose();
      expect(store.saved, isEmpty);
    });
  });

  group('the channel (existing nexora/desktop)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(WindowsDesktopIntegration.channelName);
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'displays are read from getDisplays, malformed entries skipped',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'getDisplays');
              return [
                {'left': 0, 'top': 0, 'right': 1920, 'bottom': 1040},
                {'left': 'x'},
              ];
            });
        final bridge = WindowsDesktopIntegration();
        final displays = await bridge.displays();
        expect(displays, hasLength(1));
        expect(displays.single.right, 1920);
        await bridge.dispose();
      },
    );

    test('applyPlacement sends the numbers and the flag', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            seen = call;
            return true;
          });
      final bridge = WindowsDesktopIntegration();
      await bridge.applyPlacement(_p(1, 2, 1000, 700, maximized: true));
      expect(seen!.method, 'setWindowPlacement');
      expect(seen!.arguments, {
        'left': 1,
        'top': 2,
        'width': 1000,
        'height': 700,
        'maximized': true,
      });
      await bridge.dispose();
    });

    test('an older runner without the methods leaves the default', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final bridge = WindowsDesktopIntegration();
      expect(await bridge.displays(), isEmpty);
      await bridge.applyPlacement(_p(1, 2, 1000, 700)); // no throw
      await bridge.dispose();
    });

    test('windowPlacementChanged from native reaches the stream', () async {
      final bridge = WindowsDesktopIntegration();
      final first = bridge.placementChanges.first;
      final data = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('windowPlacementChanged', {
          'left': 5,
          'top': 6,
          'width': 1000,
          'height': 700,
          'maximized': false,
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            WindowsDesktopIntegration.channelName,
            data,
            (_) {},
          );
      expect(await first, _p(5, 6, 1000, 700));
      await bridge.dispose();
    });
  });
}

final class _FakeBridge implements WindowBridge {
  _FakeBridge(this._displays);

  final List<DisplayArea> _displays;
  final List<WindowPlacement> applied = [];
  final StreamController<WindowPlacement> _changes =
      StreamController<WindowPlacement>.broadcast();
  bool fail = false;

  void emit(WindowPlacement p) => _changes.add(p);

  @override
  Future<List<DisplayArea>> displays() async {
    if (fail) {
      throw StateError('no native window');
    }
    return _displays;
  }

  @override
  Future<void> applyPlacement(WindowPlacement placement) async =>
      applied.add(placement);

  @override
  Stream<WindowPlacement> get placementChanges => _changes.stream;
}

final class _MemoryStore implements WindowPlacementStore {
  _MemoryStore(this._initial);

  final WindowPlacement? _initial;
  final List<WindowPlacement> saved = [];
  bool fail = false;

  @override
  WindowPlacement? load() => _initial;

  @override
  void save(WindowPlacement placement) {
    if (fail) {
      throw const FileSystemException('read only');
    }
    saved.add(placement);
  }
}
