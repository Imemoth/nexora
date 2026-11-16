import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nexora/core/build_info.dart';

/// Written by CI (`--dart-define`). Absent in a local build.
const String _commit = String.fromEnvironment('NEXORA_COMMIT');
const String _buildType = String.fromEnvironment('NEXORA_BUILD_TYPE');
const String _runId = String.fromEnvironment('NEXORA_BUILD_RUN');

/// Reads the running build's identity: the version from the bundled
/// `pubspec.yaml` (its single source), the commit, build type and CI run from
/// the build-time values. Never throws; whatever is missing stays unknown.
Future<BuildInfo> loadBuildInfo({
  AssetBundle? bundle,
  String commit = _commit,
  String buildType = _buildType,
  String runId = _runId,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? yaml;
  try {
    yaml = await (bundle ?? rootBundle).loadString('pubspec.yaml');
  } on Object {
    yaml = null;
  }
  return BuildInfo.fromSources(
    pubspecYaml: yaml,
    commit: commit,
    buildType: buildType,
    runId: runId,
  );
}

/// Gives the About dialog the running build's identity.
class BuildInfoScope extends InheritedWidget {
  const BuildInfoScope({super.key, required this.info, required super.child});

  final BuildInfo info;

  static BuildInfo of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BuildInfoScope>()?.info ??
      BuildInfo.unknown;

  @override
  bool updateShouldNotify(BuildInfoScope oldWidget) => info != oldWidget.info;
}
