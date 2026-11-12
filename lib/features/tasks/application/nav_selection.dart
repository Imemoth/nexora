import 'package:nexora/features/tasks/domain/smart_view.dart';

/// What the left navigation has selected.
sealed class NavSelection {
  const NavSelection();
}

final class SmartViewSelection extends NavSelection {
  const SmartViewSelection(this.view);

  final SmartView view;
}

final class ProjectSelection extends NavSelection {
  const ProjectSelection(this.projectId);

  final String projectId;
}
