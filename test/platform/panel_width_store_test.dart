import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/platform/panel_width_store.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexora-panels');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing saved loads null', () {
    expect(FilePanelWidthStore(file).load(), isNull);
  });

  test('a saved pair round-trips through a new store instance', () {
    FilePanelWidthStore(file)
        .save(const PanelWidths(sidebar: 300, details: 450));
    final loaded = FilePanelWidthStore(file).load();
    expect(loaded?.sidebar, 300);
    expect(loaded?.details, 450);
  });

  test('saving keeps the theme and the window entries of the same file', () {
    file.writeAsStringSync(
      jsonEncode({
        'theme_preference': 'dark',
        'window': {'left': 1},
      }),
    );
    FilePanelWidthStore(file)
        .save(const PanelWidths(sidebar: 210, details: 400));
    final json = jsonDecode(file.readAsStringSync()) as Map;
    expect(json['theme_preference'], 'dark');
    expect(json['window'], {'left': 1});
    expect(json['panel_widths'], {'sidebar': 210.0, 'details': 400.0});
  });

  test('a damaged file or nonsense values load null and never throw', () {
    file.writeAsStringSync('{not json');
    expect(FilePanelWidthStore(file).load(), isNull);
    for (final bad in [
      {'sidebar': 'wide', 'details': 380},
      {'sidebar': 248},
      {'sidebar': -5, 'details': 380},
      {'sidebar': 0, 'details': 380},
      'x',
    ]) {
      file.writeAsStringSync(jsonEncode({'panel_widths': bad}));
      expect(FilePanelWidthStore(file).load(), isNull, reason: '$bad');
    }
  });

  test('a damaged file is replaced by the next save', () {
    file.writeAsStringSync('{not json');
    FilePanelWidthStore(file)
        .save(const PanelWidths(sidebar: 250, details: 390));
    expect(FilePanelWidthStore(file).load()?.details, 390);
  });

  test('an unwritable location does not throw', () {
    // A directory where the file should be makes the rename fail.
    Directory('${dir.path}/blocked.json').createSync();
    expect(
      () =>
          FilePanelWidthStore(File('${dir.path}/blocked.json'))
              .save(const PanelWidths(sidebar: 250, details: 390)),
      returnsNormally,
    );
  });
}
