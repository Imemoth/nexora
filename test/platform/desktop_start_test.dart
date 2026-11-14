import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/platform/desktop_integration.dart';

/// Regression: `main()` creates the integration before `runApp`. Constructing
/// it must not require a binding that the caller has not initialized (it
/// crashed the packaged app before the database was opened).
void main() {
  test('constructing the integration initializes the services binding', () {
    // No TestWidgetsFlutterBinding.ensureInitialized() here on purpose.
    final desktop = WindowsDesktopIntegration();
    expect(desktop.available, isTrue);
    desktop.dispose();
  });
}
