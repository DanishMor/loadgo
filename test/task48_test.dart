import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_assistant_screen.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/assistant/assistant_engine.dart';
import 'package:transport_app/core/assistant/assistant_log_service.dart';
import 'package:transport_app/core/assistant/sahayak_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/support/support_screens.dart';
import 'package:transport_app/core/theme/app_theme.dart';
import 'package:transport_app/customer/post_load_screen.dart';

Widget host(Widget child, {bool dark = false}) {
  AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
  return MaterialApp(
    theme: AppTheme.build(Brightness.light),
    darkTheme: AppTheme.build(Brightness.dark),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: LanguageScope(notifier: languageNotifier, child: child),
  );
}

/// Opens [screen] from a plain first page so that `pop` has somewhere to go.
Widget launcher(Widget screen) => host(Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const ValueKey('launch'),
            onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => screen)),
            child: const Text('go'),
          ),
        ),
      ),
    ));

Future<void> say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const ValueKey('asInput')), text);
  await t.tap(find.byKey(const ValueKey('asSend')));
  await t.pumpAndSettle();
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    languageNotifier.value = AppLanguage.english;
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    AssistantLogService.resetGuard();
  });

  group('Sahayak screen', () {
    testWidgets('starts with the greeting, role chips and an input', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      expect(find.textContaining('I am LoadGo Sahayak'), findsOneWidget);
      expect(find.byKey(const ValueKey('asChip_asChipPost')), findsOneWidget);
      expect(find.byKey(const ValueKey('asChip_asChipNearby')), findsNothing);
      expect(find.byKey(const ValueKey('asInput')), findsOneWidget);
    });

    testWidgets('a driver gets driver chips', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'driver', logUnknown: false)));
      expect(find.byKey(const ValueKey('asChip_asChipNearby')), findsOneWidget);
      expect(find.byKey(const ValueKey('asChip_asChipPost')), findsNothing);
    });

    testWidgets('typed text is answered and shown as a bubble', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      await say(t, 'what is otp');
      expect(find.text('what is otp'), findsOneWidget);
      expect(find.textContaining('6-digit OTPs'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing); // an FAQ has no action
    });

    testWidgets('the my booking button closes the chat and opens the bookings tab', (t) async {
      var opened = 0;
      await t.pumpWidget(launcher(SahayakScreen(role: 'customer', logUnknown: false, actions: SahayakActions(openBookings: () => opened++))));
      await t.tap(find.byKey(const ValueKey('launch')));
      await t.pumpAndSettle();
      await say(t, 'my booking');
      await t.tap(find.byKey(const ValueKey('asAction_openBookings')));
      await t.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(SahayakScreen), findsNothing);
    });

    testWidgets('post load passes what was understood to the form', (t) async {
      Map<String, String>? got;
      await t.pumpWidget(launcher(SahayakScreen(role: 'customer', logUnknown: false, actions: SahayakActions(openPostLoad: (p) => got = p))));
      await t.tap(find.byKey(const ValueKey('launch')));
      await t.pumpAndSettle();
      await say(t, 'Delhi se Jaipur 2 ton tempo chahiye');
      await t.tap(find.byKey(const ValueKey('asAction_openPostLoad')));
      await t.pumpAndSettle();
      expect(got, {'pickup': 'Delhi', 'drop': 'Jaipur', 'vehicleType': '3-Wheeler', 'weightTons': '2'});
    });

    testWidgets('a driver chip opens nearby loads', (t) async {
      var opened = 0;
      await t.pumpWidget(launcher(SahayakScreen(role: 'driver', logUnknown: false, actions: SahayakActions(openNearbyLoads: () => opened++))));
      await t.tap(find.byKey(const ValueKey('launch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('asChip_asChipNearby')));
      await t.pumpAndSettle();
      expect(find.text('Loads near me'), findsNWidgets(2)); // the chip and the user bubble that shows its label
      await t.tap(find.byKey(const ValueKey('asAction_openNearbyLoads')));
      await t.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('an action this home cannot do has no button', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      await say(t, 'my booking');
      expect(find.byKey(const ValueKey('asAction_openBookings')), findsNothing);
      expect(find.textContaining('Bookings tab'), findsOneWidget);
    });

    testWidgets('the support ticket button opens the ticket form', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      await say(t, 'I have a complaint');
      await t.tap(find.byKey(const ValueKey('asAction_openTicket')));
      await t.pumpAndSettle();
      expect(find.byType(NewTicketScreen), findsOneWidget);
    });

    testWidgets('the answer follows the app language', (t) async {
      languageNotifier.value = AppLanguage.hindi;
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      expect(find.textContaining('लोडगो सहायक'), findsWidgets);
      await say(t, 'otp');
      expect(find.textContaining('6 अंकों'), findsOneWidget);
    });

    testWidgets('the input stops at 200 characters', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer', logUnknown: false)));
      await t.enterText(find.byKey(const ValueKey('asInput')), 'a' * 300);
      expect(t.widget<TextField>(find.byKey(const ValueKey('asInput'))).controller!.text.length, 200);
    });

    for (final dark in [false, true]) {
      testWidgets('fits 360x640 at 1.6x text (${dark ? 'dark' : 'light'})', (t) async {
        t.view.physicalSize = const Size(360, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
          home: LanguageScope(
            notifier: languageNotifier,
            child: SahayakScreen(role: 'customer', logUnknown: false, actions: SahayakActions(openBookings: () {}, openPostLoad: (_) {})),
          ),
        ));
        AppPalette.current = dark ? AppPalette.dark : AppPalette.light;
        await say(t, 'Delhi se Jaipur 2 ton tempo chahiye');
        expect(t.takeException(), isNull);
      });
    }
  });

  group('unknown question log', () {
    Future<List<Map<String, dynamic>>> docs() async => [for (final d in (await db.collection('assistant_unknown').get()).docs) d.data()];

    testWidgets('an unknown sentence is stored clean, once, with role and language', (t) async {
      languageNotifier.value = AppLanguage.hinglish;
      await t.pumpWidget(host(const SahayakScreen(role: 'driver')));
      await say(t, 'weather in 400001 call 9876543210');
      final all = await docs();
      expect(all.length, 1);
      expect(all.first['text'], 'weather in call');
      expect(all.first['userId'], 'u1');
      expect(all.first['role'], 'driver');
      expect(all.first['language'], 'hinglish');
      expect(all.first['resolved'], false);
    });

    testWidgets('understood sentences and chips are not logged', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer')));
      await say(t, 'my booking');
      await t.tap(find.byKey(const ValueKey('asChip_asChipOtp')));
      await t.pumpAndSettle();
      expect(await docs(), isEmpty);
    });

    testWidgets('the 3 second guard keeps a burst to one log', (t) async {
      await t.pumpWidget(host(const SahayakScreen(role: 'customer')));
      await say(t, 'qwerty one');
      await say(t, 'qwerty two');
      await say(t, 'qwerty three');
      expect((await docs()).length, 1);
    });

    test('the guard lets the next one through after the gap', () async {
      const unknown = RuleEngine.unknownReply;
      var now = DateTime(2026, 1, 1, 10);
      Future<bool> log(String s) => AssistantLogService.logUnknown(s, unknown, role: 'customer', language: 'english', now: () => now);
      expect(await log('first thing'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(await log('second thing'), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(await log('third thing'), isTrue);
      expect((await docs()).length, 2);
    });

    test('nothing is stored when signed out, understood, or empty after cleaning', () async {
      const unknown = RuleEngine.unknownReply;
      const ok = AssistantReply(intent: AssistantIntent.otpFaq, textKey: 'asOtp');
      expect(await AssistantLogService.logUnknown('otp', ok, role: 'customer', language: 'english'), isFalse);
      expect(await AssistantLogService.logUnknown('12345', unknown, role: 'customer', language: 'english'), isFalse);
      Backend.useFakes(db: db, uid: () => null);
      expect(await AssistantLogService.logUnknown('hello there friend', unknown, role: 'customer', language: 'english'), isFalse);
      expect(await docs(), isEmpty);
    });
  });

  group('admin screen', () {
    Future<void> seed() async {
      await db.collection('assistant_unknown').doc('a1').set({
        'text': 'weather today', 'userId': 'u9', 'role': 'customer', 'language': 'hindi', 'resolved': false, 'createdAt': DateTime(2026, 10, 6),
      });
      await db.collection('assistant_unknown').doc('a2').set({
        'text': 'old question', 'userId': 'u8', 'role': 'driver', 'language': 'english', 'resolved': true, 'createdAt': DateTime(2026, 10, 5),
      });
    }

    testWidgets('lists questions with role and language, and an empty state', (t) async {
      await t.pumpWidget(host(const AdminAssistantScreen()));
      await t.pumpAndSettle();
      expect(find.text('No unanswered questions'), findsOneWidget);
      await seed();
      await t.pumpAndSettle();
      expect(find.text('weather today'), findsOneWidget);
      expect(find.text('customer · hindi'), findsOneWidget);
      expect(find.byKey(const ValueKey('asResolved_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('asResolve_a2')), findsNothing);
    });

    testWidgets('mark resolved flips the flag and records who', (t) async {
      await seed();
      await t.pumpWidget(host(const AdminAssistantScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('asResolve_a1')));
      await t.pumpAndSettle();
      final d = (await db.collection('assistant_unknown').doc('a1').get()).data()!;
      expect(d['resolved'], true);
      expect(d['resolvedBy'], 'u1');
      expect(d['text'], 'weather today');
      expect(find.byKey(const ValueKey('asResolved_a1')), findsOneWidget);
    });
  });

  group('post load pre-fill', () {
    testWidgets('pickup, drop, weight and vehicle come from the assistant', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(const PostLoadScreen(initialPickup: 'Delhi', initialDrop: 'Jaipur', initialWeight: '2', initialVehicleType: 'Mini')));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Delhi'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Jaipur'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
    });
  });

  test('the dashboard entry is for super and support admins', () {
    expect(staffCan('super', 'adminAssistant'), isTrue);
    expect(staffCan('support', 'adminAssistant'), isTrue);
    expect(staffCan('ops', 'adminAssistant'), isFalse);
    expect(staffCan('verifier', 'adminAssistant'), isFalse);
  });
}
