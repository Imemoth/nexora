import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'window_placement.dart';

/// What the app needs from the native window. Implemented over the existing
/// `nexora/desktop` channel by `WindowsDesktopIntegration`; elsewhere there is
/// no window to manage ([NoWindowBridge]).
abstract interface class WindowBridge {
  /// Work areas of all displays, the primary one first. Empty when unknown.
  Future<List<DisplayArea>> displays();

  /// Asks the native window to open with [placement]. Before the window is shown
  /// this only prepares it (no flash); afterwards it moves the window.
  Future<void> applyPlacement(WindowPlacement placement);

  /// The window's placement after the user moved, resized, maximized or
  /// restored it. Never emitted while minimized.
  Stream<WindowPlacement> get placementChanges;
}

final class NoWindowBridge implements WindowBridge {
  const NoWindowBridge();

  @override
  Future<List<DisplayArea>> displays() async => const [];

  @override
  Future<void> applyPlacement(WindowPlacement placement) async {}

  @override
  Stream<WindowPlacement> get placementChanges =>
      const Stream<WindowPlacement>.empty();
}

/// Where the placement is remembered. It is the per-device `settings.json`
/// beside the local database (the file that already holds the theme), under one
/// `window` key. Nothing here is account data and nothing is synchronized.
abstract interface class WindowPlacementStore {
  WindowPlacement? load();
  void save(WindowPlacement placement);
}

/// [WindowPlacementStore] over the shared `settings.json`. Read-modify-write of
/// one key, written through a temporary file and a rename like the theme.
final class FileWindowPlacementStore implements WindowPlacementStore {
  FileWindowPlacementStore(this._file);

  static const _key = 'window';

  final File _file;

  @override
  WindowPlacement? load() => WindowPlacement.tryFromJson(_read()[_key]);

  @override
  void save(WindowPlacement placement) {
    final settings = _read()..[_key] = placement.toJson();
    if (!_file.parent.existsSync()) {
      _file.parent.createSync(recursive: true);
    }
    final temp = File('${_file.path}.tmp');
    temp.writeAsStringSync(jsonEncode(settings), flush: true);
    temp.renameSync(_file.path);
  }

  Map<String, Object?> _read() {
    try {
      if (!_file.existsSync()) {
        return <String, Object?>{};
      }
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map<String, Object?>
          ? Map<String, Object?>.of(decoded)
          : <String, Object?>{};
    } on FileSystemException {
      return <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }
}

/// Opens the window where the user left it, and remembers where they leave it.
///
/// Call [restore] before the first frame (the native window is still hidden
/// then), and [start] once the app runs. A failure anywhere only means the
/// window opens at its default (maximized); it never stops the app.
final class WindowStateController {
  WindowStateController({
    required this._bridge,
    required this._store,
    this.saveDelay = const Duration(milliseconds: 500),
  });

  final WindowBridge _bridge;
  final WindowPlacementStore _store;
  final Duration saveDelay;

  StreamSubscription<WindowPlacement>? _subscription;
  Timer? _timer;
  WindowPlacement? _pending;

  /// Applies the saved placement, corrected so the window is reachable on the
  /// displays that exist now. With nothing saved (first launch) nothing is
  /// applied and the native window opens maximized.
  Future<void> restore() async {
    try {
      final saved = _store.load();
      if (saved == null) {
        return;
      }
      final displays = await _bridge.displays();
      final resolved = resolveStartupPlacement(saved, displays);
      if (resolved != null) {
        await _bridge.applyPlacement(resolved);
      }
    } on Object {
      // Default placement: maximized, always visible.
    }
  }

  /// Starts remembering placement changes.
  void start() {
    _subscription ??= _bridge.placementChanges.listen((placement) {
      _pending = placement;
      _timer?.cancel();
      _timer = Timer(saveDelay, flush);
    });
  }

  /// Writes the latest placement now (also called when the app closes).
  void flush() {
    _timer?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending == null) {
      return;
    }
    try {
      _store.save(pending);
    } on Object {
      // Not being able to remember the window is not worth interrupting work.
    }
  }

  Future<void> dispose() async {
    flush();
    await _subscription?.cancel();
    _subscription = null;
  }
}
