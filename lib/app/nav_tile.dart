import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// One selectable row in the sidebar: an icon chip, a label, a count and an
/// optional action. Selected rows are shown by a tinted fill, a strong border,
/// bold text and a gradient icon chip, never by colour alone.
class NavTile extends StatelessWidget {
  const NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.progress,
    this.action,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Optional 0 to 1 completion shown as a thin bar under the label.
  final double? progress;

  /// Optional widget after the count, for example a project menu.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fraction = progress;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: selected ? colors.selectedGradient : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.borderStrong : Colors.transparent,
          ),
        ),
        child: ListTile(
          selected: selected,
          dense: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: EdgeInsets.only(
            left: 10,
            right: action == null ? 12 : 4,
          ),
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: selected ? colors.brandGradient : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 20,
              color: selected ? colors.onAccent : colors.text2,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (fraction != null) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: colors.border,
                    color: colors.accentCyan,
                  ),
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: selected ? colors.brandGradient : null,
                  color: selected ? null : colors.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? colors.onAccent : colors.text2,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
