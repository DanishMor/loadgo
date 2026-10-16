import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/features/features.dart';
import 'package:transport_app/core/khata/khata_models.dart';
import 'package:transport_app/core/khata/khata_screens.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/features_service.dart';
import 'package:transport_app/core/services/khata_service.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/core/widgets/ds/app_button.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    languageNotifier.value = AppLanguage.english;
    FeaturesService.notifier.value = const Features(flags: {FeatureKey.khata: true});
  });
  tearDown(FeaturesService.reset);

  final now = DateTime(2026, 10, 17);

  group('money maths', () {
    test('owed adds, received takes away, in whole paise', () {
      final e = [
        KhataEntry(id: '1', kind: 'owed', amountPaise: 1500000, date: now),
        KhataEntry(id: '2', kind: 'received', amountPaise: 500000, date: now),
        KhataEntry(id: '3', kind: 'received', amountPaise: 1200000, date: now),
      ];
      expect(KhataBook.balance(e), -200000);
      expect(KhataBook.balance(const []), 0);
    });

    test('totals split what others owe from what I owe', () {
      final t = KhataBook.totals(const [
        KhataParty(id: 'a', name: 'A', balancePaise: 300000),
        KhataParty(id: 'b', name: 'B', balancePaise: -100000),
        KhataParty(id: 'c', name: 'C', balancePaise: 200000),
        KhataParty(id: 'd', name: 'D'),
      ]);
      expect((t.theyOwe, t.iOwe), (500000, 100000));
    });

    test('damaged documents read as zero, never as a crash', () {
      expect(KhataParty.fromDoc('x', {'name': 5, 'balancePaise': 'lots'}).balancePaise, 0);
      expect(KhataParty.fromDoc('x', {'balancePaise': 1 << 60}).balancePaise, 0);
      expect(KhataParty.fromDoc('x', null).name, '');
      expect(KhataEntry.fromDoc('x', {'amountPaise': -5, 'kind': 'weird'}).amountPaise, 0);
      expect(KhataEntry.fromDoc('x', {'kind': 'weird'}).kind, KhataEntryKind.owed);
    });

    test('the statement lists lines oldest first with the balance last', () {
      final text = KhataBook.statementText(
        partyName: 'Sharma Traders',
        entries: [
          KhataEntry(id: '2', kind: 'received', amountPaise: 500000, date: DateTime(2026, 10, 10), note: 'UPI'),
          KhataEntry(id: '1', kind: 'owed', amountPaise: 1500000, date: DateTime(2026, 10, 1)),
        ],
        money: (p) => 'Rs ${p ~/ 100}',
        date: (d) => '${d.day}/${d.month}',
      );
      expect(text.split('\n'), ['Sharma Traders', '1/10  Owed  Rs 15000', '10/10  Received  Rs 5000  (UPI)', 'Balance: Rs 10000']);
    });
  });

  group('service', () {
    test('an entry and the balance change together; deleting a line puts the balance back', () async {
      final id = await KhataService.addParty('  Sharma Traders ', note: 'Jaipur');
      await KhataService.addEntry(id, kind: 'owed', amountPaise: 1500000, date: now, now: now);
      await KhataService.addEntry(id, kind: 'received', amountPaise: 400000, date: now, now: now);
      var party = KhataParty.fromDoc(id, (await db.collection('users').doc('u1').collection('khata').doc(id).get()).data());
      expect(party.name, 'Sharma Traders');
      expect(party.balancePaise, 1100000);
      final entries = await KhataService.watchEntries(id).first;
      expect(entries.length, 2);
      expect(KhataBook.balance(entries), party.balancePaise);
      await KhataService.deleteEntry(id, entries.firstWhere((e) => e.kind == 'received'));
      party = KhataParty.fromDoc(id, (await db.collection('users').doc('u1').collection('khata').doc(id).get()).data());
      expect(party.balancePaise, 1500000);
      await KhataService.deleteParty(id);
      expect((await db.collection('users').doc('u1').collection('khata').get()).size, 0);
      expect((await db.collection('users').doc('u1').collection('khata').doc(id).collection('entries').get()).size, 0);
    });

    test('bad input is refused before anything is written', () async {
      final id = await KhataService.addParty('A');
      Future<void> bad(Future<void> f) async => expect(f, throwsA(anything));
      await bad(KhataService.addEntry(id, kind: 'gift', amountPaise: 100, date: now, now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: 0, date: now, now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: 12.5.toInt() - 13, date: now, now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: KhataEntry.maxPaise + 1, date: now, now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: 100, date: now.add(const Duration(days: 30)), now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: 100, date: now.subtract(const Duration(days: 2000)), now: now));
      await bad(KhataService.addEntry(id, kind: 'owed', amountPaise: 100, date: now, note: 'x' * 61, now: now));
      await bad(KhataService.addParty('   '));
      await bad(KhataService.addParty('x' * 41));
      await bad(KhataService.addParty('A', currentCount: 100));
      expect((await db.collection('users').doc('u1').collection('khata').doc(id).collection('entries').get()).size, 0);
    });

    test('each person has their own book', () async {
      await KhataService.addParty('Mine');
      Backend.useFakes(db: db, uid: () => 'u2');
      expect(await KhataService.watchParties().first, isEmpty);
    });
  });

  Widget app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: child);

  testWidgets('end to end: add a party, add a line, see the balance, delete the line', (tester) async {
    await tester.pumpWidget(app(const KhataScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No party yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('khataAddPartyButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('khataPartyName')), 'Sharma Traders');
    await tester.tap(find.byKey(const ValueKey('khataPartySave')));
    await tester.pumpAndSettle();
    expect(find.text('Sharma Traders'), findsOneWidget);
    expect(find.text('All settled'), findsOneWidget);

    await tester.tap(find.text('Sharma Traders'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('khataOwed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '15000');
    await tester.tap(find.byKey(const ValueKey('priceSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('They owe me'), findsWidgets);
    expect(find.textContaining('15,000'), findsWidgets);

    await tester.tap(find.byTooltip('Delete this line'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppButton).last);
    await tester.pumpAndSettle();
    expect(find.text('No lines yet. Tap one of the buttons above.'), findsOneWidget);
  });

  testWidgets('a narrow screen at big text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2.0)),
      child: app(KhataScreen(source: Stream.value(const [KhataParty(id: 'a', name: 'A very long party name for a transport company', note: 'Jaipur and Delhi both', balancePaise: 123456789)]))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
