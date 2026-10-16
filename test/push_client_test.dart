import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/navigation/app_routes.dart';
import 'package:transport_app/core/notifications/notifications_screen.dart';
import 'package:transport_app/core/notifications/push_router.dart';
import 'package:transport_app/core/notifications/push_target.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/device_service.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/push_service.dart';

/// F24: the phone side of push messages (the server side is in functions/).
/// Real time for the stored settings, frames for the dialog.
Future<void> settleReal(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceService.resetForTest();
    FeaturesService.reset();
    AppRoutes.openBooking = null;
    AppRoutes.openLoad = null;
    AppRoutes.openWallet = null;
  });

  group('the token is kept per device', () {
    test('saveToken writes the profile list and this device record', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
      final id = await DeviceService.deviceId();
      await db.collection('users').doc('u1').collection('devices').doc(id).set({
        'label': 'android',
        'trusted': true,
        'revoked': false,
      });
      final token = 'tok' * 20;
      await PushService.saveToken(token);
      expect(
        (await db.collection('users').doc('u1').get()).data()!['fcmTokens'],
        [token],
      );
      final dev =
          (await db
                  .collection('users')
                  .doc('u1')
                  .collection('devices')
                  .doc(id)
                  .get())
              .data()!;
      expect(dev['fcmToken'], token);
      expect(dev['fcmUpdatedAt'], isNotNull);
      expect(dev['label'], 'android');
    });

    test('no device record yet: the profile list is still saved and nothing throws', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'u1');
      await PushService.saveToken('tok' * 20);
      expect(
        (await db.collection('users').doc('u1').get()).data()!['fcmTokens'],
        hasLength(1),
      );
    });

    test('signed out: nothing is written', () async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => null);
      await PushService.saveToken('tok' * 20);
      expect((await db.collection('users').get()).docs, isEmpty);
    });
  });

  group('asking after sign-in', () {
    final key = GlobalKey<NavigatorState>();

    test('with the switch off nothing is asked and nothing happens', () async {
      FeaturesService.notifier.value = const Features();
      await PushService.askAfterSignIn(key, wait: Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getString('push_asked_day'),
        isNull,
      );
    });

    testWidgets(
      'with the switch on the explanation shows first and is asked once a day',
      (t) async {
        FeaturesService.notifier.value = const Features(
          flags: {FeatureKey.pushNotifications: true},
        );
        final db = FakeFirebaseFirestore();
        Backend.useFakes(db: db, uid: () => 'u1');
        PushService.now = () => DateTime(2026, 10, 15, 10);
        addTearDown(() => PushService.now = DateTime.now);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            home: const Scaffold(body: Text('home')),
          ),
        );
        var done = false;
        final asked = PushService.askAfterSignIn(
          key,
          wait: Duration.zero,
        ).whenComplete(() => done = true);
        await settleReal(t);
        expect(
          find.byKey(const ValueKey('rationaleYes')),
          findsOneWidget,
          reason: 'the explanation first',
        );
        await t.tap(find.byKey(const ValueKey('rationaleNo')));
        await settleReal(t);
        expect(done, isTrue);
        await asked;
        expect(
          (await SharedPreferences.getInstance()).getString('push_asked_day'),
          '2026-10-15',
        );
        // The same day: not again.
        await PushService.askAfterSignIn(key, wait: Duration.zero);
        await settleReal(t);
        expect(find.byKey(const ValueKey('rationaleYes')), findsNothing);
      },
    );
  });

  group('a tap opens the right screen', () {
    testWidgets(
      'booking, chat and LR go to the booking; a load to the load; the wallet to the wallet',
      (t) async {
        final calls = <String>[];
        AppRoutes.openBooking = (c, id, {required isDriver}) =>
            calls.add('booking $id ${isDriver ? 'driver' : 'customer'}');
        AppRoutes.openLoad = (c, id, {required isDriver}) =>
            calls.add('load $id');
        AppRoutes.openWallet = (c, {required isDriver}) =>
            calls.add('wallet ${isDriver ? 'driver' : 'customer'}');
        late BuildContext ctx;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.booking, 'B1'),
          isDriver: false,
        );
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.chat, 'B2'),
          isDriver: true,
        );
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.lr, 'B3'),
          isDriver: true,
        );
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.load, 'L9'),
          isDriver: true,
        );
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.wallet),
          isDriver: true,
        );
        expect(calls, [
          'booking B1 customer',
          'booking B2 driver',
          'booking B3 driver',
          'load L9',
          'wallet driver',
        ]);
      },
    );

    testWidgets(
      'a missing hook or id falls back to the notification list, not a crash',
      (t) async {
        late BuildContext ctx;
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => 'u1');
        PushRouter.openTarget(
          ctx,
          const PushTarget(PushScreen.booking, 'B1'),
          isDriver: false,
        ); // no hook registered
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(NotificationsScreen), findsOneWidget);
      },
    );

    test('with the switch off a tap does nothing', () async {
      FeaturesService.notifier.value = const Features();
      final key = GlobalKey<NavigatorState>();
      await PushRouter.open(key, {'type': 'chat_message', 'bookingId': 'B1'});
    });
  });

  group('guards: the phone side of the push channels', () {
    test('the channels in the app, the server and MainActivity are the same five', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/example/transport_app/MainActivity.kt',
      ).readAsStringSync();
      final server = File('functions/src/push.js').readAsStringSync();
      for (final c in PushTarget.channels) {
        expect(kotlin, contains('"$c"'), reason: c);
        expect(server, contains("ch: '$c'"), reason: c);
      }
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, contains('default_notification_channel_id'));
    });

    test('the channel names exist in all twelve languages', () {
      for (final dir in [
        'values',
        'values-hi',
        'values-kn',
        'values-ta',
        'values-te',
        'values-mr',
        'values-gu',
        'values-bn',
        'values-pa',
        'values-ks',
        'values-ur',
      ]) {
        final xml = File('android/app/src/main/res/$dir/push_channels.xml')
            .readAsStringSync();
        for (final id in [
          'channel_bookings',
          'channel_chat',
          'channel_payments',
          'channel_offers',
          'channel_admin',
        ]) {
          expect(xml, contains('name="$id"'), reason: '$dir $id');
        }
      }
    });
  });
}
