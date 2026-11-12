import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/details_pane.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

/// Details editor shown over the list between 900 and 1099 px. Closing it goes
/// through [onClose], which uses the same unsaved-change gate as selection.
class DetailsOverlay extends StatelessWidget {
  const DetailsOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: AppStrings.closeDetails,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
          const Divider(height: 1),
          const Expanded(child: DetailsPane()),
        ],
      ),
    );
  }
}
