import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/analytics/earnings_breakdown.dart';
import 'package:transport_app/core/analytics/spending_summary.dart';
import 'package:transport_app/core/l10n/earn_history_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/trip/trip_history.dart';
import 'package:transport_app/core/trip/trip_history_screen.dart';
import 'package:transport_app/core/widgets/mini_bars.dart';
import 'package:transport_app/customer/spending_screen.dart';
import 'package:transport_app/driver/earnings_view.dart';

import 'test_utils.dart';

/// Thursday 8 Oct 2026, 15:00; the week began Monday 5 Oct.
final now = DateTime(2026, 10, 8, 15);

final db = FakeFirebaseFirestore();
var _n = 0;

Future<Booking> mk({
  String status = 'delivered',
  int? paise = 100000,
  DateTime? at,
  String pickup = 'Delhi',
  String drop = 'Jaipur',
  String cargo = 'FMCG',
  String vehicle = 'DL01AB1234',
  DateTime? createdAt,
}) async {
  final id = 'b${_n++}';
  await db.collection('bookings').doc(id).set({
    'driverId': 'd1',
    'customerId': 'c1',
    'status': status,
    'pickup': pickup,
    'drop': drop,
    'cargoType': cargo,
    'vehicleNumber': vehicle,
    'agreedFarePaise': paise,
    'createdAt': Timestamp.fromDate(createdAt ?? at ?? DateTime(2026, 10, 1)),
    'timeline': {if (at != null) (status == 'cancelled' ? 'cancelled' : 'delivered'): Timestamp.fromDate(at)},
  });
  return Booking.fromDoc(await db.collection('bookings').doc(id).get());
}

Widget host(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

void main() {
  setUp(() => languageNotifier.value = AppLanguage.english);

  group('EarningsBreakdown', () {
    test('today, this week, last 7 days and total in paise', () async {
      final list = [
        await mk(paise: 100000, at: DateTime(2026, 10, 8, 9)), // today
        await mk(paise: 50000, at: DateTime(2026, 10, 5, 0, 0)), // Monday 00:00, this week
        await mk(paise: 70000, at: DateTime(2026, 10, 4, 23, 59)), // Sunday: last week, still in the last 7 days
        await mk(paise: 20000, at: DateTime(2026, 10, 2)), // 6 days ago: in the 7 days
        await mk(paise: 30000, at: DateTime(2026, 10, 1, 23)), // 7 days ago: out of the 7 days
        await mk(status: 'in_transit', paise: 999999),
        await mk(status: 'cancelled', paise: 999999, at: DateTime(2026, 10, 8)),
      ];
      final e = EarningsBreakdown.from(list, now);
      expect(e.todayPaise, 100000);
      expect(e.weekPaise, 150000);
      expect(e.last7Paise, 240000);
      expect(e.totalPaise, 270000);
      expect(e.trips, 5);
      expect(e.isEmpty, isFalse);
    });

    test('seven days, oldest first, the last is today', () async {
      final e = EarningsBreakdown.from([await mk(paise: 40000, at: DateTime(2026, 10, 6, 12)), await mk(paise: 10000, at: DateTime(2026, 10, 6, 13))], now);
      expect(e.last7Days.length, 7);
      expect(e.last7Days.first.day, DateTime(2026, 10, 2));
      expect(e.last7Days.last.day, DateTime(2026, 10, 8));
      final d6 = e.last7Days.firstWhere((d) => d.day == DateTime(2026, 10, 6));
      expect(d6.paise, 50000);
      expect(d6.trips, 2);
      expect(e.peakDayPaise, 50000);
      expect(e.last7Days.where((d) => d.trips == 0).length, 6);
    });

    test('weeks start on Monday and the last one is this week', () async {
      final e = EarningsBreakdown.from([
        await mk(paise: 10000, at: DateTime(2026, 10, 8)),
        await mk(paise: 20000, at: DateTime(2026, 10, 4, 23, 59)), // last week (Sep 28 - Oct 4)
        await mk(paise: 30000, at: DateTime(2026, 9, 29)),
        await mk(paise: 5000, at: DateTime(2026, 7, 1)), // older than 8 weeks: only in the total
      ], now);
      expect(e.weeks.length, 8);
      expect(e.weeks.last.weekStart, DateTime(2026, 10, 5));
      expect(e.weeks.last.paise, 10000);
      expect(e.weeks[6].weekStart, DateTime(2026, 9, 28));
      expect(e.weeks[6].paise, 50000);
      expect(e.weeks[6].trips, 2);
      expect(e.weeks.first.weekStart, DateTime(2026, 8, 17));
      expect(e.totalPaise, 65000);
    });

    test('a delivered trip without an amount is a trip worth 0; nothing at all is empty', () async {
      final noAmount = await mk(paise: null, at: DateTime(2026, 10, 8));
      expect(noAmount.billAmountPaise, isNull);
      final e = EarningsBreakdown.from([noAmount], now);
      expect(e.trips, 1);
      expect(e.todayPaise, 0);
      final none = EarningsBreakdown.from(const [], now);
      expect(none.isEmpty, isTrue);
      expect(none.peakDayPaise, 0);
      expect(none.weeks.length, 8);
    });

    test('just before and after midnight go to different days', () async {
      final e = EarningsBreakdown.from([
        await mk(paise: 100, at: DateTime(2026, 10, 7, 23, 59, 59)),
        await mk(paise: 200, at: DateTime(2026, 10, 8, 0, 0, 0)),
      ], now);
      expect(e.todayPaise, 200);
      expect(e.last7Days[5].paise, 100);
    });
  });

  group('TripHistoryFilter', () {
    late List<Booking> all;
    setUp(() async {
      all = [
        await mk(paise: 100000, at: DateTime(2026, 10, 8), vehicle: 'DL01AB1234'),
        await mk(paise: 200000, at: DateTime(2026, 10, 3), vehicle: 'MH12XY9999'),
        await mk(status: 'cancelled', paise: 300000, at: DateTime(2026, 10, 5), vehicle: 'DL01AB1234'),
        await mk(status: 'in_transit', paise: 400000, createdAt: DateTime(2026, 10, 7), vehicle: 'MH12XY9999'),
      ];
    });

    test('no filter keeps everything, newest first', () {
      const f = TripHistoryFilter();
      expect(f.isEmpty, isTrue);
      expect(f.apply(all).map((b) => b.id), [all[0].id, all[3].id, all[2].id, all[1].id]);
    });

    test('status groups', () {
      expect(const TripHistoryFilter(statuses: {HistoryStatus.delivered}).apply(all).length, 2);
      expect(const TripHistoryFilter(statuses: {HistoryStatus.cancelled}).apply(all).single.id, all[2].id);
      expect(const TripHistoryFilter(statuses: {HistoryStatus.active}).apply(all).single.id, all[3].id);
      expect(const TripHistoryFilter(statuses: {HistoryStatus.cancelled, HistoryStatus.active}).apply(all).length, 2);
    });

    test('date range is inclusive of whole days and uses the delivery / cancel day', () {
      final f = TripHistoryFilter(from: DateTime(2026, 10, 3), to: DateTime(2026, 10, 5));
      expect(f.apply(all).map((b) => b.id).toSet(), {all[1].id, all[2].id});
      expect(TripHistoryFilter(from: DateTime(2026, 10, 8, 23)).apply(all).single.id, all[0].id);
      expect(TripHistoryFilter(to: DateTime(2026, 10, 2)).apply(all), isEmpty);
    });

    test('vehicles', () {
      expect(const TripHistoryFilter(vehicles: {'DL01AB1234'}).apply(all).length, 2);
      expect(const TripHistoryFilter(vehicles: {'DL01AB1234', 'MH12XY9999'}).apply(all).length, 4);
      expect(const TripHistoryFilter(vehicles: {'KA01'}).apply(all), isEmpty);
      expect(TripHistoryFilter.vehicleNumbers(all), ['DL01AB1234', 'MH12XY9999']);
    });

    test('all filters together', () {
      final f = TripHistoryFilter(statuses: {HistoryStatus.delivered}, vehicles: {'DL01AB1234'}, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
      expect(f.apply(all).single.id, all[0].id);
    });

    test('copyWith can clear a date', () {
      var f = TripHistoryFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 2));
      f = f.copyWith(from: null);
      expect(f.from, isNull);
      expect(f.to, DateTime(2026, 10, 2));
      expect(f.copyWith(statuses: {HistoryStatus.active}).to, DateTime(2026, 10, 2));
    });

    test('CSV: header, rupees from paise, quoting and empty values', () async {
      final tricky = await mk(paise: 123456, at: DateTime(2026, 10, 8), pickup: 'A, B', drop: 'The "Big" Yard', cargo: 'Tiles', vehicle: '');
      final noAmount = await mk(paise: null, at: DateTime(2026, 10, 7));
      final csv = TripHistoryFilter.toCsv([tricky, noAmount]).split('\n');
      expect(csv[0], 'date,status,pickup,drop,cargo,vehicle,amount_rupees');
      expect(csv[1], '2026-10-08,delivered,"A, B","The ""Big"" Yard",Tiles,,1234.56');
      expect(csv[2], '2026-10-07,delivered,Delhi,Jaipur,FMCG,DL01AB1234,');
      expect(TripHistoryFilter.toCsv(const []), 'date,status,pickup,drop,cargo,vehicle,amount_rupees');
    });
  });

  group('SpendingSummary', () {
    test('six months oldest first across a year end, only delivered trips', () async {
      final n = DateTime(2027, 2, 10);
      final list = [
        await mk(paise: 100000, at: DateTime(2027, 2, 1)),
        await mk(paise: 50000, at: DateTime(2027, 2, 9)),
        await mk(paise: 70000, at: DateTime(2026, 12, 31, 23)),
        await mk(paise: 20000, at: DateTime(2026, 9, 15)), // before the 6 months: total only
        await mk(status: 'cancelled', paise: 888888, at: DateTime(2027, 2, 2)),
        await mk(status: 'accepted', paise: 888888),
      ];
      final s = SpendingSummary.from(list, n);
      expect(s.months.map((m) => m.key), ['2026-09', '2026-10', '2026-11', '2026-12', '2027-01', '2027-02']);
      expect(s.months.last.paise, 150000);
      expect(s.months.last.trips, 2);
      expect(s.months[3].paise, 70000);
      expect(s.months.first.paise, 20000);
      expect(s.totalPaise, 240000);
      expect(s.trips, 4);
      expect(s.peakMonthPaise, 150000);
    });

    test('a month by cargo and by route, biggest first, ties by name, routes normalised', () async {
      final list = [
        await mk(paise: 100000, at: DateTime(2026, 10, 2), cargo: 'FMCG', pickup: 'Delhi', drop: 'Jaipur'),
        await mk(paise: 40000, at: DateTime(2026, 10, 3), cargo: 'FMCG', pickup: 'new delhi', drop: 'JAIPUR'),
        await mk(paise: 90000, at: DateTime(2026, 10, 4), cargo: 'Steel', pickup: 'Mumbai', drop: 'Pune'),
        await mk(paise: 90000, at: DateTime(2026, 10, 5), cargo: 'Cement', pickup: 'Surat', drop: 'Pune'),
        await mk(paise: 5000, at: DateTime(2026, 10, 6), cargo: '  ', pickup: 'Surat', drop: 'Pune'),
        await mk(paise: 7000, at: DateTime(2026, 9, 6), cargo: 'Steel'),
      ];
      final m = SpendingSummary.from(list, now).forMonth('2026-10');
      expect(m.totalPaise, 325000);
      expect(m.trips, 5);
      expect([for (final c in m.byCargo) '${c.label}:${c.paise}:${c.trips}'], ['FMCG:140000:2', 'Cement:90000:1', 'Steel:90000:1', '-:5000:1']);
      expect(m.byRoute.first.label, 'Delhi → Jaipur');
      expect(m.byRoute.first.paise, 140000);
      expect(m.byRoute.first.trips, 2);
      expect(m.byRoute.map((r) => r.label), ['Delhi → Jaipur', 'Surat → Pune', 'Mumbai → Pune']);
      expect(m.byRoute[1].paise, 95000);
      expect(m.byRoute.last.paise, 90000);
    });

    test('a month without trips is empty; any month key works', () async {
      final s = SpendingSummary.from([await mk(paise: 100, at: DateTime(2026, 10, 2))], now);
      final empty = s.forMonth('2026-08');
      expect(empty.isEmpty, isTrue);
      expect(empty.byCargo, isEmpty);
      expect(empty.totalPaise, 0);
      expect(SpendingSummary.from(const [], now).months.length, 6);
      expect(monthKeyOf(DateTime(2026, 3, 9)), '2026-03');
    });
  });

  group('MiniBars', () {
    testWidgets('the tallest bar fills the height, zero is a thin line', (t) async {
      await t.pumpWidget(host(const Scaffold(
        body: Center(child: SizedBox(width: 300, child: MiniBars(height: 100, bars: [MiniBar('a', 50, 'a'), MiniBar('b', 100, 'b'), MiniBar('c', 0, 'c')]))),
      )));
      double h(int i) => t.getSize(find.byKey(ValueKey('bar_$i'))).height;
      expect(h(1), 100);
      expect(h(0), closeTo(2 + 98 * 0.5, 0.01));
      expect(h(2), 2);
    });

    testWidgets('all zero stays flat', (t) async {
      await t.pumpWidget(host(const Scaffold(body: MiniBars(bars: [MiniBar('a', 0, ''), MiniBar('b', 0, '')]))));
      expect(t.getSize(find.byKey(const ValueKey('bar_0'))).height, 2);
    });
  });

  group('TripHistoryScreen', () {
    late List<Booking> all;
    setUp(() async {
      all = [
        await mk(paise: 100000, at: DateTime(2026, 10, 8), vehicle: 'DL01AB1234', pickup: 'Pune', drop: 'Mumbai'),
        await mk(paise: 200000, at: DateTime(2026, 10, 3), vehicle: 'MH12XY9999', pickup: 'Surat', drop: 'Vapi'),
        await mk(status: 'cancelled', paise: 300000, at: DateTime(2026, 10, 5), vehicle: 'DL01AB1234', pickup: 'Agra', drop: 'Noida'),
      ];
    });

    Future<void> open(WidgetTester t, {List<Booking>? list, Future<void> Function(String, String)? share, Future<DateTimeRange?> Function(BuildContext, DateTimeRange?)? pick, void Function(String)? onOpen}) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(TripHistoryScreen(bookings: () => Stream.value(list ?? all), onOpen: onOpen ?? (_) {}, share: share, pickRange: pick)));
      await settle(t);
    }

    testWidgets('lists everything, newest first, with a count', (t) async {
      await open(t);
      expect(find.text('3 trips'), findsOneWidget);
      expect(find.byKey(ValueKey('hist_${all[0].id}')), findsOneWidget);
      expect(t.getTopLeft(find.byKey(ValueKey('hist_${all[0].id}'))).dy, lessThan(t.getTopLeft(find.byKey(ValueKey('hist_${all[2].id}'))).dy));
      expect(find.text('₹ 1,000'), findsOneWidget);
    });

    testWidgets('status chips filter and the clear chip resets', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('hist_cancelled')));
      await t.pumpAndSettle();
      expect(find.text('1 trips'), findsOneWidget);
      expect(find.byKey(ValueKey('hist_${all[2].id}')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hist_delivered')));
      await t.pumpAndSettle();
      expect(find.text('3 trips'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hist_clear')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hist_clear')), findsNothing);
    });

    testWidgets('vehicle chips appear when there are several vehicles', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('hist_vehicle_MH12XY9999')));
      await t.pumpAndSettle();
      expect(find.text('1 trips'), findsOneWidget);
      expect(find.byKey(ValueKey('hist_${all[1].id}')), findsOneWidget);
    });

    testWidgets('no vehicle chips with a single vehicle', (t) async {
      await open(t, list: [all[0]]);
      expect(find.byKey(const ValueKey('hist_vehicle_DL01AB1234')), findsNothing);
    });

    testWidgets('date range from the picker', (t) async {
      await open(t, pick: (c, cur) async => DateTimeRange(start: DateTime(2026, 10, 3), end: DateTime(2026, 10, 5)));
      await t.tap(find.byKey(const ValueKey('hist_range')));
      await t.pumpAndSettle();
      expect(find.text('2 trips'), findsOneWidget);
      expect(find.byKey(ValueKey('hist_${all[0].id}')), findsNothing);
    });

    testWidgets('no match shows an empty state with a clear action; no trips at all shows another', (t) async {
      await open(t, pick: (c, cur) async => DateTimeRange(start: DateTime(2020), end: DateTime(2020, 1, 2)));
      await t.tap(find.byKey(const ValueKey('hist_range')));
      await t.pumpAndSettle();
      expect(find.text('No trips match these filters'), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const ValueKey('hist_share'))).onPressed, isNull);
      await t.tap(find.widgetWithText(TextButton, 'Clear'));
      await t.pumpAndSettle();
      expect(find.text('3 trips'), findsOneWidget);
    });

    testWidgets('no trips at all has its own empty state', (t) async {
      await open(t, list: const []);
      expect(find.text('No trips yet'), findsOneWidget);
    });

    testWidgets('share sends the CSV of what is shown', (t) async {
      String? csv, subject;
      await open(t, share: (c, s) async {
        csv = c;
        subject = s;
      });
      await t.tap(find.byKey(const ValueKey('hist_cancelled')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('hist_share')));
      await t.pumpAndSettle();
      expect(csv!.split('\n').length, 2);
      expect(csv, contains('cancelled,Agra,Noida'));
      expect(subject, 'LoadGo trip history');
    });

    testWidgets('a failing share shows a message instead of crashing', (t) async {
      await open(t, share: (c, s) async => throw Exception('no share'));
      await t.tap(find.byKey(const ValueKey('hist_share')));
      await t.pumpAndSettle();
      expect(find.text('Could not open this'), findsOneWidget);
    });

    testWidgets('tapping a trip opens it', (t) async {
      String? opened;
      await open(t, onOpen: (id) => opened = id);
      await t.tap(find.byKey(ValueKey('hist_${all[1].id}')));
      expect(opened, all[1].id);
    });
  });

  group('SpendingScreen', () {
    late List<Booking> all;
    setUp(() async {
      all = [
        await mk(paise: 150000, at: DateTime(2026, 10, 2), cargo: 'FMCG', pickup: 'Delhi', drop: 'Jaipur'),
        await mk(paise: 50000, at: DateTime(2026, 10, 5), cargo: 'Steel', pickup: 'Delhi', drop: 'Jaipur'),
        await mk(paise: 70000, at: DateTime(2026, 8, 5), cargo: 'Steel', pickup: 'Surat', drop: 'Pune'),
      ];
    });

    Future<void> open(WidgetTester t, List<Booking> list) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(SpendingScreen(bookings: () => Stream.value(list), now: () => now)));
      await settle(t);
    }

    testWidgets('this month first, with cargo and route lines', (t) async {
      await open(t, all);
      expect(find.byKey(const ValueKey('spendTotal')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('spendTotal'))).data, '₹ 2,000');
      expect(find.text('Spent in 10/2026'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('spendCargo_0'))).data, '₹ 1,500');
      expect(find.text('Delhi → Jaipur'), findsOneWidget);
    });

    testWidgets('choosing another month switches the figures', (t) async {
      await open(t, all);
      await t.tap(find.byKey(const ValueKey('spendMonth_2026-08')));
      await t.pumpAndSettle();
      expect(find.text('Spent in 08/2026'), findsOneWidget);
      expect(find.text('₹ 700'), findsWidgets);
      expect(find.text('Surat → Pune'), findsOneWidget);
      expect(find.text('Delhi → Jaipur'), findsNothing);
    });

    testWidgets('a month without spending shows an empty state', (t) async {
      await open(t, all);
      await t.tap(find.byKey(const ValueKey('spendMonth_2026-09')));
      await t.pumpAndSettle();
      expect(find.text('Nothing spent in this month'), findsOneWidget);
      expect(find.text('₹ 0'), findsOneWidget);
    });

    testWidgets('six month bars with the chosen month highlighted', (t) async {
      await open(t, all);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('spendBar_$i')), findsOneWidget);
      }
      expect(t.getSize(find.byKey(const ValueKey('spendBar_5'))).height, greaterThan(t.getSize(find.byKey(const ValueKey('spendBar_2'))).height));
    });

    testWidgets('nothing at all: zero everywhere, no crash', (t) async {
      await open(t, const []);
      expect(find.text('Nothing spent in this month'), findsOneWidget);
    });

    testWidgets('fits 360x640 at 1.6x text', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
        home: LanguageScope(notifier: languageNotifier, child: SpendingScreen(bookings: () => Stream.value(all), now: () => now)),
      ));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  });

  group('driver earnings tab', () {
    testWidgets('shows today, last 7 days, bars and opens the history', (t) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final list = [await mk(paise: 250000, at: DateTime(2026, 10, 8, 9)), await mk(paise: 100000, at: DateTime(2026, 10, 6))];
      await t.pumpWidget(host(Scaffold(body: EarningsView(bookings: () => Stream.value(list), onOpenTrip: (_) {}, now: () => now))));
      await settle(t);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('₹ 2,500'), findsOneWidget);
      expect(find.text('₹ 3,500'), findsOneWidget);
      expect(find.byKey(const ValueKey('earnBar_6')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('openHistory')));
      await t.pumpAndSettle();
      expect(find.byType(TripHistoryScreen), findsOneWidget);
    });
  });

  group('strings', () {
    test('every key has 12 non-empty languages and the same placeholders', () {
      final ph = RegExp(r'\{(\w+)\}');
      for (final e in earnHistoryStrings.entries) {
        expect(e.value.length, 12, reason: e.key);
        expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
        final want = ph.allMatches(e.value[0]).map((m) => m[1]).toSet();
        for (var i = 1; i < 12; i++) {
          expect(ph.allMatches(e.value[i]).map((m) => m[1]).toSet(), want, reason: '${e.key}/$i');
        }
      }
    });
  });
}
