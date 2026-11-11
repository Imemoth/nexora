import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';

// Phase 0 Task 1: intentionally red. NexoraApp is implemented in Task 2.
void main() {
  testWidgets('app boots without network and shows the Nexora placeholder',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(const NexoraApp());

    expect(find.text('Nexora'), findsOneWidget);
    expect(errors, isEmpty);
  });
}
