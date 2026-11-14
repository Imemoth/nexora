import 'dart:io';

/// Development diagnostics for the sign-in lifecycle (step names and timings).
///
/// Never receives passwords, access tokens or refresh tokens: only fixed event
/// names and short non-secret values (counts, error type names, codes). As a
/// second line of defence, any value attached under a key that looks secret is
/// dropped, and values are cut to a short length.
abstract interface class AuthLog {
  void log(String event, [Map<String, Object?> data = const {}]);
}

/// The default: does nothing.
final class NullAuthLog implements AuthLog {
  const NullAuthLog();

  @override
  void log(String event, [Map<String, Object?> data = const {}]) {}
}

/// Collects lines in memory (tests).
final class MemoryAuthLog implements AuthLog {
  final List<String> lines = [];

  @override
  void log(String event, [Map<String, Object?> data = const {}]) {
    lines.add(formatAuthLogLine(DateTime.utc(2000), event, data));
  }
}

final RegExp _secretKey = RegExp(
  r'pass|token|secret|authorization|apikey|api_key|bearer|cookie',
  caseSensitive: false,
);

/// One line: `time event key=value ...`, with secret-looking keys removed.
String formatAuthLogLine(
  DateTime time,
  String event,
  Map<String, Object?> data,
) {
  final buffer = StringBuffer(time.toUtc().toIso8601String())
    ..write(' ')
    ..write(event.replaceAll(RegExp(r'\s'), '_'));
  data.forEach((key, value) {
    if (_secretKey.hasMatch(key)) {
      return;
    }
    var text = '$value'.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    if (text.length > 120) {
      text = '${text.substring(0, 120)}...';
    }
    buffer
      ..write(' ')
      ..write(key)
      ..write('=')
      ..write(text);
  });
  return buffer.toString();
}

/// Appends lines to a file, flushing each one, so the last line shows where a
/// stuck operation stopped. The file is cut when it grows past about 256 KiB.
/// A logging failure never affects the application.
final class FileAuthLog implements AuthLog {
  FileAuthLog(this.file, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  final File file;
  final DateTime Function() _now;
  static const int _maxBytes = 256 * 1024;

  @override
  void log(String event, [Map<String, Object?> data = const {}]) {
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        file.writeAsStringSync('');
      }
      file.writeAsStringSync(
        '${formatAuthLogLine(_now(), event, data)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // diagnostics must never break sign-in
    }
  }
}
