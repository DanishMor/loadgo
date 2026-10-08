/// Finds phone numbers, UPI ids, other apps and "call me" in a chat message
/// (Task 68). Pure, offline, no AI: a list of patterns plus a number-chain
/// scan that also understands spaced, dotted, Devanagari, keycap-emoji and
/// spelled-out digits ("nau aath teen ..."), in English, Hindi and Hinglish.
///
/// It runs on the phone BEFORE a message is sent. It cannot be perfect (a
/// determined person can always invent a new trick) and the Firestore rules
/// repeat the simplest checks (a long digit run, an "@"), so a modified app
/// cannot send those either. LATER(paid): a server-side check (Cloud
/// Functions) for everything else.
library;

enum ContactKind {
  /// A phone number (digits, spaced, dotted, spelled out).
  phone,

  /// A UPI id or any "name@handle".
  upi,

  /// WhatsApp, Telegram, a link, "call me", "send your number".
  app,

  /// Paying outside the app.
  payment,
}

class ContactFilter {
  ContactFilter._();

  /// The first kind of contact detail found in [text], or null when the text
  /// looks fine. [recent] are the sender's own latest messages (newest
  /// first): a number split over several messages is caught when the
  /// pieces together make one.
  static ContactKind? check(String text, {Iterable<String> recent = const []}) {
    final own = _scan(text);
    if (own != null) return own;
    final before = recent.take(3).toList().reversed.toList();
    if (before.isEmpty) return null;
    final joined = _scan([...before, text].join(' '));
    return joined == ContactKind.phone ? joined : null;
  }

  static bool looksLikeContact(String text, {Iterable<String> recent = const []}) => check(text, recent: recent) != null;

  // ---- normalising ----

  // First code point of each script's digit block (0..9 follow in order).
  static const _digitBlocks = [0x0660, 0x06F0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0xFF10];

  /// Lower case, every script's digits turned into 0-9, keycap emoji marks and
  /// zero-width characters removed.
  static String normalise(String input) {
    final out = StringBuffer();
    for (final r in input.runes) {
      if (r == 0xFE0F || r == 0x20E3 || r == 0x200B || r == 0x200C || r == 0x200D || r == 0x2060 || r == 0xAD) continue;
      var mapped = false;
      for (final base in _digitBlocks) {
        if (r >= base && r <= base + 9) {
          out.writeCharCode(0x30 + r - base);
          mapped = true;
          break;
        }
      }
      if (!mapped) out.write(String.fromCharCode(r).toLowerCase());
    }
    return out.toString();
  }

  // ---- patterns ----

  static final _upi = RegExp(r'[a-z0-9._\-]+\s?@\s?[a-z]{2,}');
  static final _link = RegExp(r'https?\s?:\s?//|www\s?\.|\b(?:t\.me|wa\.me|bit\.ly|tinyurl)\b');
  static final _appNames = RegExp(r'whatsapp|whatsap|watsapp|whtsapp|wtsapp|telegram|telegrm|instagram|facebook|messenger');
  static final _appWords = RegExp(r'\b(?:wa|whats\s?app|watsap|tg|insta|fb)\b');
  static final _askPhrases = RegExp(
    r'call\s*me|call\s*(?:kar|kr)(?:o|na|do|dena|lo)?\b|phone\s*(?:kar|kr)(?:o|na|do)?\b|fone\s*(?:kar|kr)(?:o|na)?\b|ring\s*me|contact\s*me|dm\s*me|text\s*me|'
    r'(?:mobile|mobil|phone|fone|contact|personal|direct|whats\s?app)\s*(?:no\.?|number|nmbr|nambar|num)\b|'
    r'(?:apna|apne|mera|meri|tera|teri|tumhara|aapka|aapke|your|my)\s*(?:mobile\s*|phone\s*|contact\s*)?(?:no\.?|number|nmbr|nambar|num)\b|'
    r'number\s*(?:share|send)\b|share\s*(?:your\s*)?number|'
    r'\bmy\s*(?:upi|gpay|phonepe|paytm)\b|\b(?:gpay|google\s*pay|phonepe|phone\s*pe|paytm|bhim)\s*(?:number|no\b|id\b)|'
    r'कॉल\s*कर|फ़?ोन\s*कर|फोन\s*नंबर|मोबाइल\s*नंबर|मोबाइल\s*नं|कॉन्टैक्ट|व्हाट्?स?एप|वॉट्?स?एप|व्हाट्सऐप|टेलीग्राम|अपना\s*नंबर|मेरा\s*नंबर|आपका\s*नंबर|तेरा\s*नंबर|नंबर\s*(?:दो|दे|दें|भेज|बता)',
  );
  static final _payOutside = RegExp(
    r'pay\s*(?:me\s*)?outside|outside\s*(?:the\s*)?app|direct\s*payment|pay\s*direct(?:ly)?|bahar\s*(?:se\s*)?payment|app\s*ke\s*bahar|'
    r'cash\s*(?:me|mein)\s*(?:de|do)\s*dena|(?:google\s*pay|phone\s*pe|gpay)\s*kar|ऐप\s*के\s*बाहर|बाहर\s*(?:से\s*)?पेमेंट|सीधे\s*पेमेंट',
  );
  // dd/mm/yyyy, yyyy-mm-dd, dd.mm.yy: dates are not phone numbers.
  static final _date = RegExp(
    r'\b(?:(?:19|20)\d\d[-/.](?:0?[1-9]|1[0-2])[-/.](?:0?[1-9]|[12]\d|3[01])|(?:0?[1-9]|[12]\d|3[01])[-/.](?:0?[1-9]|1[0-2])[-/.](?:(?:19|20)\d\d|\d\d))\b');

  // Number words. "do" and "ek" are ordinary words, so they only count inside a long chain.
  static const _wordDigits = <String, int>{
    'zero': 0, 'shunya': 0, 'sifar': 0, 'shoonya': 0, 'शून्य': 0, 'सिफर': 0, 'जीरो': 0,
    'one': 1, 'ek': 1, 'एक': 1,
    'two': 2, 'do': 2, 'दो': 2,
    'three': 3, 'teen': 3, 'tin': 3, 'तीन': 3,
    'four': 4, 'char': 4, 'chaar': 4, 'चार': 4,
    'five': 5, 'paanch': 5, 'panch': 5, 'pach': 5, 'पांच': 5, 'पाँच': 5,
    'six': 6, 'chhe': 6, 'chhah': 6, 'chha': 6, 'chah': 6, 'chhay': 6, 'छह': 6, 'छः': 6, 'छे': 6, 'छ': 6,
    'seven': 7, 'saat': 7, 'sat': 7, 'सात': 7,
    'eight': 8, 'aath': 8, 'ath': 8, 'आठ': 8,
    'nine': 9, 'nau': 9, 'nao': 9, 'नौ': 9, 'नो': 9,
  };
  static const _multipliers = <String, int>{'double': 1, 'dabal': 1, 'dubal': 1, 'डबल': 1, 'triple': 2, 'tripal': 2, 'ट्रिपल': 2};

  static final _word = RegExp(r'[a-z]+|[\u0900-\u097f]+|\d+');
  static final _digitsOnly = RegExp(r'^\d+$');
  static final _gap = RegExp(r'^[\s.,\-_/()+*#|;~]*$');
  // 10:30, 4:45 pm: a time of day is not a phone number.
  static final _time = RegExp(r'\b\d{1,2}\s?:\s?\d{2}\b(?:\s?(?:am|pm))?');

  // ---- scanning ----

  static ContactKind? _scan(String raw) {
    final t = normalise(raw);
    if (t.trim().isEmpty) return null;
    if (_upi.hasMatch(t)) return ContactKind.upi;
    if (_numberChain(t.replaceAll(_date, ' ').replaceAll(_time, ' '))) return ContactKind.phone;
    if (_link.hasMatch(t) || _appNames.hasMatch(t) || _appWords.hasMatch(t) || _askPhrases.hasMatch(t)) return ContactKind.app;
    // "w h a t s a p p", "t e l e g r a m": letters pulled apart with spaces or dots.
    final squashed = t.replaceAll(RegExp(r'[\s.\-_*]+'), '');
    if (_appNames.hasMatch(squashed)) return ContactKind.app;
    if (_payOutside.hasMatch(t)) return ContactKind.payment;
    return null;
  }

  /// True when a chain of digits, spelled-out digits and separators makes a
  /// phone number. A chain ends at any other word.
  static bool _numberChain(String t) {
    var full = StringBuffer();
    var multiplier = 0;
    var lastEnd = -1;
    var started = false;

    bool decide() {
      final ok = started && _looksLikePhone(full.toString());
      full = StringBuffer();
      multiplier = 0;
      started = false;
      return ok;
    }

    void add(String digits) {
      if (digits.isEmpty) return;
      full.write(digits[0] * (1 + multiplier));
      full.write(digits.substring(1));
      multiplier = 0;
      started = true;
    }

    for (final m in _word.allMatches(t)) {
      final w = m.group(0)!;
      final joined = lastEnd < 0 || _gap.hasMatch(t.substring(lastEnd, m.start));
      lastEnd = m.end;
      if (!joined && started && decide()) return true;
      if (_digitsOnly.hasMatch(w)) {
        add(w);
        continue;
      }
      final d = _wordDigits[w];
      if (d != null) {
        add('$d');
        continue;
      }
      final k = _multipliers[w];
      if (k != null) {
        multiplier = k;
        continue;
      }
      // Any other word ends the chain.
      if (decide()) return true;
    }
    return decide();
  }

  /// [full] is every digit of one chain. An Indian mobile number starts with
  /// 6-9 and has 10 digits, usually with +91 or a 0 in front; 8-9 digits that
  /// start like one are a piece of a number; a landline starts with 0.
  static bool _looksLikePhone(String full) {
    if (full.startsWith('0') && full.length >= 10 && full.length <= 11) return true; // landline or 0 + mobile
    var d = full;
    if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
    if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
    if (d.length < 8 || d.length > 12) return false;
    if (RegExp(r'^[6-9]').hasMatch(d)) return true;
    return d.startsWith('0') && d.length >= 10;
  }
}
