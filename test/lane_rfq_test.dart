import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/enterprise/lane_rfq.dart';
import 'package:transport_app/core/enterprise/lane_rfq_screens.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/theme/app_theme.dart';

final now = DateTime(2027, 5, 20, 12);
LaneRfq rfq(String id, {String status = 'open', String owner = 'biz1', DateTime? closes}) => LaneRfq(
    id: id, ownerId: owner, ownerName: 'Shah', fromCity: 'Surat', toCity: 'Delhi', vehicleType: '32ft', tripsPerMonth: 20, months: 3, status: status, closesAt: closes ?? now.add(const Duration(days: 5)));

/// E30: lane tenders (flag laneRfq).
void main() {
  late FakeFirebaseFirestore db;
  String? uid = 'biz1';
  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'biz1';
    Backend.useFakes(db: db, uid: () => uid);
    languageNotifier.value = AppLanguage.english;
  });

  test('model parses defensively; bids rank lowest first, then earliest', () {
    final r = LaneRfq.fromMap('R', {'status': 'weird', 'tripsPerMonth': 'x', 'months': 3});
    expect((r.status, r.tripsPerMonth, r.months), ('closed', 0, 3));
    expect(LaneBid.fromMap('a', {'ratePaise': 0}), isNull);
    final ranked = rankBids([
      LaneBid(bidderId: 'b', bidderName: 'B', ratePaise: 500, at: DateTime(2027, 1, 2)),
      LaneBid(bidderId: 'a', bidderName: 'A', ratePaise: 500, at: DateTime(2027, 1, 1)),
      const LaneBid(bidderId: 'c', bidderName: 'C', ratePaise: 300),
    ]);
    expect(ranked.map((b) => b.bidderId), ['c', 'a', 'b']);
    expect(rfq('R').openAt(now), isTrue);
    expect(rfq('R', closes: now.subtract(const Duration(minutes: 1))).openAt(now), isFalse);
    expect(rfq('R').totalTrips, 60);
  });

  test('service writes exactly the fields the rules allow', () async {
    final id = await LaneRfqService.create(ownerName: 'Shah', fromCity: ' Surat ', toCity: 'Delhi', vehicleType: '32ft', tripsPerMonth: 20, months: 3, closesAt: now);
    final d = (await db.doc('lane_rfqs/$id').get()).data()!;
    expect(d.keys.toSet(), {'ownerId', 'ownerName', 'fromCity', 'toCity', 'vehicleType', 'tripsPerMonth', 'months', 'note', 'closesAt', 'status', 'createdAt'});
    expect((d['fromCity'], d['status']), ('Surat', 'open'));
    uid = 'flt1';
    await LaneRfqService.placeBid(id, bidderName: 'Co', ratePaise: 6500000);
    final b = (await db.doc('lane_rfqs/$id/bids/flt1').get()).data()!;
    expect(b.keys.toSet(), {'bidderId', 'bidderName', 'ratePaise', 'note', 'at'});
    expect((await LaneRfqService.myBid(id))!.ratePaise, 6500000);
    uid = 'biz1';
    await LaneRfqService.award(id, (await LaneRfqService.watchBids(id).first).single);
    final after = (await db.doc('lane_rfqs/$id').get()).data()!;
    expect((after['status'], after['awardedTo'], after['awardedRatePaise']), ('awarded', 'flt1', 6500000));
    expect(after['decidedAt'], isA<Timestamp>());
  });

  Widget host(Widget child, {AppLanguage lang = AppLanguage.english, Brightness b = Brightness.light, double scale = 1}) => LanguageScope(
        notifier: ValueNotifier(lang),
        child: MaterialApp(
          theme: AppTheme.build(b, style: ThemeStyle.signature),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: lang.textDirection, child: w!)),
          home: child,
        ),
      );

  testWidgets('owner: bids lowest first; award asks first and records the chosen bid', (t) async {
    LaneBid? awarded;
    await t.pumpWidget(host(LaneTenderBidsScreen(
      rfq: rfq('R1'),
      bids: (_) => Stream.value(rankBids(const [
        LaneBid(bidderId: 'flt2', bidderName: 'Gupta Roadlines', ratePaise: 7000000),
        LaneBid(bidderId: 'flt1', bidderName: 'Singh Transport', ratePaise: 6400000),
      ])),
      award: (id, b) async => awarded = b,
    )));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('tdrBid_flt1'))).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('tdrBid_flt2'))).dy));
    await t.tap(find.byKey(const ValueKey('tdrAward_flt1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tdrConfirm')));
    await t.pumpAndSettle();
    expect(awarded!.bidderId, 'flt1');
  });

  testWidgets('bidder: only open tenders of others; a rate is sent in paise', (t) async {
    int? sent;
    await t.pumpWidget(host(OpenTendersScreen(
      bidderName: 'Co',
      myUid: 'flt1',
      open: () => Stream.value([rfq('R1'), rfq('R2', owner: 'flt1'), rfq('R3', closes: now.subtract(const Duration(hours: 1)))]),
      place: (id, p, n) async => sent = p,
      now: () => now,
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('lr_R1')), findsOneWidget);
    expect(find.byKey(const ValueKey('lr_R2')), findsNothing);
    expect(find.byKey(const ValueKey('lr_R3')), findsNothing);
    await t.tap(find.byKey(const ValueKey('tdrBidOn_R1')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('tdrRate')), '64000');
    await t.tap(find.byKey(const ValueKey('tdrSendRate')));
    await t.pumpAndSettle();
    expect(sent, 6400000);
  });

  testWidgets('owner list: empty state, and a tender opens its bids', (t) async {
    await t.pumpWidget(host(LaneTendersScreen(ownerName: 'Shah', mine: () => Stream.value(const []))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tdrNone')), findsOneWidget);
    expect(find.byKey(const ValueKey('tdrNew')), findsOneWidget);
  });

  for (final (lang, b) in [(AppLanguage.hindi, Brightness.light), (AppLanguage.urdu, Brightness.dark), (AppLanguage.tamil, Brightness.dark)]) {
    testWidgets('no overflow at 320 dp and 2.0x: ${lang.name} ${b.name}', (t) async {
      t.view.physicalSize = const Size(320, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(OpenTendersScreen(bidderName: 'Co', open: () => Stream.value([rfq('R1')]), now: () => now), lang: lang, b: b, scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(host(
          LaneTenderBidsScreen(rfq: rfq('R1'), bids: (_) => Stream.value(const [LaneBid(bidderId: 'flt1', bidderName: 'Singh Transport Company', ratePaise: 6400000, note: 'AC cabin, GPS')])),
          lang: lang,
          b: b,
          scale: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
