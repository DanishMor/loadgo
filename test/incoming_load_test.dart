import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/dispatch/load_radar.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/models/vehicle.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/driver/v2/driver_bid_sheet.dart';
import 'package:transport_app/driver/v2/incoming_load_screen.dart';

/// U28 and U29: the Incoming Load Card and the bid sheet's numbers.
void main() {
  const delhi = (lat: 28.6139, lng: 77.2090);

  Vehicle truck({String id = 'v1', String type = '14ft', num capacity = 6}) => Vehicle(id: id, ownerId: 'd1', number: 'DL01$id', type: type, capacity: capacity, rcNumber: 'RC', status: 'active');

  Load load(String id, {num? budget = 20000, DateTime? created}) => Load(
        id: id,
        shipperId: 'c1',
        pickup: 'Delhi',
        drop: 'Jaipur',
        cargoType: 'FMCG',
        weight: 4,
        vehicleType: '14ft',
        budget: budget,
        pickupDate: null,
        notes: '',
        status: 'open',
        createdAt: Timestamp.fromDate(created ?? DateTime.now()),
      );

  test('cardFarePaise: customer price first, else the estimate, else none', () {
    expect(cardFarePaise(load('a', budget: 20000)), 2000000);
    expect(cardFarePaise(load('a', budget: null)), isNull);
  });

  test('truckForLoad: the chosen truck if it fits, else the first that fits, else none', () {
    final l = load('a');
    final now = DateTime.now();
    final all = [truck(id: 'a', type: '20ft'), truck(id: 'b'), truck(id: 'c')];
    expect(truckForLoad(all, l, preferredId: 'c', now: now)!.id, 'c');
    expect(truckForLoad(all, l, preferredId: 'a', now: now)!.id, 'b', reason: 'a does not fit');
    expect(truckForLoad([truck(type: '20ft')], l, now: now), isNull);
  });

  test('BidSheetModel: percent steps round to ten rupees and stay inside the rules', () {
    const m = BidSheetModel(farePaise: 2000000, estimatePaise: 1800000);
    expect(m.priceAt(5), 2100000);
    expect(m.priceAt(-5), 1900000);
    expect(m.priceAt(10), 2200000);
    expect(m.lowest, 540000);
    expect(m.highest, 5400000);
    expect(m.clamp(1), 540000);
    expect(m.clamp(99999999), 5400000);
    expect(m.check(2000000), isNull);
    expect(m.check(100), 'low');
    expect(m.check(9000000), 'high');
    expect(m.check(0), 'low');
  });

  test('BidSheetModel without an estimate has no 30%..300% limits, only the hard cap', () {
    const m = BidSheetModel(farePaise: 500000, estimatePaise: null);
    expect(m.check(100000), isNull);
    expect(m.check(200000000), 'low');
  });

  group('screen', () {
    late StreamController<List<Load>> loads;
    late LoadRadar radar;

    setUp(() {
      loads = StreamController<List<Load>>.broadcast();
      radar = LoadRadar(
        loads: loads.stream,
        vehicles: () async => [truck()],
        origin: () => delhi,
        driverId: () => 'd1',
        wavesOn: () => false,
      );
    });
    tearDown(() async {
      await loads.close();
    });

    Widget host(Widget home) => LanguageScope(notifier: languageNotifier, child: MaterialApp(theme: AppTheme.build(Brightness.light), home: home));

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.runAsync(radar.dispose);
    }

    Future<void> pump(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openCard(WidgetTester t, {required List<Load> initial, String? Function(Load, Vehicle)? accept, ValueChanged<String>? onAccepted}) async {
      languageNotifier.value = AppLanguage.english;
      radar.start();
      loads.add(initial);
      await pump(t);
      await t.pumpWidget(host(IncomingLoadScreen(
        radar: radar,
        onAccepted: onAccepted ?? (_) {},
        vehicles: () async => [truck()],
        accept: (l, v) async => accept?.call(l, v) ?? 'booking1',
        goneFor: const Duration(seconds: 2),
      )));
      await pump(t);
    }

    testWidgets('shows the route, the fare, the ring and the three actions', (t) async {
      t.view.physicalSize = const Size(360 * 2, 640 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await openCard(t, initial: [load('a')]);
      expect(find.text('New load near you'), findsOneWidget);
      expect(find.byKey(const ValueKey('ilRing')), findsOneWidget);
      expect(find.byKey(const ValueKey('ilFare')), findsOneWidget);
      expect(find.byKey(const ValueKey('ilSlide')), findsOneWidget);
      expect(find.byKey(const ValueKey('ilBid')), findsOneWidget);
      expect(find.byKey(const ValueKey('ilSkip')), findsOneWidget);
      await finish(t);
    });

    testWidgets('sliding to accept books the load and hands the booking id on', (t) async {
      t.view.physicalSize = const Size(360 * 2, 640 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      String? got;
      Load? accepted;
      await openCard(t, initial: [load('a')], onAccepted: (id) => got = id, accept: (l, v) {
        accepted = l;
        return 'b42';
      });
      await t.drag(find.byKey(const ValueKey('ilSlide')), const Offset(600, 0));
      await pump(t);
      expect(accepted?.id, 'a');
      expect(got, 'b42');
      await finish(t);
    });

    testWidgets('when someone else takes the load the card says so, then closes', (t) async {
      t.view.physicalSize = const Size(360 * 2, 640 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await openCard(t, initial: [load('a')]);
      loads.add(const []);
      await pump(t);
      expect(find.byKey(const ValueKey('ilGone')), findsOneWidget);
      expect(find.text('Someone else took this load'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await pump(t);
      expect(find.byKey(const ValueKey('ilGone')), findsNothing);
      expect(find.byKey(const ValueKey('ilFare')), findsNothing);
      await finish(t);
    });

    testWidgets('dark, 2.0x text and Hindi lay out without overflow', (t) async {
      t.view.physicalSize = const Size(360 * 2, 640 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      radar.start();
      loads.add([load('a')]);
      await pump(t);
      languageNotifier.value = AppLanguage.hindi;
      await t.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)), child: w!),
          home: IncomingLoadScreen(radar: radar, onAccepted: (_) {}, vehicles: () async => [truck()]),
        ),
      ));
      await pump(t);
      expect(t.takeException(), isNull);
      await finish(t);
    });
  });
}
