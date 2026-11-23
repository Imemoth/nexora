import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';

import 'theme/nexora_colors.dart';

/// A shortcut hint such as "Ctrl S". Decoration only: the shortcut itself is
/// bound by the keymap, so the hint carries no semantics of its own.
class Keycap extends StatelessWidget {
  const Keycap(this.text, {super.key, this.color, this.onFill = false});

  final String text;

  /// Overrides the text colour.
  final Color? color;

  /// True on a filled button, where the hint uses the button's own text colour.
  final bool onFill;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final tone = color ?? (onFill ? c.onAccent : c.textMuted);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: tone.withValues(alpha: 0.55)),
        ),
        child: Text(text, style: NexoraText.keycap.copyWith(color: tone)),
      ),
    );
  }
}
