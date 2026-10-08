import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/navigation/deep_links.dart';
import 'package:transport_app/core/share/share_links.dart';

/// MASTER-5 Task 19: one rule for every way a link can arrive.
void main() {
  setUp(DeepLinks.reset);

  test('a route name, a full link and a padded link all give the same load id', () {
    final host = ShareLinks.host;
    expect(DeepLinks.loadIdFrom('/load/abc123'), 'abc123');
    expect(DeepLinks.loadIdFrom('https://$host/load/abc123'), 'abc123');
    expect(DeepLinks.loadIdFrom('  https://$host/load/abc123  '), 'abc123');
  });

  test('anything else is ignored and leaves nothing pending', () {
    for (final bad in [null, '', '/', '/load', '/load/', '/booking/1', 'ftp://x/load/1', '/load/a/b', '/load/${'x' * 65}']) {
      expect(DeepLinks.handle(bad), isFalse, reason: '$bad');
    }
    expect(DeepLinks.pendingLoadId.value, isNull);
  });

  test('a good link waits until a home picks it up; a second one replaces it', () {
    expect(DeepLinks.handle('/load/one'), isTrue);
    expect(DeepLinks.pendingLoadId.value, 'one');
    expect(DeepLinks.handle('/load/two'), isTrue);
    expect(DeepLinks.pendingLoadId.value, 'two');
  });
}
