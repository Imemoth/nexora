import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/details_pane.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// Details editor shown over the list between 900 and 1099 px: 380 wide, with
/// the overlay shadow, and a Close button in the save bar. Closing goes through
/// [onClose], which uses the same unsaved-change gate as selection.
class DetailsOverlay extends StatelessWidget {
  const DetailsOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(left: BorderSide(color: c.border)),
        boxShadow: c.overlayShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: DetailsPane(onClose: onClose),
      ),
    );
  }
}
