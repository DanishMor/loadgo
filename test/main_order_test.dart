import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Services that need Firebase must start after Firebase.initializeApp in main().
void main() {
  test('the push router starts after Firebase and the crash service', () {
    final main = File('lib/main.dart').readAsStringSync();
    final init = main.indexOf('await Firebase.initializeApp');
    final router = main.indexOf('PushRouter.start(');
    expect(init, greaterThan(0));
    expect(router, greaterThan(init), reason: 'FirebaseMessaging.instance throws before initializeApp, so the router would stay off');
    expect(RegExp(r'PushRouter\.start\(').allMatches(main).length, 1);
  });

  test('nothing else that uses Firebase is called in main() before initializeApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final before = main.substring(main.indexOf('Future<void> main()'), main.indexOf('await Firebase.initializeApp'));
    for (final w in ['FirebaseMessaging', 'FirebaseAuth', 'FirebaseFirestore', 'Backend.', 'PushService', 'CrashService']) {
      expect(before.contains(w), isFalse, reason: '$w before initializeApp');
    }
  });
}
