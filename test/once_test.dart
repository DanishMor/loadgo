import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/widgets/once.dart';

void main() {
  test('a second tap while the first is running is ignored', () async {
    final once = Once();
    var writes = 0;
    final gate = Completer<void>();
    Future<void> save() async {
      writes++;
      await gate.future;
    }

    final first = once.run(save);
    expect(once.running, isTrue);
    expect(await once.run(save), isFalse);
    expect(await once.run(save), isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(writes, 1);
    expect(once.running, isFalse);
  });

  test('after a finished or failed run it can run again', () async {
    final once = Once();
    var n = 0;
    await once.run(() async => n++);
    await expectLater(once.run(() async => throw StateError('x')), throwsStateError);
    expect(once.running, isFalse);
    await once.run(() async => n++);
    expect(n, 2);
  });
}
