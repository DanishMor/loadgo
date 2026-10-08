/// LoadGo Sahayak: a small in-app assistant that understands short English,
/// Hindi and Hinglish (and a few loan words of the other languages) with
/// keyword scores. Pure Dart: no Firebase, no network.
///
/// LATER(paid): an LLM engine behind the same [AssistantEngine] interface.
library;

import '../pricing/cities.dart';
import '../voice/voice_parser.dart';

enum AssistantIntent {
  greeting,
  myBooking,
  postLoad,
  nearbyLoads,
  otpFaq,
  bidFaq,
  paymentFaq,
  cancelFaq,
  supportTicket,
  unknown,
}

/// What the screen may offer as a button under the answer.
enum AssistantAction { none, openBookings, openPostLoad, openNearbyLoads, openTicket }

class AssistantReply {
  final AssistantIntent intent;

  /// Translation key of the answer (see assistant_strings.dart).
  final String textKey;
  final AssistantAction action;

  /// Pre-filled values for the action: `pickup`, `drop`, `vehicleType`,
  /// `weightTons` (all strings, only the ones that were understood).
  final Map<String, String> prefill;

  /// 0..1; how much the best intent beat the others.
  final double confidence;

  const AssistantReply({
    required this.intent,
    required this.textKey,
    this.action = AssistantAction.none,
    this.prefill = const {},
    this.confidence = 0,
  });

  bool get understood => intent != AssistantIntent.unknown;

  @override
  String toString() => 'AssistantReply($intent, $action, $prefill, ${confidence.toStringAsFixed(2)})';
}

abstract class AssistantEngine {
  /// [role] is `customer`, `driver` or `fleet`.
  AssistantReply reply(String text, {required String role});
}

/// Things found in a sentence.
class AssistantEntities {
  final String? from;
  final String? to;
  final String? vehicleType;
  final String? weightTons;
  const AssistantEntities({this.from, this.to, this.vehicleType, this.weightTons});

  bool get hasRoute => from != null || to != null;
  bool get isEmpty => from == null && to == null && vehicleType == null && weightTons == null;

  Map<String, String> toPrefill() => {
        'pickup': ?from,
        'drop': ?to,
        'vehicleType': ?vehicleType,
        'weightTons': ?weightTons,
      };
}

class RuleEngine implements AssistantEngine {
  const RuleEngine();

  /// Below this score an answer is not given (the sentence is "unknown").
  static const double minScore = 1;

  /// Tie-break order when two intents score the same (earlier wins).
  static const _priority = [
    AssistantIntent.supportTicket,
    AssistantIntent.cancelFaq,
    AssistantIntent.otpFaq,
    AssistantIntent.paymentFaq,
    AssistantIntent.bidFaq,
    AssistantIntent.myBooking,
    AssistantIntent.postLoad,
    AssistantIntent.nearbyLoads,
    AssistantIntent.greeting,
  ];

  // Keywords per intent. A keyword with a space is a phrase (worth 2).
  // Latin keywords match whole words, other scripts match as substrings.
  static const Map<AssistantIntent, List<String>> keywords = {
    AssistantIntent.greeting: [
      'hi', 'hello', 'hey', 'namaste', 'namaskar', 'good morning', 'good evening', 'salam', 'assalam',
      'नमस्ते', 'नमस्कार', 'हेलो', 'हैलो', 'ಹಲೋ', 'ನಮಸ್ಕಾರ', 'வணக்கம்', 'హలో', 'నమస్కారం', 'હેલો', 'નમસ્તે', 'হ্যালো', 'নমস্কার', 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ', 'ਹੈਲੋ', 'ہیلو', 'سلام',
    ],
    AssistantIntent.myBooking: [
      'booking', 'bookings', 'my trip', 'my trips', 'my booking', 'meri booking', 'meri trip', 'order', 'orders', 'trip status',
      'status', 'where is my', 'kahan hai', 'kaha hai', 'track', 'tracking', 'driver kahan',
      'बुकिंग', 'मेरी बुकिंग', 'ट्रिप', 'ऑर्डर', 'कहाँ है', 'कहां है', 'स्थिति',
      'ಬುಕಿಂಗ್', 'முன்பதிவு', 'புக்கிங்', 'బుకింగ్', 'बुकिंग', 'બુકિંગ', 'বুকিং', 'ਬੁਕਿੰਗ', 'بکنگ', 'بُکنگ',
    ],
    AssistantIntent.postLoad: [
      'post load', 'post a load', 'new load', 'load post', 'send goods', 'send parcel', 'send my goods', 'book truck', 'book a truck',
      'need truck', 'need a truck', 'truck chahiye', 'gaadi chahiye', 'gadi chahiye', 'tempo chahiye', 'saman bhejna', 'samaan bhejna',
      'maal bhejna', 'saman', 'samaan', 'maal', 'bhejna', 'bhejni', 'shift', 'shifting', 'transport', 'deliver', 'delivery',
      'लोड पोस्ट', 'सामान भेजना', 'माल भेजना', 'ट्रक चाहिए', 'गाड़ी चाहिए', 'गाड़ी बुक', 'सामान', 'माल', 'भेजना', 'शिफ्ट',
      'ಲೋಡ್ ಪೋಸ್ಟ್', 'ಸಾಮಾನು', 'ಲಾರಿ ಬೇಕು', 'லோடு போஸ்ட்', 'சரக்கு', 'లోడ్ పోస్ట్', 'సరుకు', 'लोड पोस्ट', 'સામાન', 'માલ', 'মাল', 'ਸਮਾਨ', 'ਮਾਲ', 'سامان', 'مال بھیجنا',
    ],
    AssistantIntent.nearbyLoads: [
      'nearby', 'near me', 'nearby loads', 'find load', 'find loads', 'available loads', 'open loads', 'load dhundh', 'load khoj',
      'load dhoondh', 'load milega', 'kaam chahiye', 'paas ka load', 'paas mein', 'loads',
      'पास', 'नज़दीक', 'नजदीक', 'लोड खोज', 'लोड ढूंढ', 'लोड मिलेगा', 'काम चाहिए',
      'ಹತ್ತಿರ', 'அருகில்', 'దగ్గర', 'जवळ', 'નજીક', 'কাছে', 'ਨੇੜੇ', 'قریب', 'نزدیک',
    ],
    AssistantIntent.otpFaq: [
      'otp', 'o t p', 'code', 'pin', 'verification code', 'ओटीपी', 'कोड', 'ಒಟಿಪಿ', 'ஓடிபி', 'ఓటీపీ', 'ઓટીપી', 'ওটিপি', 'ਓਟੀਪੀ', 'او ٹی پی',
    ],
    AssistantIntent.bidFaq: [
      'bid', 'bids', 'offer', 'offers', 'counter', 'negotiate', 'my price', 'rate', 'bhav', 'bhaav', 'daam', 'dam', 'kitna', 'price',
      'ऑफर', 'भाव', 'दाम', 'कितना', 'बोली', 'मोलभाव',
      'ಆಫರ್', 'ಬೆಲೆ', 'ஆஃபர்', 'விலை', 'ఆఫర్', 'ధర', 'किंमत', 'ભાવ', 'દામ', 'দাম', 'ਭਾਅ', 'ਕੀਮਤ', 'قیمت', 'بھاؤ',
    ],
    AssistantIntent.paymentFaq: [
      'payment', 'pay', 'paid', 'upi', 'cash', 'money', 'paisa', 'paise', 'wallet', 'invoice', 'bill', 'payout', 'withdraw', 'commission',
      'भुगतान', 'पेमेंट', 'पैसा', 'पैसे', 'वॉलेट', 'बिल', 'कमीशन',
      'ಪಾವತಿ', 'ಹಣ', 'பணம்', 'கட்டணம்', 'చెల్లింపు', 'డబ్బు', 'पेमेंट', 'ચુકવણી', 'પૈસા', 'পেমেন্ট', 'টাকা', 'ਭੁਗਤਾਨ', 'ਪੈਸੇ', 'ادائیگی', 'پیسے',
    ],
    AssistantIntent.cancelFaq: [
      'cancel', 'cancelled', 'canceled', 'cancellation', 'refund', 'radd', 'band karo', 'nahi chahiye',
      'कैंसल', 'रद्द', 'रिफंड', 'नहीं चाहिए',
      'ರದ್ದು', 'ரத்து', 'రద్దు', 'रद्द', 'રદ', 'বাতিল', 'ਰੱਦ', 'منسوخ',
    ],
    AssistantIntent.supportTicket: [
      'help', 'support', 'complaint', 'complain', 'problem', 'issue', 'ticket', 'shikayat', 'shikayat karni', 'dikkat', 'samasya', 'fraud', 'cheat',
      'मदद', 'सहायता', 'शिकायत', 'समस्या', 'दिक्कत', 'धोखा', 'टिकट',
      'ಸಹಾಯ', 'ದೂರು', 'உதவி', 'புகார்', 'సహాయం', 'ఫిర్యాదు', 'मदत', 'तक्रार', 'મદદ', 'ફરિયાદ', 'সাহায্য', 'অভিযোগ', 'ਮਦਦ', 'ਸ਼ਿਕਾਇਤ', 'مدد', 'شکایت',
    ],
  };

  // ------------------------------------------------------------- normalising

  /// Lower case, no punctuation, one space between words, no Devanagari
  /// nukta, letters repeated 3+ times cut to 1 ("helloooo").
  static String normalize(String text) {
    var t = text.toLowerCase();
    t = t.replaceAll('़', ''); // nukta: ज़ = ज, ड़ = ड
    t = t.replaceAll('ँ', 'ं'); // chandrabindu -> anusvara
    t = t.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N} ]', unicode: true), ' ');
    t = t.replaceAllMapped(RegExp(r'([a-z])\1{2,}'), (m) => m[1]!);
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isLatin(String s) => RegExp(r'^[a-z0-9 ]+$').hasMatch(s);

  static bool _has(String padded, String keyword) {
    final k = normalize(keyword);
    if (k.isEmpty) return false;
    if (_isLatin(k)) return padded.contains(' $k ');
    return padded.contains(k);
  }

  /// Score of each intent for [text] (only intents above 0).
  static Map<AssistantIntent, double> scores(String text) {
    final padded = ' ${normalize(text)} ';
    final out = <AssistantIntent, double>{};
    keywords.forEach((intent, list) {
      var s = 0.0;
      for (final k in list) {
        if (_has(padded, k)) s += k.contains(' ') ? 2 : 1;
      }
      if (s > 0) out[intent] = s;
    });
    return out;
  }

  // ---------------------------------------------------------------- entities

  static const Map<String, String> _vehicleWords = {
    'bike': 'Bike', 'motorcycle': 'Bike', 'बाइक': 'Bike',
    'scooter': 'Scooter', 'स्कूटर': 'Scooter',
    'cycle': 'Cycle', 'साइकिल': 'Cycle',
    'auto': '3-Wheeler', '3 wheeler': '3-Wheeler', 'three wheeler': '3-Wheeler', 'tempo': '3-Wheeler', 'टेम्पो': '3-Wheeler', 'ऑटो': '3-Wheeler',
    'mini truck': 'Mini', 'mini': 'Mini', 'chhota hathi': 'Mini', 'tata ace': 'Mini', 'छोटा हाथी': 'Mini',
    'container': 'Container', 'कंटेनर': 'Container',
    'trailer': 'Trailer', 'ट्रेलर': 'Trailer',
    'open body': 'Open body', 'open truck': 'Open body',
  };

  static const _feet = {'14', '17', '19', '20', '22', '24', '32'};

  /// Cities, vehicle and weight spoken in [text].
  static AssistantEntities entities(String text) {
    final route = VoiceParser.parseRoute(text);
    // parseRoute reads one lone city as a pickup; keep that.
    final padded = ' ${normalize(text)} ';

    String? vehicle;
    final ft = RegExp(r'\b(\d{2})\s?(?:ft|feet|foot)\b').firstMatch(padded);
    if (ft != null && _feet.contains(ft.group(1))) vehicle = '${ft.group(1)}ft';
    if (vehicle == null) {
      // longest word first so "mini truck" beats "mini"
      final words = _vehicleWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final w in words) {
        if (_has(padded, w)) {
          vehicle = _vehicleWords[w];
          break;
        }
      }
    }
    return AssistantEntities(
      from: route.from,
      to: route.to,
      vehicleType: vehicle,
      weightTons: _weightTons(padded),
    );
  }

  static String? _weightTons(String padded) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s?(tons?|tonnes?|tan|ton|टन|kg|kgs|kilo|किलो)\b').firstMatch(padded) ??
        RegExp(r'(\d+(?:\.\d+)?)\s?(टन|किलो)').firstMatch(padded);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    final unit = m.group(2)!;
    final tons = (unit.startsWith('kg') || unit.startsWith('kilo') || unit == 'किलो') ? n / 1000 : n;
    if (tons <= 0 || tons > 1000) return null;
    final s = tons.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }

  // ------------------------------------------------------------------ reply

  @override
  AssistantReply reply(String text, {required String role}) {
    final ent = entities(text);
    final sc = Map<AssistantIntent, double>.from(scores(text));

    // A route in the sentence is a strong hint: customers want to post a
    // load, drivers want to see loads.
    if (ent.hasRoute && role != 'fleet') {
      final target = role == 'driver' ? AssistantIntent.nearbyLoads : AssistantIntent.postLoad;
      sc[target] = (sc[target] ?? 0) + 2;
    }
    // Drivers do not post loads; "load" words mean looking for one.
    if (role == 'driver' && sc.containsKey(AssistantIntent.postLoad)) {
      sc[AssistantIntent.nearbyLoads] = (sc[AssistantIntent.nearbyLoads] ?? 0) + sc[AssistantIntent.postLoad]!;
      sc.remove(AssistantIntent.postLoad);
    }
    // Transporters only manage trucks and drivers: they neither post loads nor look for them.
    if (role == 'fleet') sc.remove(AssistantIntent.postLoad);
    // Transporters and customers do not look for loads on the road.
    if (role != 'driver' && sc.containsKey(AssistantIntent.nearbyLoads)) {
      sc.remove(AssistantIntent.nearbyLoads);
    }

    // A greeting never beats a real question in the same sentence.
    if (sc.length > 1) sc.remove(AssistantIntent.greeting);

    final ranked = sc.entries.where((e) => e.value >= minScore).toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        if (c != 0) return c;
        return _priority.indexOf(a.key).compareTo(_priority.indexOf(b.key));
      });
    if (ranked.isEmpty) return unknownReply;

    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0.0;
    final confidence = best.value / (best.value + second);
    return _build(best.key, ent, role, confidence);
  }

  static const unknownReply = AssistantReply(intent: AssistantIntent.unknown, textKey: 'asUnknown');

  AssistantReply _build(AssistantIntent intent, AssistantEntities ent, String role, double confidence) {
    switch (intent) {
      case AssistantIntent.greeting:
        return AssistantReply(intent: intent, textKey: 'asGreeting', confidence: confidence);
      case AssistantIntent.myBooking:
        return AssistantReply(intent: intent, textKey: 'asMyBooking', action: AssistantAction.openBookings, confidence: confidence);
      case AssistantIntent.postLoad:
        return AssistantReply(
          intent: intent,
          textKey: ent.isEmpty ? 'asPostLoad' : 'asPostLoadFilled',
          action: AssistantAction.openPostLoad,
          prefill: ent.toPrefill(),
          confidence: confidence,
        );
      case AssistantIntent.nearbyLoads:
        return AssistantReply(intent: intent, textKey: 'asNearby', action: AssistantAction.openNearbyLoads, prefill: ent.toPrefill(), confidence: confidence);
      case AssistantIntent.otpFaq:
        return AssistantReply(intent: intent, textKey: 'asOtp', confidence: confidence);
      case AssistantIntent.bidFaq:
        return AssistantReply(intent: intent, textKey: 'asBid', confidence: confidence);
      case AssistantIntent.paymentFaq:
        return AssistantReply(intent: intent, textKey: 'asPayment', confidence: confidence);
      case AssistantIntent.cancelFaq:
        return AssistantReply(intent: intent, textKey: 'asCancel', confidence: confidence);
      case AssistantIntent.supportTicket:
        return AssistantReply(intent: intent, textKey: 'asTicket', action: AssistantAction.openTicket, confidence: confidence);
      case AssistantIntent.unknown:
        return unknownReply;
    }
  }
}

/// Collects sentences the assistant did not understand so that an admin can
/// read them later. Pure; the screen decides where to store them.
class UnknownQuestionCollector {
  final int maxItems;
  final List<String> _items = [];

  UnknownQuestionCollector({this.maxItems = 50});

  /// Text that is safe to store: no digits (phone numbers, amounts, ids),
  /// no e-mail or link, collapsed spaces, at most [maxLength] characters.
  static String sanitize(String text, {int maxLength = 300}) {
    var t = text.trim();
    t = t.replaceAll(RegExp(r'\S+@\S+'), ' ');
    t = t.replaceAll(RegExp(r'https?://\S+|www\.\S+', caseSensitive: false), ' ');
    t = t.replaceAll(RegExp(r'[0-9०-९০-৯੦-੯૦-૯೦-೯౦-౯௦-௯۰-۹٠-٩]+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length > maxLength) t = t.substring(0, maxLength).trim();
    return t;
  }

  /// Adds [text] when the engine did not understand it. Returns the stored
  /// text, or null when nothing was stored (understood, empty after
  /// cleaning, or already collected).
  String? add(String text, AssistantReply reply) {
    if (reply.understood) return null;
    final clean = sanitize(text);
    if (clean.length < 2) return null;
    final key = normalize(clean);
    if (_items.any((e) => normalize(e) == key)) return null;
    if (_items.length >= maxItems) _items.removeAt(0);
    _items.add(clean);
    return clean;
  }

  static String normalize(String s) => RuleEngine.normalize(s);

  List<String> get items => List.unmodifiable(_items);
  void clear() => _items.clear();
}

/// Names of the cities the assistant can pick up (for tests and help text).
List<String> get assistantCityNames => [for (final c in indianCities) c.name];
