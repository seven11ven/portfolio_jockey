import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_jockey/services/native/gio_apps.dart';

void main() {
  const shared = '/run/user/1000/app/io.github.seven11ven.portfolio_jockey';
  const resolved = '/run/flatpak/app/io.github.seven11ven.portfolio_jockey';

  test('an edit copy is accepted by either form of the shared folder', () {
    expect(isInFolder('$resolved/portfolio_jockey/edit-1/file/a.pdf', [shared, resolved]), isTrue, reason: 'the path the PM got');
    expect(isInFolder('$shared/portfolio_jockey/edit-1/file/a.pdf', [shared, resolved]), isTrue);
  });

  test('anything else is refused, including a look-alike name', () {
    expect(isInFolder('/run/user/1000/portfolio_jockey/edit-1/file/a.pdf', [shared, resolved]), isFalse);
    expect(isInFolder('$shared-other/a.pdf', [shared, resolved]), isFalse);
  });
}
