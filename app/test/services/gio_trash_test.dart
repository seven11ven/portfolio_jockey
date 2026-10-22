// Moves a real file to the Trash through GLib, to prove the bindings work.
// It only runs on request, with XDG_DATA_HOME pointing at a temporary folder,
// so it never touches your real Trash. GLib only uses that Trash for files on
// the same drive as your home folder, so put the temporary folder there too
// (in the dev container, /tmp is a separate drive that GLib won't trash on):
//
//   T=$(mktemp -d ~/.cache/pj-gio-XXXXXX)
//   TMPDIR=$T PJ_GIO_TRASH_TEST=1 XDG_DATA_HOME=$T/share flutter test test/services/gio_trash_test.dart
//   rm -rf "$T"
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/gio_trash.dart';

void main() {
  final env = Platform.environment;
  final dataHome = env['XDG_DATA_HOME'];
  final enabled = env['PJ_GIO_TRASH_TEST'] == '1' && dataHome != null && dataHome.startsWith(Directory.systemTemp.path);

  test('GLib moves a file into the Trash with a .trashinfo', () async {
    final source = File('$dataHome/../pj-gio-trash-test.txt');
    await source.writeAsString('trash me');

    await const GioTrash().trash(source.absolute.path);

    expect(await source.exists(), isFalse);
    expect(await File('$dataHome/Trash/files/pj-gio-trash-test.txt').readAsString(), 'trash me');
    final info = await File('$dataHome/Trash/info/pj-gio-trash-test.txt.trashinfo').readAsString();
    expect(info, contains('[Trash Info]'));
    expect(info, contains('DeletionDate='));
  }, skip: enabled ? false : 'Set PJ_GIO_TRASH_TEST=1 and a temporary XDG_DATA_HOME to run');

  test('a file that does not exist is reported, not ignored', () async {
    await expectLater(const GioTrash().trash('$dataHome/../no-such-file.txt'), throwsA(isA<FileSystemException>()));
  }, skip: enabled ? false : 'Set PJ_GIO_TRASH_TEST=1 and a temporary XDG_DATA_HOME to run');
}
