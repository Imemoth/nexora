import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// Widths of the two side panels of the three-pane layout, with the limits that
/// keep the existing breakpoints valid.
///
/// The defaults (248 and 380) and the breakpoints (1100 and 900) are unchanged.
/// At 1100 px the defaults already leave the list exactly [centreMin], so no
/// panel can grow there; a wider window gives room to grow. The overlay layout
/// (900 to 1099 px) keeps its fixed 380 px editor: resizing applies to the
/// three-pane layout only.
abstract final class PanelLayout {
  static const double sidebarDefault = 248;
  static const double detailsDefault = 380;
  static const double sidebarMin = 200;
  static const double sidebarMax = 360;

  /// 340 keeps the due date, the time and the project name readable.
  static const double detailsMin = 340;
  static const double detailsMax = 560;

  /// The list never gets narrower than it has at 1100 px with the defaults.
  static const double centreMin = 472;

  /// Clamps [want] for the sidebar given the current [details] width.
  static double sidebar(
    double want, {
    required double total,
    required double details,
  }) {
    final room = total - details - centreMin;
    return want.clamp(
      sidebarMin,
      math.max(sidebarMin, math.min(sidebarMax, room)),
    );
  }

  /// Clamps [want] for the details panel given the current [sidebar] width.
  static double details(
    double want, {
    required double total,
    required double sidebar,
  }) {
    final room = total - sidebar - centreMin;
    return want.clamp(
      detailsMin,
      math.max(detailsMin, math.min(detailsMax, room)),
    );
  }

  /// Both widths for a window of [total] px, shrinking the details panel first
  /// and then the sidebar when the window got smaller than the stored widths.
  static ({double sidebar, double details}) fit(
    double wantSidebar,
    double wantDetails, {
    required double total,
  }) {
    final d = details(wantDetails, total: total, sidebar: wantSidebar);
    final s = sidebar(wantSidebar, total: total, details: d);
    return (sidebar: s, details: details(d, total: total, sidebar: s));
  }
}

/// A thin separator the user can drag or move with the arrow keys.
///
/// It sits on the border between two panes without taking layout space. Focus
/// shows as a 2 px accent line. Left and Right change the width by 16 px
/// (48 px with Shift); Home restores the default; double-click does too.
class PanelResizeHandle extends StatefulWidget {
  const PanelResizeHandle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onReset,
    this.growsLeft = false,
  });

  final String label;

  /// The current width, for assistive technology and the tooltip.
  final double value;

  /// Asks for a new width. The shell clamps it.
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  /// True for the details panel: dragging left makes it wider.
  final bool growsLeft;

  @override
  State<PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<PanelResizeHandle> {
  bool _hover = false;
  bool _dragging = false;
  bool _focused = false;

  void _nudge(double delta) {
    widget.onChanged(widget.value + (widget.growsLeft ? -delta : delta));
  }

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final active = _hover || _dragging || _focused;
    // Left/Right move the edge, so for the details panel (its left edge) Left
    // makes it wider.
    return Semantics(
      label: widget.label,
      value: '${widget.value.round()} px',
      hint: AppStrings.resizeHint,
      slider: true,
      child: Tooltip(
        message: '${widget.label}. ${AppStrings.resizeHint}',
        waitDuration: const Duration(milliseconds: 600),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _nudge(-16),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _nudge(16),
            const SingleActivator(
              LogicalKeyboardKey.arrowLeft,
              shift: true,
            ): () =>
                _nudge(-48),
            const SingleActivator(
              LogicalKeyboardKey.arrowRight,
              shift: true,
            ): () =>
                _nudge(48),
            const SingleActivator(LogicalKeyboardKey.home): widget.onReset,
          },
          child: Focus(
            debugLabel: widget.label,
            onFocusChange: (value) => setState(() => _focused = value),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                onHorizontalDragUpdate: (DragUpdateDetails d) =>
                    _nudge(d.delta.dx),
                onDoubleTap: widget.onReset,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: active ? 3 : 1,
                    decoration: BoxDecoration(
                      color: _focused
                          ? c.accentCyan
                          : (active ? c.accentBlue : Colors.transparent),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
