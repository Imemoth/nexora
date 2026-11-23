import 'dart:convert';
import 'dart:io';

/// The widths of the sidebar and the details panel the user chose.
final class PanelWidths {
  const PanelWidths({required this.sidebar, required this.details});

  final double sidebar;
  final double details;

  Map<String, Object?> toJson() => {'sidebar': sidebar, 'details': details};

  /// Null unless [json] holds two finite positive numbers. The shell clamps the
  /// values to its limits, so only nonsense is rejected here.
  static PanelWidths? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final sidebar = json['sidebar'];
    final details = json['details'];
    if (sidebar is! num ||
        details is! num ||
        !sidebar.isFinite ||
        !details.isFinite ||
        sidebar <= 0 ||
        details <= 0) {
      return null;
    }
    return PanelWidths(
      sidebar: sidebar.toDouble(),
      details: details.toDouble(),
    );
  }
}

/// Where the panel widths are remembered: this device only, like the theme and
/// the window placement. Nothing here is account data and nothing synchronizes.
abstract interface class PanelWidthStore {
  PanelWidths? load();

  /// Never throws: a failed write only means the widths are not remembered.
  void save(PanelWidths widths);
}

/// [PanelWidthStore] over the shared `settings.json` (the file that holds the
/// theme and the window placement), under one `panel_widths` key. Read-modify-
/// write of that key, through a temporary file and a rename.
final class FilePanelWidthStore implements PanelWidthStore {
  FilePanelWidthStore(this._file);

  static const _key = 'panel_widths';

  final File _file;

  @override
  PanelWidths? load() => PanelWidths.tryFromJson(_read()[_key]);

  @override
  void save(PanelWidths widths) {
    try {
      final settings = _read()..[_key] = widths.toJson();
      if (!_file.parent.existsSync()) {
        _file.parent.createSync(recursive: true);
      }
      final temp = File('${_file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(settings), flush: true);
      temp.renameSync(_file.path);
    } on FileSystemException {
      // Not remembered this time; the app keeps working.
    }
  }

  Map<String, Object?> _read() {
    try {
      if (!_file.existsSync()) {
        return <String, Object?>{};
      }
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map<String, Object?>
          ? Map<String, Object?>.of(decoded)
          : <String, Object?>{};
    } on FileSystemException {
      return <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }
}

/// Keeps the widths in memory only (tests).
final class InMemoryPanelWidthStore implements PanelWidthStore {
  InMemoryPanelWidthStore([this.widths]);

  PanelWidths? widths;
  int saves = 0;

  @override
  PanelWidths? load() => widths;

  @override
  void save(PanelWidths value) {
    widths = value;
    saves++;
  }
}
