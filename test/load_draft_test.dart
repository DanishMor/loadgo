import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/drafts/load_draft.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/customer/post_load_screen.dart';

/// MASTER-6 Task 15: save and resume an unfinished load.
void main() {
  String? uid;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    uid = 'c1';
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => uid);
  });

  final now = DateTime(2026, 10, 9, 12);

  test('worth saving once a place or a weight is typed; expires after 7 days', () {
    expect(LoadDraft(savedAt: now).isWorthSaving, isFalse);
    expect(LoadDraft(pickup: ' D ', savedAt: now).isWorthSaving, isFalse);
    expect(LoadDraft(pickup: 'Delhi', savedAt: now).isWorthSaving, isTrue);
    expect(LoadDraft(weight: '3', savedAt: now).isWorthSaving, isTrue);
    expect(LoadDraft(pickup: 'Delhi', savedAt: now).isExpired(now.add(const Duration(days: 6, hours: 23))), isFalse);
    expect(LoadDraft(pickup: 'Delhi', savedAt: now).isExpired(now.add(const Duration(days: 7))), isTrue);
  });

  test('json round trip; junk and a missing time give null; long text is cut', () {
    final d = LoadDraft(pickup: 'Delhi', drop: 'Jaipur', cargoType: 'FMCG', weight: '3', vehicleType: '14ft', budget: '9000', notes: 'x' * 500, pickupDate: '2026-10-12', savedAt: now);
    final back = LoadDraft.fromJson(d.toJson())!;
    expect((back.pickup, back.drop, back.weight, back.pickupDate), ('Delhi', 'Jaipur', '3', '2026-10-12'));
    expect(back.notes.length, LoadDraft.maxText);
    expect(back.pickupDay, DateTime(2026, 10, 12));
    expect(LoadDraft.fromJson('nope'), isNull);
    expect(LoadDraft.fromJson({'pickup': 'x'}), isNull);
  });

  test('the store keeps one draft per person, drops an expired or empty one, and clear removes it', () async {
    await LoadDraftStore.save(LoadDraft(pickup: 'Delhi', savedAt: DateTime.now()));
    expect((await LoadDraftStore.load())!.pickup, 'Delhi');
    uid = 'c2';
    expect(await LoadDraftStore.load(), isNull);
    uid = 'c1';
    expect(await LoadDraftStore.load(now: DateTime.now().add(const Duration(days: 8))), isNull);
    expect(await LoadDraftStore.load(), isNull); // removed when it expired
    await LoadDraftStore.save(LoadDraft(pickup: 'Pune', savedAt: DateTime.now()));
    await LoadDraftStore.save(LoadDraft(pickup: '', savedAt: DateTime.now())); // empty = clear
    expect(await LoadDraftStore.load(), isNull);
    await LoadDraftStore.save(LoadDraft(pickup: 'Agra', savedAt: DateTime.now()));
    await LoadDraftStore.clear();
    expect(await LoadDraftStore.load(), isNull);
  });

  Future<GlobalKey<NavigatorState>> open(WidgetTester tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('home')))));
    nav.currentState!.push<void>(MaterialPageRoute(builder: (_) => const PostLoadScreen()));
    await tester.pumpAndSettle();
    return nav;
  }

  testWidgets('typing saves a draft after a pause; reopening offers it and Continue fills the form', (tester) async {
    var nav = await open(tester);
    await tester.enterText(find.byType(TextField).first, 'Delhi');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect((await tester.runAsync(LoadDraftStore.load))!.pickup, 'Delhi');
    // leave (discard would clear it, so use Save draft)
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saveDraftLeave')));
    await tester.pumpAndSettle();
    expect(find.byType(PostLoadScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    nav = await open(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draftBanner')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draftResume')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draftBanner')), findsNothing);
    expect(find.widgetWithText(TextField, 'Delhi'), findsOneWidget);
  });

  testWidgets('Delete draft removes it for good; Discard on leaving also clears', (tester) async {
    await LoadDraftStore.save(LoadDraft(pickup: 'Delhi', drop: 'Jaipur', savedAt: DateTime.now()));
    var nav = await open(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Delhi → Jaipur'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('draftDelete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draftBanner')), findsNothing);
    expect(await tester.runAsync(LoadDraftStore.load), isNull);
    // typing after a delete must not bring a draft back when the person discards
    await tester.enterText(find.byType(TextField).first, 'Pune');
    await tester.pump();
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discardLoad')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(await tester.runAsync(LoadDraftStore.load), isNull);
  });

  testWidgets('while the banner waits, typing does not overwrite the saved draft', (tester) async {
    await LoadDraftStore.save(LoadDraft(pickup: 'Delhi', savedAt: DateTime.now()));
    await open(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Mumbai');
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect((await tester.runAsync(LoadDraftStore.load))!.pickup, 'Delhi');
  });
}
