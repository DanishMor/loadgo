import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/simple_mode_strings.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/settings/simple_mode.dart';
import 'package:transport_app/core/voice/voice_input.dart';
import 'package:transport_app/core/voice/voice_parser.dart';
import 'package:transport_app/core/widgets/logistics_labels.dart';
import 'package:transport_app/driver/simple_bid.dart';
import 'package:transport_app/driver/simple_home_screen.dart';

class FakeEngine implements SpeechEngine {
  bool ok;
  bool deny;
  String? heard;
  String? usedLocale;
  FakeEngine({this.ok = true, this.deny = false, this.heard});

  @override
  Future<bool> init({required void Function() onDenied}) async {
    if (deny) onDenied();
    return ok && !deny;
  }

  @override
  Future<String?> listen({required String localeId}) async {
    usedLocale = localeId;
    return heard;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    SharedPreferences.setMockInitialValues({'rationale_seen_microphone': true});
    SimpleMode.reset();
  });
  tearDown(() => VoiceInput.engine = SpeechToTextEngine());

  group('VoiceParser amounts', () {
    final cases = <String, int>{
      '5000': 5000,
      '5,000': 5000,
      '₹ 7500': 7500,
      '5 hazaar': 5000,
      '5 thousand': 5000,
      'ten thousand': 10000,
      'five thousand five hundred': 5500,
      'twenty five thousand': 25000,
      'two lakh': 200000,
      'seven hundred': 700,
      'one lakh fifty thousand': 150000,
      'पाँच हज़ार': 5000,
      'पांच हजार': 5000,
      'दस हज़ार': 10000,
      'बीस हज़ार': 20000,
      'पच्चीस सौ': 2500,
      'सात सौ पचास': 750,
      'दो हज़ार पाँच सौ': 2500,
      'एक लाख': 100000,
      'ढाई हज़ार': 2500,
      'डेढ़ हज़ार': 1500,
      'डेढ़ लाख': 150000,
      'सवा लाख': 125000,
      'साढ़े तीन हज़ार': 3500,
      'पैंतालीस हज़ार': 45000,
      'paanch hazaar': 5000,
      'do hazaar paanch sau': 2500,
      'dedh lakh': 150000,
      'dhai hazaar': 2500,
      'sava lakh': 125000,
      'saade teen hazaar': 3500,
      'bees hazaar': 20000,
      'ek lakh pachas hazaar': 150000,
      'mera daam 8000 rupaye': 8000,
    };
    cases.forEach((text, rupees) {
      test('"$text" is $rupees', () => expect(VoiceParser.parseAmountRupees(text), rupees));
    });

    test('no amount in the speech gives null', () {
      for (final t in ['', '   ', 'hello there', 'Delhi se Jaipur', 'zero', '0']) {
        expect(VoiceParser.parseAmountRupees(t), isNull, reason: t);
      }
    });
  });

  group('VoiceParser routes', () {
    test('Hinglish, English and Hindi routes', () {
      var r = VoiceParser.parseRoute('Delhi se Jaipur');
      expect((r.from, r.to), ('Delhi', 'Jaipur'));
      r = VoiceParser.parseRoute('from Pune to Mumbai');
      expect((r.from, r.to), ('Pune', 'Mumbai'));
      r = VoiceParser.parseRoute('दिल्ली से जयपुर');
      expect((r.from, r.to), ('Delhi', 'Jaipur'));
      r = VoiceParser.parseRoute('लखनऊ तक');
      expect(r.to, isNull);
      r = VoiceParser.parseRoute('bangalore se chennai tak');
      expect((r.from, r.to), ('Bengaluru', 'Chennai'));
    });

    test('one city is the pickup; nonsense is empty', () {
      expect(VoiceParser.parseRoute('Indore').from, 'Indore');
      expect(VoiceParser.parseRoute('जोधपुर').from, 'Jodhpur');
      expect(VoiceParser.parseRoute('blah blah').isEmpty, isTrue);
      expect(VoiceParser.cityIn('गुड़गांव'), 'Gurugram');
      expect(VoiceParser.cityIn('xyz'), isNull);
    });
  });

  group('VoiceInput', () {
    test('locale follows the app language', () {
      expect(VoiceInput.localeFor(AppLanguage.hindi), 'hi_IN');
      expect(VoiceInput.localeFor(AppLanguage.hinglish), 'en_IN');
      expect(VoiceInput.localeFor(AppLanguage.tamil), 'ta_IN');
      expect(VoiceInput.localeFor(AppLanguage.kashmiri), 'ur_IN');
    });

    test('text, unavailable, denied and nothing heard', () async {
      final e = FakeEngine(heard: 'paanch hazaar');
      VoiceInput.engine = e;
      languageNotifier.value = AppLanguage.hindi;
      expect((await VoiceInput.listenOnce()).text, 'paanch hazaar');
      expect(e.usedLocale, 'hi_IN');
      VoiceInput.engine = FakeEngine(ok: false);
      expect((await VoiceInput.listenOnce()).issue, VoiceIssue.unavailable);
      VoiceInput.engine = FakeEngine(deny: true);
      expect((await VoiceInput.listenOnce()).issue, VoiceIssue.denied);
      VoiceInput.engine = FakeEngine();
      expect((await VoiceInput.listenOnce()).issue, VoiceIssue.nothingHeard);
    });
  });

  group('SimpleMode', () {
    test('off by default, saved, and read back', () async {
      await SimpleMode.load();
      expect(SimpleMode.isOn, isFalse);
      await SimpleMode.set(true);
      SimpleMode.reset();
      expect(SimpleMode.isOn, isFalse);
      await SimpleMode.load();
      expect(SimpleMode.isOn, isTrue);
    });

    test('the first-start question is asked once', () async {
      expect(await SimpleMode.shouldAsk(), isTrue);
      await SimpleMode.markAsked();
      expect(await SimpleMode.shouldAsk(), isFalse);
    });

    Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: SingleChildScrollView(child: child))));

    testWidgets('the prompt: yes switches Simple Mode on and the card goes away', (t) async {
      await t.pumpWidget(app(const SimpleModePrompt()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('simpleModePrompt')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('simpleModeYes')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('simpleModePrompt')), findsNothing);
      expect(SimpleMode.isOn, isTrue);
      expect(await SimpleMode.shouldAsk(), isFalse);
    });

    testWidgets('the prompt: not now keeps it off and does not come back', (t) async {
      await t.pumpWidget(app(const SimpleModePrompt()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('simpleModeNo')));
      await t.pumpAndSettle();
      expect(SimpleMode.isOn, isFalse);
      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(app(const SimpleModePrompt()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('simpleModePrompt')), findsNothing);
    });

    testWidgets('the settings switch flips the mode', (t) async {
      await t.pumpWidget(app(const SimpleModeSwitch()));
      await t.tap(find.byKey(const ValueKey('simpleModeSwitch')));
      await t.pumpAndSettle();
      expect(SimpleMode.isOn, isTrue);
    });
  });

  group('Simple screens', () {
    Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: child));

    testWidgets('four big buttons with icons and short labels', (t) async {
      await t.pumpWidget(app(const SimpleDriverHome()));
      for (final k in ['simpleFindLoads', 'simpleMyTrips', 'simpleMoney', 'simpleHelp']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Find loads'), findsOneWidget);
      expect(find.text('My trips'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Help'), findsOneWidget);
    });

    testWidgets('the money screen shows the balance and what can be requested', (t) async {
      final db = FakeFirebaseFirestore();
      Backend.useFakes(db: db, uid: () => 'd1');
      await t.pumpWidget(app(const SimpleMoneyScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('simpleBalance')), findsOneWidget);
      expect(find.byKey(const ValueKey('simpleAvailable')), findsOneWidget);
      expect(find.text('You can ask for'), findsOneWidget);
      expect(find.byKey(const ValueKey('simpleAskMoney')), findsOneWidget);
    });

    test('labels are at most 3 words in every language', () {
      for (final k in ['simpleFindLoads', 'simpleMyTrips', 'simpleMoney', 'simpleHelp', 'simpleAskMoney', 'simpleSendPrice']) {
        final all = simpleModeStrings[k]!;
        expect(all.length, 12, reason: k);
        for (var i = 0; i < all.length; i++) {
          expect(all[i].trim().split(RegExp(r'\s+')).length, lessThanOrEqualTo(3), reason: '$k/$i ${all[i]}');
        }
      }
    });

    test('every simple-mode string has 12 non-empty languages', () {
      for (final e in simpleModeStrings.entries) {
        expect(e.value.length, 12, reason: e.key);
        expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      }
    });
  });

  group('Simple bid', () {
    test('stepper: 100 below 5,000, 500 from 5,000, within limits', () {
      expect(simpleBidNext(1000, up: true), 1100);
      expect(simpleBidNext(4900, up: true), 5000);
      expect(simpleBidNext(5000, up: true), 5500);
      expect(simpleBidNext(5000, up: false), 4900);
      expect(simpleBidNext(5500, up: false), 5000);
      expect(simpleBidNext(100, up: false), 100);
      expect(simpleBidNext(1000000, up: true), 1000000);
    });

    Widget host(void Function(int?) got, {int? initialPaise}) => MaterialApp(
          home: LanguageScope(
            notifier: languageNotifier,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => got(await askSimpleBidPaise(context, initialPaise: initialPaise)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('start from the estimate, step, confirm in paise', (t) async {
      int? got;
      await t.pumpWidget(host((v) => got = v, initialPaise: 600000));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('bidAmount')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bidPlus')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('bidMinus')));
      await t.tap(find.byKey(const ValueKey('bidMinus')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('bidConfirm')));
      await t.pumpAndSettle();
      expect(got, 600000 - 500 * 100);
    });

    testWidgets('speaking an amount sets it; an unclear one shows a message', (t) async {
      int? got;
      VoiceInput.engine = FakeEngine(heard: 'dedh hazaar');
      await t.pumpWidget(host((v) => got = v));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voiceMic')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bidConfirm')));
      await t.pumpAndSettle();
      expect(got, 150000);

      VoiceInput.engine = FakeEngine(heard: 'bla bla');
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voiceMic')));
      await t.pumpAndSettle();
      expect(find.text('Could not hear an amount. Please try again.'), findsOneWidget);
    });

    testWidgets('the normal price dialog has a mic that fills the field', (t) async {
      int? got;
      VoiceInput.engine = FakeEngine(heard: 'ten thousand');
      await t.pumpWidget(MaterialApp(
        home: LanguageScope(
          notifier: languageNotifier,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => got = await askPricePaise(context, title: 'Offer', label: 'Price', voice: true),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('voiceMic')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('priceSubmit')));
      await t.pumpAndSettle();
      expect(got, 1000000);
    });

    testWidgets('a missing microphone shows the fallback message', (t) async {
      VoiceInput.engine = FakeEngine(deny: true);
      await t.pumpWidget(MaterialApp(
        home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: VoiceMicButton(onText: (_) {}))),
      ));
      await t.tap(find.byKey(const ValueKey('voiceMic')));
      await t.pumpAndSettle();
      expect(find.textContaining('Microphone permission is off'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      VoiceInput.engine = FakeEngine(ok: false);
      await t.tap(find.byKey(const ValueKey('voiceMic')));
      await t.pumpAndSettle();
      expect(find.textContaining('Voice input is not available'), findsOneWidget);
    });
  });
}
