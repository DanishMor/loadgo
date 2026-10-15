import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/security/secure_screen.dart';

/// F4: screenshots and recording are blocked on sensitive screens.
void main() {
  final calls = <bool>[];

  setUp(() {
    SecureScreen.reset();
    calls.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SecureScreen.channel, (call) async {
      if (call.method == 'set') calls.add(call.arguments as bool);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SecureScreen.channel, null);
    SecureScreen.reset();
  });

  test('the flag is OFF by default, also outside pilot mode', () {
    final spec = Features.registry.firstWhere((s) => s.key == FeatureKey.secureScreens);
    expect(spec.pilotOn, isFalse);
    expect(spec.normalOn, isFalse);
    expect(const Features().isOn(FeatureKey.secureScreens), isFalse);
    expect(const Features(pilotMode: false).isOn(FeatureKey.secureScreens), isFalse);
  });

  test('in a debug build nothing is sent to the phone (release builds only)', () async {
    await SecureScreen.acquire();
    expect(calls, isEmpty);
    await SecureScreen.release();
  });

  test('when enabled: the first holder switches it on, the last one switches it off', () async {
    SecureScreen.enabledCheck = () => true;
    await SecureScreen.acquire();
    await SecureScreen.acquire();
    expect(calls, [true], reason: 'one on for two screens');
    await SecureScreen.release();
    expect(calls, [true], reason: 'still one screen open');
    await SecureScreen.release();
    expect(calls, [true, false]);
    await SecureScreen.release(); // extra release never goes negative
    expect(calls, [true, false]);
  });

  test('a phone without the native side does not break anything', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SecureScreen.channel, (call) async => throw PlatformException(code: 'x'));
    SecureScreen.enabledCheck = () => true;
    await SecureScreen.acquire();
    await SecureScreen.release();
  });

  testWidgets('SecureScope shows its child, holds while open and lets go when closed', (t) async {
    SecureScreen.enabledCheck = () => true;
    await t.pumpWidget(const MaterialApp(home: SecureScope(child: Text('private'))));
    expect(find.text('private'), findsOneWidget);
    await t.pump();
    expect(calls, [true]);
    await t.pumpWidget(const MaterialApp(home: Text('public')));
    await t.pump();
    expect(calls, [true, false]);
  });

  group('guards: the sensitive screens stay covered', () {
    const covered = {
      'lib/auth/otp_verification_screen.dart': 'login code',
      'lib/core/documents/documents_center_screen.dart': 'documents',
      'lib/driver/vehicle_documents_screen.dart': 'vehicle documents',
      'lib/core/bilty/lr_copy_screen.dart': 'private LR copy',
      'lib/driver/wallet_screen.dart': 'earnings',
      'lib/customer/trip_otp_card.dart': 'trip codes',
    };
    for (final e in covered.entries) {
      test('${e.value} uses SecureScope', () {
        expect(File(e.key).readAsStringSync(), contains('SecureScope('));
      });
    }

    test('the Android side sets and clears FLAG_SECURE on the same channel', () {
      final k = File('android/app/src/main/kotlin/com/example/transport_app/MainActivity.kt').readAsStringSync();
      expect(k, contains('FLAG_SECURE'));
      expect(k, contains('loadgo/secure_screen'));
      expect(k, contains('clearFlags'));
    });
  });
}
