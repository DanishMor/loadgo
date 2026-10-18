import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/dispatch_config_service.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/customer/instant_wait_card.dart';

/// U12: the customer's waiting card (ring, reach, raise the price, search wider).
void main() {
  final t0 = DateTime(2030, 1, 1, 12);
  late FakeFirebaseFirestore db;

  setUp(() async {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'customer1');
    DispatchConfigService.reset();
    languageNotifier.value = AppLanguage.english;
    await db.collection('loads').doc('L1').set({
      'shipperId': 'customer1',
      'pickup': 'Delhi',
      'drop': 'Jaipur',
      'cargoType': 'FMCG',
      'weight': 5,
      'vehicleType': '20ft',
      'budget': 25000,
      'pickupDate': Timestamp.fromDate(DateTime(2030, 1, 5)),
      'status': 'open',
      'createdAt': Timestamp.fromDate(t0),
    });
  });

  Future<Load> read() async => Load.fromDoc(await db.collection('loads').doc('L1').get());

  Widget host(Load load, DateTime now, {double scale = 1.0, Brightness b = Brightness.light, bool lowEnd = false}) => LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(b, lowEnd: lowEnd),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
          home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: InstantWaitCard(load: load, now: () => now))),
        ),
      );

  testWidgets('while searching: the ring, the reach and the round; no raise buttons yet', (t) async {
    final load = await t.runAsync(read) as Load;
    await t.pumpWidget(host(load, t0.add(const Duration(seconds: 35))));
    expect(find.text('Looking for a truck near you'), findsOneWidget);
    expect(find.text('Searching within 7 km'), findsOneWidget);
    expect(find.text('Round 2 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('instRaise5')), findsNothing);
    expect(find.byKey(const ValueKey('instPrice')), findsOneWidget);
  });

  testWidgets('after the last wave: raise 5% changes the price on the load; search wider adds one ring', (t) async {
    final load = await t.runAsync(read) as Load;
    await t.pumpWidget(host(load, t0.add(const Duration(seconds: 120))));
    expect(find.text('No driver has said yes yet'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('instRaise5')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect((await t.runAsync(read))!.budget, 26250);
    await t.tap(find.byKey(const ValueKey('instWiden')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect((await t.runAsync(read))!.ringBoost, 1);
  });

  testWidgets('at the widest search the button is replaced by a note', (t) async {
    await db.collection('loads').doc('L1').update({'ringBoost': 3});
    final load = await t.runAsync(read) as Load;
    await t.pumpWidget(host(load, t0.add(const Duration(seconds: 500))));
    expect(find.byKey(const ValueKey('instWiden')), findsNothing);
    expect(find.text('Widest search reached'), findsOneWidget);
  });

  for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
    for (final stalled in [false, true]) {
      testWidgets('fits 360x640 at 2.0x text: ${lang.name} stalled=$stalled', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        languageNotifier.value = lang;
        final load = await t.runAsync(read) as Load;
        await t.pumpWidget(host(load, t0.add(Duration(seconds: stalled ? 500 : 5)), scale: 2.0));
        expect(t.takeException(), isNull);
      });
    }
  }
}
