import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/services/session_watcher.dart';

void main() {
  late StreamController<bool> auth;
  var expired = 0;
  late SessionWatcher watcher;

  setUp(() {
    auth = StreamController<bool>();
    expired = 0;
    watcher = SessionWatcher(auth.stream, onExpired: () => expired++);
  });
  tearDown(() async {
    await watcher.dispose();
    await auth.close();
  });

  Future<void> emit(bool v) async {
    auth.add(v);
    await Future<void>.delayed(Duration.zero);
  }

  test('signed out at start is not an expiry', () async {
    await emit(false);
    expect(expired, 0);
  });

  test('a session that ends by itself is reported once', () async {
    await emit(true);
    await emit(false);
    await emit(false);
    expect(expired, 1);
  });

  test('a sign-out the app asked for (logout, account deletion) is not reported', () async {
    await emit(true);
    SessionWatcher.expectSignOut();
    await emit(false);
    expect(expired, 0);
    await emit(true);
    await emit(false);
    expect(expired, 1);
  });
}
