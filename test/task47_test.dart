import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/assistant/assistant_engine.dart';
import 'package:transport_app/core/l10n/assistant_strings.dart';
import 'package:transport_app/core/l10n/l10n.dart';

const engine = RuleEngine();

AssistantReply ask(String t, {String role = 'customer'}) => engine.reply(t, role: role);

void main() {
  group('intents in English', () {
    test('each intent', () {
      expect(ask('hello').intent, AssistantIntent.greeting);
      expect(ask('where is my booking').intent, AssistantIntent.myBooking);
      expect(ask('I want to post a load').intent, AssistantIntent.postLoad);
      expect(ask('find loads near me', role: 'driver').intent, AssistantIntent.nearbyLoads);
      expect(ask('what is otp').intent, AssistantIntent.otpFaq);
      expect(ask('how does bid work').intent, AssistantIntent.bidFaq);
      expect(ask('how to pay').intent, AssistantIntent.paymentFaq);
      expect(ask('how to cancel').intent, AssistantIntent.cancelFaq);
      expect(ask('I have a complaint').intent, AssistantIntent.supportTicket);
    });
  });

  group('intents in Hinglish and Hindi', () {
    test('Hinglish', () {
      expect(ask('namaste').intent, AssistantIntent.greeting);
      expect(ask('meri booking kahan hai').intent, AssistantIntent.myBooking);
      expect(ask('saman bhejna hai').intent, AssistantIntent.postLoad);
      expect(ask('paas ka load dikhao', role: 'driver').intent, AssistantIntent.nearbyLoads);
      expect(ask('otp kya hai').intent, AssistantIntent.otpFaq);
      expect(ask('bhav kaise bhejte hain').intent, AssistantIntent.bidFaq);
      expect(ask('payment kaise hoga').intent, AssistantIntent.paymentFaq);
      expect(ask('cancel kaise karein').intent, AssistantIntent.cancelFaq);
      expect(ask('shikayat karni hai').intent, AssistantIntent.supportTicket);
    });
    test('Hindi', () {
      expect(ask('नमस्ते').intent, AssistantIntent.greeting);
      expect(ask('मेरी बुकिंग कहाँ है').intent, AssistantIntent.myBooking);
      expect(ask('सामान भेजना है').intent, AssistantIntent.postLoad);
      expect(ask('पास के लोड खोजें', role: 'driver').intent, AssistantIntent.nearbyLoads);
      expect(ask('ओटीपी क्या है').intent, AssistantIntent.otpFaq);
      expect(ask('भाव कैसे भेजें').intent, AssistantIntent.bidFaq);
      expect(ask('पेमेंट कैसे होगा').intent, AssistantIntent.paymentFaq);
      expect(ask('कैंसल कैसे करें').intent, AssistantIntent.cancelFaq);
      expect(ask('शिकायत करनी है').intent, AssistantIntent.supportTicket);
    });
  });

  // greeting, booking, post load, nearby (driver), otp, bid, payment, cancel, support
  const order = [
    AssistantIntent.greeting,
    AssistantIntent.myBooking,
    AssistantIntent.postLoad,
    AssistantIntent.nearbyLoads,
    AssistantIntent.otpFaq,
    AssistantIntent.bidFaq,
    AssistantIntent.paymentFaq,
    AssistantIntent.cancelFaq,
    AssistantIntent.supportTicket,
  ];
  const words = <String, List<String>>{
    'kannada': ['ನಮಸ್ಕಾರ', 'ಬುಕಿಂಗ್', 'ಸಾಮಾನು', 'ಹತ್ತಿರ', 'ಒಟಿಪಿ', 'ಬೆಲೆ', 'ಪಾವತಿ', 'ರದ್ದು', 'ದೂರು'],
    'tamil': ['வணக்கம்', 'முன்பதிவு', 'சரக்கு', 'அருகில்', 'ஓடிபி', 'விலை', 'பணம்', 'ரத்து', 'புகார்'],
    'telugu': ['నమస్కారం', 'బుకింగ్', 'సరుకు', 'దగ్గర', 'ఓటీపీ', 'ధర', 'డబ్బు', 'రద్దు', 'ఫిర్యాదు'],
    'marathi': ['नमस्कार', 'बुकिंग', 'सामान', 'जवळ', 'ओटीपी', 'किंमत', 'पेमेंट', 'रद्द', 'तक्रार'],
    'gujarati': ['હેલો', 'બુકિંગ', 'સામાન', 'નજીક', 'ઓટીપી', 'ભાવ', 'ચુકવણી', 'રદ', 'ફરિયાદ'],
    'bengali': ['হ্যালো', 'বুকিং', 'মাল', 'কাছে', 'ওটিপি', 'দাম', 'পেমেন্ট', 'বাতিল', 'অভিযোগ'],
    'punjabi': ['ਹੈਲੋ', 'ਬੁਕਿੰਗ', 'ਸਮਾਨ', 'ਨੇੜੇ', 'ਓਟੀਪੀ', 'ਕੀਮਤ', 'ਭੁਗਤਾਨ', 'ਰੱਦ', 'ਮਦਦ'],
    'urdu': ['ہیلو', 'بکنگ', 'سامان', 'قریب', 'او ٹی پی', 'قیمت', 'ادائیگی', 'منسوخ', 'شکایت'],
    'kashmiri': ['سلام', 'بُکنگ', 'مال بھیجنا', 'نزدیک', 'او ٹی پی', 'قیمت', 'ادائیگی', 'منسوخ', 'مدد'],
  };

  group('keyword set of each other language', () {
    for (final e in words.entries) {
      test(e.key, () {
        for (var i = 0; i < order.length; i++) {
          final role = order[i] == AssistantIntent.nearbyLoads ? 'driver' : 'customer';
          expect(ask(e.value[i], role: role).intent, order[i], reason: '${e.key}: ${e.value[i]}');
        }
      });
    }
  });

  group('entities', () {
    test('route, vehicle and weight from Hinglish', () {
      final r = ask('Delhi se Jaipur 2 ton tempo chahiye');
      expect(r.intent, AssistantIntent.postLoad);
      expect(r.action, AssistantAction.openPostLoad);
      expect(r.prefill, {'pickup': 'Delhi', 'drop': 'Jaipur', 'vehicleType': '3-Wheeler', 'weightTons': '2'});
      expect(r.textKey, 'asPostLoadFilled');
    });
    test('English route and a ft truck', () {
      final r = ask('book a truck from Pune to Mumbai 17 ft 500 kg');
      expect(r.prefill['pickup'], 'Pune');
      expect(r.prefill['drop'], 'Mumbai');
      expect(r.prefill['vehicleType'], '17ft');
      expect(r.prefill['weightTons'], '0.5');
    });
    test('Hindi cities', () {
      final r = ask('दिल्ली से जयपुर सामान भेजना है');
      expect(r.prefill['pickup'], 'Delhi');
      expect(r.prefill['drop'], 'Jaipur');
    });
    test('a route alone is a load for a customer and nearby loads for a driver', () {
      expect(ask('Delhi se Jaipur').intent, AssistantIntent.postLoad);
      final d = ask('Delhi se Jaipur', role: 'driver');
      expect(d.intent, AssistantIntent.nearbyLoads);
      expect(d.prefill['pickup'], 'Delhi');
    });
    test('no entities gives the plain post-load text', () {
      expect(ask('post load').textKey, 'asPostLoad');
      expect(ask('post load').prefill, isEmpty);
    });
    test('weight in tons, kg and Devanagari', () {
      expect(RuleEngine.entities('3 tonne').weightTons, '3');
      expect(RuleEngine.entities('1500 kg').weightTons, '1.5');
      expect(RuleEngine.entities('५ टन').weightTons, isNull); // Devanagari digits are not read
      expect(RuleEngine.entities('5 टन').weightTons, '5');
      expect(RuleEngine.entities('hello').isEmpty, isTrue);
    });
    test('mini truck beats mini and ft needs a known size', () {
      expect(RuleEngine.entities('mini truck').vehicleType, 'Mini');
      expect(RuleEngine.entities('15 ft').vehicleType, isNull);
      expect(RuleEngine.entities('open body').vehicleType, 'Open body');
      expect(RuleEngine.entities('container chahiye').vehicleType, 'Container');
    });
  });

  group('actions', () {
    test('actions of intents', () {
      expect(ask('my booking').action, AssistantAction.openBookings);
      expect(ask('complaint').action, AssistantAction.openTicket);
      expect(ask('nearby loads', role: 'driver').action, AssistantAction.openNearbyLoads);
      expect(ask('otp').action, AssistantAction.none);
      expect(ask('hello').action, AssistantAction.none);
    });
    test('a driver asking about loads is not offered to post one', () {
      final r = ask('load bhejna hai', role: 'driver');
      expect(r.intent, isNot(AssistantIntent.postLoad));
    });
    test('a customer cannot get nearby loads', () {
      expect(ask('nearby loads').intent, AssistantIntent.unknown);
    });
  });

  group('confidence and unknown', () {
    test('nonsense is unknown', () {
      for (final t in ['', '   ', 'asdf qwer', 'what is the weather', '???']) {
        final r = ask(t);
        expect(r.intent, AssistantIntent.unknown, reason: t);
        expect(r.textKey, 'asUnknown');
        expect(r.understood, isFalse);
      }
    });
    test('a greeting does not beat a real question', () {
      expect(ask('hello my booking').intent, AssistantIntent.myBooking);
    });
    test('confidence is 1 for a lone intent and lower when mixed', () {
      expect(ask('otp').confidence, 1);
      final mixed = ask('payment cancel refund');
      expect(mixed.confidence, lessThan(1));
      expect(mixed.confidence, greaterThan(0.5));
      expect(mixed.intent, AssistantIntent.cancelFaq); // 2 cancel words beat 1
    });
    test('tie goes to the priority order', () {
      expect(ask('cancel payment').intent, AssistantIntent.cancelFaq);
    });
    test('noise: repeated letters, case, punctuation, nukta', () {
      expect(ask('HELLOOOO!!!').intent, AssistantIntent.greeting);
      expect(ask('OTP???').intent, AssistantIntent.otpFaq);
      expect(RuleEngine.normalize('ज़रूर  Hello!!'), 'जरूर hello');
    });
    test('a keyword inside another word does not count', () {
      expect(ask('hint').intent, AssistantIntent.unknown); // not "hi"
      expect(ask('payroll').intent, AssistantIntent.unknown); // not "pay"
    });
  });

  group('unknown question collector', () {
    final unknown = RuleEngine.unknownReply;
    test('sanitize removes digits, phones, links and e-mail and cuts to 300', () {
      expect(UnknownQuestionCollector.sanitize('call 9876543210 now'), 'call now');
      expect(UnknownQuestionCollector.sanitize('mail me a@b.com or see https://x.in/a ok'), 'mail me or see ok');
      expect(UnknownQuestionCollector.sanitize('फोन ९८७६५४३२१० करो'), 'फोन करो');
      expect(UnknownQuestionCollector.sanitize('a' * 400).length, 300);
    });
    test('stores only unknown, once, and nothing that is empty after cleaning', () {
      final c = UnknownQuestionCollector();
      const ok = AssistantReply(intent: AssistantIntent.otpFaq, textKey: 'asOtp');
      expect(c.add('otp kya hai', ok), isNull);
      expect(c.add('weather today 123', unknown), 'weather today');
      expect(c.add('Weather today!', unknown), isNull); // same after normalising
      expect(c.add('12345', unknown), isNull);
      expect(c.items, ['weather today']);
    });
    test('keeps the newest maxItems', () {
      final c = UnknownQuestionCollector(maxItems: 2);
      c.add('one one', unknown);
      c.add('two two', unknown);
      c.add('three three', unknown);
      expect(c.items, ['two two', 'three three']);
      c.clear();
      expect(c.items, isEmpty);
    });
  });

  group('answer texts', () {
    test('every reply key exists with 12 non-empty languages', () {
      final keys = {
        'asGreeting', 'asMyBooking', 'asPostLoad', 'asPostLoadFilled', 'asNearby', 'asOtp', 'asBid', 'asPayment', 'asCancel', 'asTicket', 'asUnknown',
      };
      expect(assistantStrings.keys.toSet(), keys);
      for (final e in assistantStrings.entries) {
        expect(e.value.length, AppLanguage.values.length, reason: e.key);
        expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
      }
    });
    test('the engine only returns keys that exist and are merged into T', () {
      const samples = ['hello', 'my booking', 'post load', 'Delhi se Jaipur', 'otp', 'bid', 'pay', 'cancel', 'help', 'xyzzy'];
      for (final s in samples) {
        for (final role in ['customer', 'driver']) {
          final r = engine.reply(s, role: role);
          expect(assistantStrings.containsKey(r.textKey), isTrue, reason: '$s/$role ${r.textKey}');
          expect(T.get(r.textKey, AppLanguage.hindi), isNot(r.textKey));
        }
      }
    });
    test('every keyword is unique to the point of not crossing intents (exact duplicates)', () {
      final seen = <String, AssistantIntent>{};
      RuleEngine.keywords.forEach((intent, list) {
        for (final k in list) {
          final n = RuleEngine.normalize(k);
          if (seen.containsKey(n) && seen[n] != intent) {
            fail('"$k" is a keyword of both ${seen[n]} and $intent');
          }
          seen[n] = intent;
        }
      });
    });
    test('the Hindi, Hinglish and English answers differ and Hinglish is Latin', () {
      for (final e in assistantStrings.entries) {
        expect(e.value[1], isNot(e.value[0]), reason: e.key);
        expect(RegExp(r'^[\x00-\x7F’]+$').hasMatch(e.value[2]), isTrue, reason: e.key);
      }
    });
  });
}
