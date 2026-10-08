import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/bilty/bilty_card.dart';
import 'package:transport_app/core/bilty/lr_copy_screen.dart';
import 'package:transport_app/core/bilty/lr_form_screen.dart';
import 'package:transport_app/core/bilty/lr_model.dart';
import 'package:transport_app/core/bilty/lr_send_screen.dart';
import 'package:transport_app/core/bilty/lr_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/theme/app_theme.dart';

import 'test_utils.dart';

/// The bilty screens fit a 360 x 640 phone at 1.6x text in the longest
/// languages, light and dark.
void main() {
  final db = FakeFirebaseFirestore();
  String? uid = 'tr1';
  late Booking booking;
  late LrBundle bundle;

  setUp(() async {
    Backend.useFakes(db: db, uid: () => uid);
    await db.collection('users').doc('tr1').set({'role': 'fleet', 'name': 'Ravi', 'companyName': 'Sharma Roadlines Pvt Ltd'});
    await db.collection('bookings').doc('B1').set({
      'loadId': 'L1', 'driverId': 'tr1', 'vehicleId': 'v1', 'customerId': 'c1', 'status': 'accepted', 'pickup': 'Thiruvananthapuram', 'drop': 'Visakhapatnam',
      'cargoType': 'Fast moving consumer goods', 'weight': 12, 'vehicleType': '20ft', 'vehicleNumber': 'MH12AB1234', 'driverName': 'Sharma Roadlines', 'driverPhone': '', 'timeline': <String, dynamic>{},
      'fleetOwnerId': 'tr1', 'assignedDriverId': 'd1', 'assignedDriverName': 'Ramasubramanian', 'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(),
    });
    booking = Booking.fromDoc(await db.collection('bookings').doc('B1').get());
  });

  for (final lang in [AppLanguage.english, AppLanguage.tamil, AppLanguage.telugu, AppLanguage.urdu]) {
    for (final dark in [false, true]) {
      testWidgets('bilty screens fit 360x640 at 1.6x text (${lang.name}, ${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        languageNotifier.value = lang;
        addTearDown(() => languageNotifier.value = AppLanguage.english);
        AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
        await tester.runAsync(() async {
          uid = 'tr1';
          for (final d in (await db.collection('lrs').get()).docs) {
            await d.reference.delete();
          }
          final lr = await LrService.issue(
              booking,
              const LrDraft(consignorName: 'Anil Traders and Sons Private Limited', consigneeName: 'Venkataramanan Wholesale Stores', goods: 'Fast moving consumer goods', packages: 400, weightTons: 12, freightPaise: 2400000, advancePaise: 400000, marginPaise: 100000, goodsValuePaise: 90000000, invoiceNo: 'INV/2026/000123', consignorGstin: '27ABCDE1234F1Z5', ewayBillNo: '123456789012'));
          bundle = await LrService.bundle(lr);
        });
        final screens = <String, Widget>{
          'card': SingleChildScrollView(child: BiltyCard(booking: booking)),
          'form': LrFormScreen(booking: booking, issuerRole: LrIssuerRole.transporter),
          'edit': LrFormScreen(booking: booking, issuerRole: LrIssuerRole.transporter, editing: bundle),
          'send': LrSendScreen(booking: booking, bundle: bundle),
          'copy': LrCopyScreen(booking: booking, lr: bundle.pub, copy: LrCopy.full),
          'driver': DriverLrScreen(booking: booking),
        };
        for (final e in screens.entries) {
          await tester.pumpWidget(LanguageScope(
            notifier: languageNotifier,
            child: MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.build(Brightness.light),
              darkTheme: AppTheme.build(Brightness.dark),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: c!),
              home: e.key == 'card' ? Scaffold(body: e.value) : e.value,
            ),
          ));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: e.key);
        }
      });
    }
  }
}
