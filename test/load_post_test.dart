import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/constants/logistics.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/load_service.dart';
import 'package:transport_app/core/widgets/common.dart';
import 'package:transport_app/customer/my_loads_view.dart';
import 'package:transport_app/customer/post_load_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'customer1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  Future<String> postSample({String pickup = 'Delhi', num? budget = 25000}) => LoadService.post(
        pickup: pickup,
        drop: 'Mumbai',
        cargoType: 'FMCG',
        weight: 8,
        vehicleType: '20ft',
        budget: budget,
        pickupDate: DateTime(2026, 10, 5, 15, 30),
        notes: ' fragile ',
      );

  test('post stores an open load for the signed-in shipper', () async {
    final id = await postSample();
    final d = (await db.collection('loads').doc(id).get()).data()!;
    expect(d['shipperId'], 'customer1');
    expect(d['status'], LoadStatus.open);
    expect(d['weight'], 8);
    expect(d['budget'], 25000);
    expect(d['notes'], 'fragile');
    expect(d['createdAt'], isNotNull);
    // Pickup date is stored as a date (time stripped).
    expect(LoadService.watchMine(), emits(predicate<List>((l) => l.single.pickupDate == DateTime(2026, 10, 5))));
  });

  test('watchMine returns only my loads; budget can be null', () async {
    await postSample(pickup: 'Pune', budget: null);
    uid = 'customer2';
    await postSample(pickup: 'Jaipur');
    uid = 'customer1';
    final mine = await LoadService.watchMine().first;
    expect(mine.map((l) => l.pickup), ['Pune']);
    expect(mine.single.budget, isNull);
  });

  testWidgets('MASTER-5 Task 31: the form reads as three numbered steps', (tester) async {
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: PostLoadScreen())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('postStep1')), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('postStep3')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('postStep2')), findsOneWidget);
  });

  testWidgets('MASTER-5 Task 19: leaving with something typed asks first; an untouched form just closes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('home')))));
    nav.currentState!.push<void>(MaterialPageRoute(builder: (_) => const PostLoadScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsOneWidget);

    // nothing typed: back closes at once
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsNothing);

    // something typed: back asks; Keep editing stays, Leave closes
    nav.currentState!.push<void>(MaterialPageRoute(builder: (_) => const PostLoadScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Delhi');
    await tester.pump();
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Leave without posting?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('keepEditing')));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsOneWidget);
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discardLoad')));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsNothing);
  });

  testWidgets('post load form validates and the load shows in My Loads', (tester) async {
    // Push the form on top of a page, like the real app does, so pop() works.
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold()));
    final result = nav.currentState!.push<bool>(MaterialPageRoute(builder: (_) => const PostLoadScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsWidgets);
    expect((await db.collection('loads').get()).docs, isEmpty);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Delhi');
    await tester.enterText(fields.at(1), 'Mumbai');
    await tester.enterText(fields.at(2), '3');
    // Pick a date via the date picker.
    await tester.ensureVisible(find.byIcon(Icons.calendar_today_rounded));
    await tester.tap(find.byIcon(Icons.calendar_today_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(PrimaryButton));
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    final docs = (await db.collection('loads').get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single['budget'], isNull);
    // Delhi -> Mumbai is in the offline city table, so an estimate is stored.
    expect(find.byKey(const ValueKey('fareTotal')), findsNothing, reason: 'form closed');
    expect((docs.single['estimate'] as Map)['total'], greaterThan(0));
    expect((docs.single['estimate'] as Map)['distanceSource'], 'cities');
    expect(await result, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MyLoadsView(onPostLoad: () {}, onOpenBooking: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delhi → Mumbai'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });
}
