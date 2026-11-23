import 'package:flutter/material.dart';

import 'theme/nexora_colors.dart';

/// Draws a 2 px focus ring (accent cyan, the same ring the buttons and fields
/// use) around [child] while the child, or anything inside it, has keyboard
/// focus. Like Material's own focus highlight it shows for keyboard navigation,
/// not after a mouse click.
///
/// The ring is painted over the child, inside its bounds, so it never changes
/// the layout. Wrap an `InkWell` with it where the wash of `focusColor` alone is
/// too faint to see in both themes.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final show =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: show
              ? Border.all(color: NexoraColors.of(context).accentCyan, width: 2)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
