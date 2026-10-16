import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/security/app_lock.dart';
import 'package:transport_app/core/security/local_auth_authenticator.dart';
import 'package:local_auth/local_auth.dart';

class _FakeAuth implements LocalAuthentication {
  bool supported = true;
  bool pass = true;
  bool throws = false;
  String? lastReason;

  @override
  Future<bool> isDeviceSupported() async {
    if (throws) throw Exception('no sensor');
    return supported;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    lastReason = localizedReason;
    if (throws) throw Exception('plugin error');
    return pass;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(AppLock.reset);

  test('available follows the phone', () async {
    final f = _FakeAuth();
    final a = LocalAuthAppLockAuthenticator(f);
    expect(await a.isAvailable(), isTrue);
    f.supported = false;
    expect(await a.isAvailable(), isFalse);
  });

  test('authenticate passes the reason and returns the result', () async {
    final f = _FakeAuth();
    final a = LocalAuthAppLockAuthenticator(f);
    expect(await a.authenticate('Unlock'), isTrue);
    expect(f.lastReason, 'Unlock');
    f.pass = false;
    expect(await a.authenticate('Unlock'), isFalse);
  });

  test('plugin errors never throw', () async {
    final f = _FakeAuth()..throws = true;
    final a = LocalAuthAppLockAuthenticator(f);
    expect(await a.isAvailable(), isFalse);
    expect(await a.authenticate('x'), isFalse);
  });

  test('AppLock.set(true) needs a supported phone', () async {
    final f = _FakeAuth()..supported = false;
    AppLock.authenticator = LocalAuthAppLockAuthenticator(f);
    expect(await AppLock.set(true), isFalse);
    f.supported = true;
    expect(await AppLock.set(true), isTrue);
    expect(AppLock.enabled.value, isTrue);
  });
}
