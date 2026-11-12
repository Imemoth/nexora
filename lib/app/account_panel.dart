import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

/// Where the account stands, in terms the user can act on.
enum AccountPhase { signedOut, signedIn, reauthRequired }

/// A message to show next to the account state, if any.
enum AccountNotice {
  none,
  signedOut,
  sessionExpired,
  anonymousRejected,
  storageProblem,
}

final class AccountView {
  const AccountView({
    required this.phase,
    this.email,
    this.notice = AccountNotice.none,
  });

  final AccountPhase phase;
  final String? email;
  final AccountNotice notice;
}

/// The outcome of a sign-in attempt, already reduced to what the dialog shows.
enum SignInOutcome {
  success,
  invalidCredentials,
  unconfirmed,
  anonymousRejected,
  offline,
  rateLimited,
  failed,
}

/// What the UI needs from the authentication layer. Provided only when
/// synchronization is enabled; the default application has no account UI.
final class AccountPanel {
  const AccountPanel({
    required this.initial,
    required this.views,
    required this.signIn,
    required this.signOut,
  });

  final AccountView initial;
  final Stream<AccountView> views;
  final Future<SignInOutcome> Function(String email, String password) signIn;
  final Future<void> Function() signOut;
}

String signInMessage(SignInOutcome outcome) => switch (outcome) {
  SignInOutcome.success => '',
  SignInOutcome.invalidCredentials => AppStrings.signInInvalid,
  SignInOutcome.unconfirmed => AppStrings.signInUnconfirmed,
  SignInOutcome.anonymousRejected => AppStrings.signInAnonymous,
  SignInOutcome.offline => AppStrings.signInOffline,
  SignInOutcome.rateLimited => AppStrings.signInRateLimited,
  SignInOutcome.failed => AppStrings.signInFailed,
};

String accountNoticeText(AccountNotice notice) => switch (notice) {
  AccountNotice.none => '',
  AccountNotice.signedOut => AppStrings.accountSignedOutNotice,
  AccountNotice.sessionExpired => AppStrings.accountSessionExpired,
  AccountNotice.anonymousRejected => AppStrings.signInAnonymous,
  AccountNotice.storageProblem => AppStrings.accountStorageProblem,
};

/// A thin bar: who is signed in, and Sign in / Sign out.
class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.panel});

  final AccountPanel panel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccountView>(
      stream: panel.views,
      initialData: panel.initial,
      builder: (context, snapshot) {
        final view = snapshot.data ?? panel.initial;
        final text = switch (view.phase) {
          AccountPhase.signedIn => AppStrings.accountSignedInAs(
            view.email ?? '',
          ),
          AccountPhase.reauthRequired => AppStrings.accountSessionExpired,
          AccountPhase.signedOut => AppStrings.accountLocalOnly,
        };
        final notice = accountNoticeText(view.notice);
        return Material(
          key: const ValueKey('account-bar'),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    notice.isEmpty ? text : '$text. $notice',
                    key: const ValueKey('account-status-text'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (view.phase == AccountPhase.signedIn)
                  TextButton(
                    key: const ValueKey('sign-out'),
                    onPressed: panel.signOut,
                    child: const Text(AppStrings.signOutAction),
                  )
                else
                  TextButton(
                    key: const ValueKey('sign-in'),
                    onPressed: () => showSignInDialog(context, panel),
                    child: const Text(AppStrings.signInAction),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> showSignInDialog(BuildContext context, AccountPanel panel) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SignInDialog(panel: panel),
  );
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.panel});

  final AccountPanel panel;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await widget.panel.signIn(_email.text, _password.text);
    if (!mounted) {
      return;
    }
    if (outcome == SignInOutcome.success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = signInMessage(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('sign-in-dialog'),
      title: const Text(AppStrings.signInTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('sign-in-email'),
              controller: _email,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(labelText: AppStrings.emailLabel),
            ),
            TextField(
              key: const ValueKey('sign-in-password'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: AppStrings.passwordLabel,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  key: const ValueKey('sign-in-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('sign-in-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancelAction),
        ),
        FilledButton(
          key: const ValueKey('sign-in-submit'),
          onPressed: _busy ? null : _submit,
          child: const Text(AppStrings.signInAction),
        ),
      ],
    );
  }
}
