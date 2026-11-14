import 'package:flutter/widgets.dart';

import 'theme_controller.dart';

/// Makes the [ThemeController] available to the widget tree.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, or null when no scope is above [context] (a widget test
  /// that pumps a single widget). The theme selector hides itself then.
  static ThemeController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeScope>()?.notifier;
  }
}
