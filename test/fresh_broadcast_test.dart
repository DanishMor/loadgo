import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/backend.dart';

/// Part 5: the newest-only streams are async* streams (listen once). Screens listen again after every rebuild, so they go
/// through freshBroadcast.
void main() {
  test('two listeners at the same time both get the values', () async {
    final s = freshBroadcast(() => Stream.fromIterable([1, 2, 3]));
    final a = <int>[], b = <int>[];
    final sa = s.listen(a.add), sb = s.listen(b.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sa.cancel();
    await sb.cancel();
    expect(a, [1, 2, 3]);
    expect(b, [1, 2, 3]);
  });

  test('it can be listened to again after the last listener left (a fresh pipeline each time)', () async {
    var made = 0;
    final s = freshBroadcast(() {
      made++;
      return Stream.fromIterable([made]);
    });
    expect(await s.first, 1);
    expect(await s.first, 2);
    expect(made, 2);
  });

  test('the source is cancelled when nobody listens any more, and errors are passed on', () async {
    var cancelled = false;
    final source = StreamController<int>(onCancel: () => cancelled = true);
    final s = freshBroadcast(() => source.stream);
    final errors = <Object>[];
    final sub = s.listen((_) {}, onError: errors.add);
    source.addError('boom');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(errors, ['boom']);
    await sub.cancel();
    expect(cancelled, isTrue);
  });
}
