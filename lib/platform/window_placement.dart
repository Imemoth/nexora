/// Where the main window was and how it was, and the rule that decides where it
/// opens next time. Pure Dart: the Windows side only reads and applies numbers.
///
/// All coordinates are physical pixels in the virtual screen (the same space the
/// native `GetWindowRect` and `GetMonitorInfo` use).
library;

import 'dart:math' as math;

/// The smallest window a saved placement may describe. Anything smaller is
/// treated as damaged data.
const int minWindowWidth = 480;
const int minWindowHeight = 320;

/// How much of the title bar must be on a display for the window to count as
/// reachable (enough to see it and drag it).
const int _reachableWidth = 120;
const int _titleBarHeight = 32;

final class WindowRect {
  const WindowRect(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is WindowRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'WindowRect($left, $top, $width x $height)';
}

/// A saved window: its restored (normal) bounds and whether it was maximized.
/// The bounds are kept even while maximized, so Restore lands where it did.
final class WindowPlacement {
  const WindowPlacement(this.rect, {required this.maximized});

  /// Parses stored JSON. Returns null for anything that is not a complete,
  /// plausible placement, so a damaged file means "first launch", never a crash.
  static WindowPlacement? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final left = json['left'];
    final top = json['top'];
    final width = json['width'];
    final height = json['height'];
    final maximized = json['maximized'];
    if (left is! int ||
        top is! int ||
        width is! int ||
        height is! int ||
        maximized is! bool) {
      return null;
    }
    if (width < minWindowWidth ||
        height < minWindowHeight ||
        width > 100000 ||
        height > 100000 ||
        left.abs() > 1000000 ||
        top.abs() > 1000000) {
      return null;
    }
    return WindowPlacement(
      WindowRect(left, top, width, height),
      maximized: maximized,
    );
  }

  final WindowRect rect;
  final bool maximized;

  Map<String, Object?> toJson() => {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'maximized': maximized,
  };

  @override
  bool operator ==(Object other) =>
      other is WindowPlacement &&
      other.rect == rect &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(rect, maximized);

  @override
  String toString() => 'WindowPlacement($rect, maximized: $maximized)';
}

/// The usable area (work area: without the taskbar) of one display.
final class DisplayArea {
  const DisplayArea(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
}

/// Decides where the window opens.
///
/// * No saved placement (first launch) or no display information: null. The
///   native side then opens the window maximized with the normal title bar.
/// * A saved placement whose title bar is still reachable on some display opens
///   exactly there (a window spanning two displays stays spanning).
/// * Otherwise (a display was removed, or the layout or resolution changed so the
///   window would be off screen) it moves onto the display it overlaps most, or
///   the primary one, no larger than that display's work area. The maximized
///   flag is kept.
///
/// [displays] lists the primary display first.
WindowPlacement? resolveStartupPlacement(
  WindowPlacement? saved,
  List<DisplayArea> displays,
) {
  if (saved == null || displays.isEmpty) {
    return null;
  }
  final rect = saved.rect;
  if (_titleBarReachable(rect, displays) && _fitsSomeDisplay(rect, displays)) {
    return saved;
  }
  final target = _bestDisplay(rect, displays);
  final width = math.min(rect.width, target.width);
  final height = math.min(rect.height, target.height);
  final unreachable = !_titleBarReachable(rect, displays);
  // Unreachable windows are centred on the target. Windows that merely became
  // too large keep their position as far as it fits.
  final left = unreachable
      ? target.left + (target.width - width) ~/ 2
      : rect.left.clamp(target.left, target.right - width).toInt();
  final top = unreachable
      ? target.top + (target.height - height) ~/ 2
      : rect.top.clamp(target.top, target.bottom - height).toInt();
  return WindowPlacement(
    WindowRect(left, top, width, height),
    maximized: saved.maximized,
  );
}

bool _titleBarReachable(WindowRect rect, List<DisplayArea> displays) {
  final strip = WindowRect(rect.left, rect.top, rect.width, _titleBarHeight);
  for (final display in displays) {
    final w =
        math.min(strip.right, display.right) -
        math.max(strip.left, display.left);
    final h =
        math.min(strip.bottom, display.bottom) -
        math.max(strip.top, display.top);
    if (w >= _reachableWidth && h >= _titleBarHeight ~/ 2) {
      return true;
    }
  }
  return false;
}

/// A window larger than every display (after a resolution drop) is not left as
/// it is, even when its title bar is visible: its controls could be off screen.
bool _fitsSomeDisplay(WindowRect rect, List<DisplayArea> displays) {
  // A window may legitimately span displays, so compare with the bounding box.
  final left = displays.map((d) => d.left).reduce(math.min);
  final top = displays.map((d) => d.top).reduce(math.min);
  final right = displays.map((d) => d.right).reduce(math.max);
  final bottom = displays.map((d) => d.bottom).reduce(math.max);
  return rect.width <= right - left && rect.height <= bottom - top;
}

DisplayArea _bestDisplay(WindowRect rect, List<DisplayArea> displays) {
  var best = displays.first; // the primary display
  var bestArea = 0;
  for (final display in displays) {
    final int w =
        (math.min(rect.right, display.right) -
                math.max(rect.left, display.left))
            .toInt();
    final int h =
        (math.min(rect.bottom, display.bottom) -
                math.max(rect.top, display.top))
            .toInt();
    if (w > 0 && h > 0 && w * h > bestArea) {
      bestArea = w * h;
      best = display;
    }
  }
  return best;
}
