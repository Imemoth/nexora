/// Which build is running: version, source commit and build type.
///
/// Pure Dart. The version has one source, `pubspec.yaml` (the Flutter
/// convention: it also becomes the Windows file version of nexora.exe). The
/// commit and the build type are written by CI at build time and arrive as
/// `--dart-define` values; a build made without them is a local build and says
/// so. Nothing here can be filled in with a guess: an unknown commit stays
/// unknown.
library;

/// How the running build was made.
enum BuildKind {
  /// The normal CI release build (`ci.yml`).
  release,

  /// The manual CI build with synchronization against the TEST project
  /// (`windows-sync-dev-build.yml`). Never a production release.
  developmentTest,

  /// Anything else: `flutter run`, a developer's own build, tests.
  local,
}

final class BuildInfo {
  const BuildInfo({
    required this.version,
    required this.kind,
    this.buildNumber,
    this.commit,
    this.runId,
  });

  /// Nothing known: used where no build information was provided.
  static const BuildInfo unknown = BuildInfo(
    version: unknownVersion,
    kind: BuildKind.local,
  );

  static const String unknownVersion = 'unknown';

  /// Combines the pubspec text and the three build-time values.
  ///
  /// [commit] is accepted only as 7 to 40 hexadecimal characters, optionally
  /// followed by `-dirty` (a local build with uncommitted changes); anything
  /// else, including an empty value, is treated as unknown.
  factory BuildInfo.fromSources({
    required String? pubspecYaml,
    String commit = '',
    String buildType = '',
    String runId = '',
  }) {
    final parsed = pubspecYaml == null
        ? null
        : parsePubspecVersion(pubspecYaml);
    return BuildInfo(
      version: parsed?.version ?? unknownVersion,
      buildNumber: parsed?.buildNumber,
      kind: switch (buildType.trim()) {
        'release' => BuildKind.release,
        'development-test' => BuildKind.developmentTest,
        _ => BuildKind.local,
      },
      commit: normalizeCommit(commit),
      runId: _normalizeRun(runId),
    );
  }

  /// `1.2.3` and the optional build number after `+`, from a pubspec's
  /// top-level `version:` line. Null when there is none.
  static ({String version, String? buildNumber})? parsePubspecVersion(
    String yaml,
  ) {
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$',
      multiLine: true,
    ).firstMatch(yaml);
    if (match == null) {
      return null;
    }
    return (version: match.group(1)!, buildNumber: match.group(2));
  }

  /// The commit in canonical lower case, or null when [raw] is not one.
  static String? normalizeCommit(String raw) {
    final text = raw.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{7,40}(-dirty)?$').hasMatch(text) ? text : null;
  }

  static String? _normalizeRun(String raw) {
    final text = raw.trim();
    return RegExp(r'^[0-9]{1,20}(-[0-9]{1,6})?$').hasMatch(text) ? text : null;
  }

  /// `1.0.0`.
  final String version;

  /// The `+N` part of the pubspec version, when there is one.
  final String? buildNumber;

  /// The source commit (7 to 40 hex characters, maybe `-dirty`), or null.
  final String? commit;
  final BuildKind kind;

  /// The CI run, `<run id>-<attempt>`, for finding the workflow run.
  final String? runId;

  /// `1.0.0+1`, or `1.0.0` without a build number.
  String get versionLabel =>
      buildNumber == null ? version : '$version+$buildNumber';

  /// The first seven characters of the commit (plus `-dirty` when set).
  String? get shortCommit {
    final c = commit;
    if (c == null) {
      return null;
    }
    final dirty = c.endsWith('-dirty');
    final hex = dirty ? c.substring(0, c.length - '-dirty'.length) : c;
    return '${hex.substring(0, 7)}${dirty ? '-dirty' : ''}';
  }

  bool get isDevelopmentTest => kind == BuildKind.developmentTest;

  /// Plain text for a bug report. Contains nothing but the identity above.
  String toReport({
    required String appName,
    required String buildTypeLabel,
    required String unknownCommitLabel,
  }) {
    return [
      '$appName $versionLabel',
      'Commit: ${commit ?? unknownCommitLabel}',
      'Build: $buildTypeLabel',
      if (runId != null) 'CI run: $runId',
    ].join('\n');
  }
}
