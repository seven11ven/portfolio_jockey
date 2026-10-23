import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/private_folder.dart';

void main() {
  test('inside a Flatpak, edit copies go in the folder Flatpak shares with the desktop', () {
    final folders = PrivateFolders.forEditing(sandboxed: true, environment: {'XDG_RUNTIME_DIR': '/run/user/1000', 'FLATPAK_ID': 'io.github.seven11ven.portfolio_jockey'});
    expect(folders.runtimeDir, '/run/user/1000/app/io.github.seven11ven.portfolio_jockey');
  });

  test('outside a Flatpak, edit copies go in the session folder as before', () {
    final folders = PrivateFolders.forEditing(sandboxed: false, environment: {'XDG_RUNTIME_DIR': '/run/user/1000', 'FLATPAK_ID': 'x'});
    expect(folders.runtimeDir, '/run/user/1000');
  });

  test('a strange app ID is never used as a path', () {
    final folders = PrivateFolders.forEditing(sandboxed: true, environment: {'XDG_RUNTIME_DIR': '/run/user/1000', 'FLATPAK_ID': '../../tmp'});
    expect(folders.runtimeDir, '/run/user/1000');
  });
}
