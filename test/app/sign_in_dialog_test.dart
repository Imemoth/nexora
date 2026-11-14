import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_panel.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<SignInOutcome> Function(String, String) signIn,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountBar(
            panel: AccountPanel(
              initial: const AccountView(phase: AccountPhase.signedOut),
              views: const Stream<AccountView>.empty(),
              signIn: signIn,
              signOut: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email')),
      'a@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      'pw',
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pump();
  }

  bool submitEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const ValueKey('sign-in-submit')))
      .enabled;

  testWidgets('success closes the dialog', (tester) async {
    await open(tester, (e, p) async => SignInOutcome.success);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsNothing);
  });

  testWidgets('a failure shows the error and re-enables the button', (
    tester,
  ) async {
    await open(tester, (e, p) async => SignInOutcome.offline);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.signInOffline), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('an unexpected exception is contained, retry is possible', (
    tester,
  ) async {
    var calls = 0;
    await open(tester, (e, p) async {
      calls++;
      if (calls == 1) {
        throw StateError('unexpected');
      }
      return SignInOutcome.success;
    });
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.signInFailed), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsNothing);
  });

  testWidgets('an operation that never completes ends with a timeout error', (
    tester,
  ) async {
    await open(tester, (e, p) => Completer<SignInOutcome>().future);
    await submit(tester);
    expect(submitEnabled(tester), isFalse); // busy while waiting
    await tester.pump(signInDialogTimeout + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text(AppStrings.signInTimedOut), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
  });

  testWidgets('account folder failure has its own actionable message', (
    tester,
  ) async {
    await open(tester, (e, p) async => SignInOutcome.accountStorageFailed);
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.signInAccountStorage), findsOneWidget);
    expect(submitEnabled(tester), isTrue);
  });
}
