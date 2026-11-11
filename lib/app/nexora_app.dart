import 'package:flutter/material.dart';

/// Application root. Phase 0 shell: no network, no Supabase, no configuration.
class NexoraApp extends StatelessWidget {
  const NexoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _DiagnosticHome(),
    );
  }
}

class _DiagnosticHome extends StatelessWidget {
  const _DiagnosticHome();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nexora', style: textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Offline ready'),
          ],
        ),
      ),
    );
  }
}
