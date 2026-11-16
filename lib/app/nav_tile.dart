import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/presentation/focus_ring.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// One selectable row in the sidebar: an icon (views) or a colour dot
/// (projects), a label and a count. 38 px high, radius 8.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    this.icon,
    this.dotColor,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.countColor,
    this.trailing,
  }) : assert(icon != null || dotColor != null);

  final IconData? icon;

  /// A project's colour dot, drawn instead of an icon.
  final Color? dotColor;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Overrides the count colour (Overdue above zero).
  final Color? countColor;

  /// Extra control shown after the count (the selected project's menu).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final labelColor = selected ? c.text1 : c.text2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: FocusRing(
        radius: 8,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: c.surface,
            focusColor: Colors.transparent,
            child: Ink(
              height: 38,
              decoration: BoxDecoration(
                color: selected ? c.surface2 : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? c.borderStrong : Colors.transparent,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    if (icon != null)
                      Icon(icon, size: 18, color: labelColor)
                    else
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: NexoraText.bodyStrong.copyWith(
                          color: labelColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (count >= 0)
                      Text(
                        count.toString(),
                        style: NexoraText.label.copyWith(
                          color: countColor ?? c.textMuted,
                        ),
                      ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
