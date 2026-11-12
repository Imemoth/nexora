import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

import 'nav_tile.dart';

/// Sidebar entry for a predefined smart view (Today, Next 7 Days, ...).
class SmartViewTile extends StatelessWidget {
  const SmartViewTile({
    super.key,
    required this.view,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final SmartView view;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NavTile(
      icon: _iconFor(view),
      label: AppStrings.smartViewLabel(view),
      count: count,
      selected: selected,
      onTap: onTap,
    );
  }

  IconData _iconFor(SmartView view) {
    return switch (view) {
      SmartView.today => Icons.today_outlined,
      SmartView.next7Days => Icons.date_range_outlined,
      SmartView.overdue => Icons.warning_amber_outlined,
      SmartView.all => Icons.inbox_outlined,
    };
  }
}
