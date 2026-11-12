import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

import 'theme.dart';

/// Shown when the local database cannot be opened. It touches no data and offers
/// no silent reset. The message says what to do.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: buildNexoraDarkTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              key: const ValueKey('startup-error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
