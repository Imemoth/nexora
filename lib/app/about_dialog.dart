import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/core/build_info.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'build_info_loader.dart';

String buildTypeLabel(BuildInfo info) => switch (info.kind) {
  BuildKind.release => AppStrings.buildTypeRelease,
  BuildKind.developmentTest => AppStrings.buildTypeDevelopmentTest,
  BuildKind.local => AppStrings.buildTypeLocal,
};

String syncLabel(BuildInfo info) =>
    info.syncEnabled ? AppStrings.syncOn : AppStrings.syncOff;

/// Opens About: the exact build that is running.
Future<void> showAboutNexoraDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => AboutNexoraDialog(info: BuildInfoScope.of(context)),
  );
}

/// Version, source commit and build type. A DEVELOPMENT TEST build is marked in
/// the warning colour and in words; a local build says its commit cannot be
/// confirmed. Nothing here is secret: no URLs, keys or account data.
class AboutNexoraDialog extends StatelessWidget {
  const AboutNexoraDialog({super.key, required this.info});

  final BuildInfo info;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final dev = info.isDevelopmentTest;
    final local = info.kind == BuildKind.local;
    final commit = info.shortCommit;
    return AlertDialog(
      key: const ValueKey('about-dialog'),
      title: const Text(AppStrings.aboutTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(
              label: AppStrings.aboutVersion,
              valueKey: const ValueKey('about-version'),
              value: info.versionLabel,
            ),
            _Row(
              label: AppStrings.aboutCommit,
              valueKey: const ValueKey('about-commit'),
              value: commit ?? AppStrings.commitUnknown,
              mono: commit != null,
              muted: commit == null,
            ),
            _Row(
              label: AppStrings.aboutBuild,
              valueKey: const ValueKey('about-build-type'),
              value: buildTypeLabel(info),
              color: dev ? c.statusReview : null,
              bold: dev,
            ),
            _Row(
              label: AppStrings.aboutSync,
              valueKey: const ValueKey('about-sync'),
              value: syncLabel(info),
              bold: info.syncEnabled,
            ),
            if (info.runId != null)
              _Row(
                label: AppStrings.aboutRun,
                valueKey: const ValueKey('about-run'),
                value: info.runId!,
                mono: true,
              ),
            if (dev || local)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  dev
                      ? AppStrings.aboutDevelopmentNote
                      : AppStrings.aboutLocalNote,
                  key: const ValueKey('about-note'),
                  style: NexoraText.caption.copyWith(
                    color: dev ? c.statusReview : c.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('about-copy'),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: info.toReport(
                  appName: AppStrings.appName,
                  buildTypeLabel: buildTypeLabel(info),
                  unknownCommitLabel: AppStrings.commitUnknown,
                  syncLabel: syncLabel(info),
                ),
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text(AppStrings.aboutCopied)),
              );
            }
          },
          child: const Text(AppStrings.aboutCopy),
        ),
        FilledButton(
          key: const ValueKey('about-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.aboutClose),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.valueKey,
    required this.value,
    this.mono = false,
    this.muted = false,
    this.bold = false,
    this.color,
  });

  final String label;
  final Key valueKey;
  final String value;
  final bool mono;
  final bool muted;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    // Commit ids are read aloud and compared character by character: tabular
    // figures and a little spacing make them easier to check.
    final base = mono
        ? NexoraText.bodyStrong.copyWith(
            letterSpacing: 0.6,
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : NexoraText.bodyStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: NexoraText.label.copyWith(color: c.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              key: valueKey,
              style: base.copyWith(
                color: color ?? (muted ? c.textMuted : c.text1),
                fontWeight: bold ? FontWeight.w800 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
