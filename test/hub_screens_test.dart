import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/ledger_entry.dart';
import 'package:transport_app/core/models/payout.dart';
import 'package:transport_app/core/offers/promo.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/transporter/transporter_logic.dart';
import 'package:transport_app/core/wallet/hub/hub_screens.dart';
import 'package:transport_app/core/widgets/error_boundary.dart';

/// F9 and F10: the three hubs, their states and the error boundary.
Widget host(Widget screen, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1.0, bool lowEnd = false}) {
  final language = ValueNotifier(lang);
  final dir = (lang == AppLanguage.urdu || lang == AppLanguage.kashmiri) ? TextDirection.rtl : TextDirection.ltr;
  return LanguageScope(
    notifier: language,
    child: MaterialApp(
      theme: AppTheme.build(b, lowEnd: lowEnd),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: screen,
    ),
  );
}

final now = DateTime(2026, 10, 14, 15);

Booking booking(String id, String status, {String payment = 'pending', int? fare}) => Booking(
      id: id, loadId: 'L', driverId: 'd1', vehicleId: 'v', customerId: 'c1', status: status, pickup: 'Pune', drop: 'Delhi',
      cargoType: 'x', weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1',
      driverName: 'Ravi', driverPhone: '', timeline: {BookingStatus.delivered: DateTime(2026, 10, 14, 9)}, paymentStatus: payment, paidAmountPaise: fare,
    );

final ledger = [
  LedgerEntry(id: 'B1_trip_earning', driverId: 'd1', bookingId: 'B1', type: LedgerType.tripEarning, amountPaise: 100000, createdAt: DateTime(2026, 10, 14, 9)),
  LedgerEntry(id: 'B1_platform_commission', driverId: 'd1', bookingId: 'B1', type: LedgerType.platformCommission, amountPaise: -10000, createdAt: DateTime(2026, 10, 14, 9)),
];

DriverHubScreen driver({List<LedgerEntry>? entries, List<Booking>? bookings, List<Payout>? payouts, Stream<List<LedgerEntry>> Function()? ledgerStream}) => DriverHubScreen(
      ledger: ledgerStream ?? () => Stream.value(entries ?? ledger),
      bookings: () => Stream.value(bookings ?? [booking('b1', BookingStatus.delivered, fare: 40000)]),
      payouts: () => Stream.value(payouts ?? const []),
      now: () => now,
    );

void main() {
  group('driver hub', () {
    testWidgets('amounts start hidden, the eye shows them, and the request button is ready', (t) async {
      await t.pumpWidget(host(driver()));
      await t.pumpAndSettle();
      expect(find.text('₹ ••••'), findsWidgets);
      expect(find.textContaining('900'), findsNothing, reason: 'nothing readable while hidden');
      await t.tap(find.byTooltip('Show amount'));
      await t.pumpAndSettle();
      expect(find.text('₹ ••••'), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('hubAvailable')), matching: find.text('₹ 900')), findsOneWidget);
      expect(find.byKey(const ValueKey('hubRequestPayout')), findsOneWidget);
      expect(find.byKey(const ValueKey('stage_hubStageCustomer')), findsOneWidget);
      expect(find.byKey(const ValueKey('stage_hubStagePaid')), findsOneWidget);
      await t.tap(find.byTooltip('Hide amount'));
      await t.pumpAndSettle();
      expect(find.text('₹ ••••'), findsWidgets);
    });

    testWidgets('an empty account says so kindly and keeps the road visible only when there is data', (t) async {
      await t.pumpWidget(host(driver(entries: const [], bookings: const [])));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hubEmpty')), findsOneWidget);
      expect(find.text(T.get('hubEmptyDriver', AppLanguage.english)), findsOneWidget);
    });

    testWidgets('pull to refresh asks the streams again', (t) async {
      var calls = 0;
      await t.pumpWidget(host(driver(ledgerStream: () {
        calls++;
        return Stream.value(ledger);
      })));
      await t.pumpAndSettle();
      final first = calls;
      await t.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(calls, greaterThan(first));
    });

    testWidgets('a failing stream shows a friendly message with Retry, never the exception', (t) async {
      var attempt = 0;
      await t.pumpWidget(host(driver(ledgerStream: () {
        attempt++;
        return attempt == 1 ? Stream<List<LedgerEntry>>.error(StateError('secret internals 9876543210')) : Stream.value(ledger);
      })));
      await t.pumpAndSettle();
      expect(find.textContaining('secret internals'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hubAvailable')), findsOneWidget);
    });

    testWidgets('while the first data is on its way a skeleton shows', (t) async {
      final c = StreamController<List<LedgerEntry>>();
      addTearDown(c.close);
      await t.pumpWidget(host(driver(ledgerStream: () => c.stream)));
      await t.pump();
      expect(find.bySemanticsLabel('Loading'), findsOneWidget, reason: 'the skeleton is announced as Loading');
      expect(find.byKey(const ValueKey('hubAvailable')), findsNothing);
      c.add(ledger);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('hubAvailable')), findsOneWidget);
    });
  });

  group('customer hub', () {
    CustomerHubScreen customer({List<Booking>? bookings, List<CreditLine>? credits}) => CustomerHubScreen(
          bookings: () => Stream.value(bookings ?? [booking('b1', BookingStatus.delivered, fare: 100000)]),
          credits: () => Stream.value(credits ?? [CreditLine(id: 'c1', amountPaise: 20000, kind: 'referral', createdAt: DateTime(2026, 10, 1))]),
          now: () => now,
        );

    testWidgets('credits and spending, hidden first', (t) async {
      await t.pumpWidget(host(customer()));
      await t.pumpAndSettle();
      expect(find.text('₹ ••••'), findsWidgets);
      await t.tap(find.byTooltip('Show amount'));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('hubCredits')), matching: find.text('₹ 200')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hubSpentMonth')), matching: find.text('₹ 1,000')), findsOneWidget);
    });

    testWidgets('nothing yet', (t) async {
      await t.pumpWidget(host(customer(bookings: const [], credits: const [])));
      await t.pumpAndSettle();
      expect(find.text(T.get('hubEmptyCustomer', AppLanguage.english)), findsOneWidget);
    });
  });

  group('transporter hub', () {
    TransporterHubScreen transporter(List<TripAccount> a) => TransporterHubScreen(accounts: () => Stream.value(a));

    testWidgets('party ledger with margin', (t) async {
      await t.pumpWidget(host(transporter(const [TripAccount(bookingId: 'a', partyId: 'p1', partyName: 'Shree Traders', revenuePaise: 100000, driverPayPaise: 70000, receivedPaise: 40000)])));
      await t.pumpAndSettle();
      expect(find.text('Shree Traders'), findsOneWidget);
      expect(find.byKey(const ValueKey('hubParty_p1')), findsOneWidget);
      expect(find.text('1 trips'), findsOneWidget);
    });

    testWidgets('no accounts yet', (t) async {
      await t.pumpWidget(host(transporter(const [])));
      await t.pumpAndSettle();
      expect(find.text(T.get('hubEmptyTransporter', AppLanguage.english)), findsOneWidget);
    });
  });

  group('error boundary', () {
    testWidgets('a builder that throws becomes a friendly message with Retry; Retry rebuilds', (t) async {
      var fail = true;
      await t.pumpWidget(host(Scaffold(body: ErrorBoundary(builder: (_) {
        if (fail) throw FormatException('bad data 9876543210');
        return const Text('fine now');
      }))));
      expect(find.byKey(const ValueKey('errorBoundary')), findsOneWidget);
      expect(find.textContaining('FormatException'), findsNothing);
      expect(find.textContaining('9876543210'), findsNothing);
      fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('fine now'), findsOneWidget);
    });

    testWidgets('a ledger line of the wrong type does not take the screen down', (t) async {
      // The parser of the stream turns odd documents into zeros; here the hub is fed the result.
      await t.pumpWidget(host(driver(entries: [
        LedgerEntry(id: 'x', driverId: '', bookingId: '', type: '???', amountPaise: 0, createdAt: DateTime(1970)),
      ], bookings: const [])));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('hubAvailable')), findsOneWidget);
    });
  });

  group('layout: every hub at 360x640, 2.0x text, light and dark, Hindi and Urdu (RTL), Low-end', () {
    final screens = <String, Widget Function()>{
      'driver': () => driver(
            bookings: [booking('b1', BookingStatus.delivered, fare: 40000)],
            payouts: [const Payout(id: 'p1', driverId: 'd1', amountPaise: 30000, status: Payout.requested), const Payout(id: 'p2', driverId: 'd1', amountPaise: 12345678, status: Payout.paid)],
          ),
      'customer': () => CustomerHubScreen(
            bookings: () => Stream.value([booking('b1', BookingStatus.delivered, fare: 987654321)]),
            credits: () => Stream.value([CreditLine(id: 'c1', amountPaise: 20000, kind: 'referral', note: 'Referral bonus from a friend with a long name', createdAt: DateTime(2026, 10, 1))]),
            now: () => now,
          ),
      'transporter': () => TransporterHubScreen(accounts: () => Stream.value(const [
            TripAccount(bookingId: 'a', partyId: 'p1', partyName: 'Shree Balaji Roadlines and Cargo Movers Private Limited', revenuePaise: 123456789, driverPayPaise: 70000000, receivedPaise: 40000),
          ])),
    };
    for (final lang in [AppLanguage.english, AppLanguage.hindi, AppLanguage.urdu]) {
      for (final b in Brightness.values) {
        for (final e in screens.entries) {
          testWidgets('${e.key} ${lang.name} ${b.name}', (t) async {
            t.view.physicalSize = const Size(360, 640);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            await t.pumpWidget(host(e.value(), lang: lang, b: b, scale: 2.0, lowEnd: lang == AppLanguage.hindi));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await t.tap(find.byTooltip(T.get('dsShowAmount', lang)));
            await t.pumpAndSettle();
            await t.drag(find.byType(ListView).first, const Offset(0, -4000));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });
}
