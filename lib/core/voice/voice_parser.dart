/// Pure parsing of spoken Hindi / Hinglish / English text: amounts in rupees
/// ("पाँच हज़ार", "ten thousand", "dedh lakh") and routes ("Delhi se Jaipur").
library;

import '../pricing/cities.dart';

class VoiceRoute {
  final String? from;
  final String? to;
  const VoiceRoute({this.from, this.to});

  bool get isEmpty => from == null && to == null;

  @override
  String toString() => 'VoiceRoute($from -> $to)';
}

class VoiceParser {
  VoiceParser._();

  // ---------------------------------------------------------------- numbers

  static const _hindiUnits = <String>[
    '', 'एक', 'दो', 'तीन', 'चार', 'पाँच', 'छह', 'सात', 'आठ', 'नौ', 'दस', 'ग्यारह', 'बारह', 'तेरह', 'चौदह', 'पंद्रह', 'सोलह', 'सत्रह', 'अठारह', 'उन्नीस',
    'बीस', 'इक्कीस', 'बाईस', 'तेईस', 'चौबीस', 'पच्चीस', 'छब्बीस', 'सत्ताईस', 'अट्ठाईस', 'उनतीस',
    'तीस', 'इकतीस', 'बत्तीस', 'तैंतीस', 'चौंतीस', 'पैंतीस', 'छत्तीस', 'सैंतीस', 'अड़तीस', 'उनतालीस',
    'चालीस', 'इकतालीस', 'बयालीस', 'तैंतालीस', 'चौवालीस', 'पैंतालीस', 'छियालीस', 'सैंतालीस', 'अड़तालीस', 'उनचास',
    'पचास', 'इक्यावन', 'बावन', 'तिरपन', 'चौवन', 'पचपन', 'छप्पन', 'सत्तावन', 'अट्ठावन', 'उनसठ',
    'साठ', 'इकसठ', 'बासठ', 'तिरसठ', 'चौंसठ', 'पैंसठ', 'छियासठ', 'सड़सठ', 'अड़सठ', 'उनहत्तर',
    'सत्तर', 'इकहत्तर', 'बहत्तर', 'तिहत्तर', 'चौहत्तर', 'पचहत्तर', 'छिहत्तर', 'सतहत्तर', 'अठहत्तर', 'उनासी',
    'अस्सी', 'इक्यासी', 'बयासी', 'तिरासी', 'चौरासी', 'पचासी', 'छियासी', 'सत्तासी', 'अट्ठासी', 'नवासी',
    'नब्बे', 'इक्यानवे', 'बानवे', 'तिरानवे', 'चौरानवे', 'पंचानवे', 'छियानवे', 'सत्तानवे', 'अट्ठानवे', 'निन्यानवे',
  ];

  /// Other spellings a speech engine may give.
  static const _hindiVariants = <String, int>{
    'पांच': 5, 'छः': 6, 'छे': 6, 'पन्द्रह': 15, 'पंद्रा': 15, 'अठाईस': 28, 'नो': 9, 'चौबिस': 24, 'पच्चिस': 25, 'पैंतिस': 35,
    'चौतीस': 34, 'तेंतीस': 33, 'उन्तीस': 29, 'उन्नीस': 19, 'सैतीस': 37, 'चवालीस': 44, 'सैंतालिस': 47, 'पचपन': 55, 'अट्ठावन': 58,
  };

  static const _romanUnits = <String, int>{
    'ek': 1, 'do': 2, 'teen': 3, 'tin': 3, 'char': 4, 'chaar': 4, 'paanch': 5, 'panch': 5, 'pach': 5, 'chhe': 6, 'chhah': 6, 'cheh': 6, 'saat': 7, 'sat': 7,
    'aath': 8, 'ath': 8, 'nau': 9, 'das': 10, 'dus': 10, 'gyarah': 11, 'barah': 12, 'terah': 13, 'chaudah': 14, 'pandrah': 15,
    'solah': 16, 'satrah': 17, 'atharah': 18, 'unnis': 19, 'bees': 20, 'ikkis': 21, 'pachees': 25, 'tees': 30, 'chalis': 40, 'pachas': 50,
    'saath': 60, 'sattar': 70, 'assi': 80, 'nabbe': 90,
  };

  static const _english = <String, int>{
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fourty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  static final Map<String, int> _units = {
    for (var i = 1; i < _hindiUnits.length; i++) _hindiUnits[i]: i,
    ..._hindiVariants,
    ..._romanUnits,
    ..._english,
  };

  static const _hundred = {'सौ', 'सो', 'sau', 'sao', 'hundred'};
  static const _thousand = {'हज़ार', 'हजार', 'hazaar', 'hazar', 'hajar', 'thousand', 'k'};
  static const _lakh = {'लाख', 'lakh', 'lac', 'lakhs', 'laakh'};

  /// Fraction words that stand for a number by themselves.
  static const _fraction = {'डेढ़': 1.5, 'डेढ': 1.5, 'dedh': 1.5, 'dhed': 1.5, 'ढाई': 2.5, 'अढ़ाई': 2.5, 'dhai': 2.5, 'adhai': 2.5, 'dhaai': 2.5};
  static const _sava = {'सवा', 'sava', 'sawa'};
  static const _saade = {'साढ़े', 'साढे', 'saade', 'sade', 'saadhe'};

  static List<String> _tokens(String text) => text
      .toLowerCase()
      .replaceAll('₹', ' ')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}${m[2]}')
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}. ]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Whole rupees spoken in [text], or null when there is no amount.
  ///
  /// Reads digits ("5,000", "5 hazar"), English words ("ten thousand"),
  /// Hindi words ("पाँच हज़ार") and Hinglish ("paanch hazaar"), with
  /// dedh/dhai/sava/saade ("सवा लाख" = 1,25,000).
  static int? parseAmountRupees(String text) {
    double total = 0; // finished thousands/lakhs parts
    double chunk = 0; // hundreds being built (below a thousand)
    double current = 0; // last small number
    var seen = false;
    var half = false; // saade: add 0.5 to the next number
    var sava = false; // sava: 1.25 times the next unit word

    double small() => chunk + current;

    for (final t in _tokens(text)) {
      final digits = double.tryParse(t);
      if (digits != null) {
        current += digits;
        if (half) {
          current += 0.5;
          half = false;
        }
        seen = true;
      } else if (_fraction.containsKey(t)) {
        current += _fraction[t]!;
        seen = true;
      } else if (_sava.contains(t)) {
        sava = true;
        seen = true;
      } else if (_saade.contains(t)) {
        half = true;
        seen = true;
      } else if (_units.containsKey(t)) {
        current += _units[t]!;
        if (half) {
          current += 0.5;
          half = false;
        }
        seen = true;
      } else if (_hundred.contains(t)) {
        final base = current == 0 ? 1.0 : current;
        chunk += base * 100;
        current = 0;
        seen = true;
      } else if (_thousand.contains(t)) {
        final base = small() == 0 ? (sava ? 1.25 : 1.0) : small();
        total += base * 1000;
        chunk = 0;
        current = 0;
        sava = false;
        seen = true;
      } else if (_lakh.contains(t)) {
        final base = small() == 0 ? (sava ? 1.25 : 1.0) : small();
        total += base * 100000;
        chunk = 0;
        current = 0;
        sava = false;
        seen = true;
      }
    }
    if (!seen) return null;
    final value = total + small();
    if (value <= 0) return null;
    return value.round();
  }

  // ----------------------------------------------------------------- cities

  /// Devanagari spellings of common cities (the offline table is Latin).
  static const _hindiCities = <String, String>{
    'दिल्ली': 'Delhi', 'नई दिल्ली': 'Delhi', 'मुंबई': 'Mumbai', 'बंबई': 'Mumbai', 'कोलकाता': 'Kolkata', 'चेन्नई': 'Chennai',
    'बेंगलुरु': 'Bengaluru', 'बैंगलोर': 'Bengaluru', 'बेंगलूरु': 'Bengaluru', 'हैदराबाद': 'Hyderabad', 'अहमदाबाद': 'Ahmedabad', 'पुणे': 'Pune',
    'सूरत': 'Surat', 'जयपुर': 'Jaipur', 'लखनऊ': 'Lucknow', 'कानपुर': 'Kanpur', 'नागपुर': 'Nagpur', 'इंदौर': 'Indore', 'भोपाल': 'Bhopal',
    'विशाखापत्तनम': 'Visakhapatnam', 'पटना': 'Patna', 'वडोदरा': 'Vadodara', 'बड़ौदा': 'Vadodara', 'लुधियाना': 'Ludhiana', 'आगरा': 'Agra',
    'नासिक': 'Nashik', 'फरीदाबाद': 'Faridabad', 'मेरठ': 'Meerut', 'राजकोट': 'Rajkot', 'वाराणसी': 'Varanasi', 'बनारस': 'Varanasi',
    'श्रीनगर': 'Srinagar', 'जम्मू': 'Jammu', 'औरंगाबाद': 'Aurangabad', 'अमृतसर': 'Amritsar', 'प्रयागराज': 'Prayagraj', 'इलाहाबाद': 'Prayagraj',
    'रांची': 'Ranchi', 'जबलपुर': 'Jabalpur', 'ग्वालियर': 'Gwalior', 'कोयंबटूर': 'Coimbatore', 'विजयवाड़ा': 'Vijayawada', 'जोधपुर': 'Jodhpur',
    'मदुरै': 'Madurai', 'रायपुर': 'Raipur', 'कोटा': 'Kota', 'गुवाहाटी': 'Guwahati', 'चंडीगढ़': 'Chandigarh', 'चंडीगढ': 'Chandigarh',
    'मैसूर': 'Mysuru', 'भुवनेश्वर': 'Bhubaneswar', 'कोच्चि': 'Kochi', 'देहरादून': 'Dehradun', 'गुरुग्राम': 'Gurugram', 'गुड़गांव': 'Gurugram',
    'नोएडा': 'Noida', 'गाज़ियाबाद': 'Ghaziabad', 'गाजियाबाद': 'Ghaziabad', 'गोवा': 'Goa', 'उदयपुर': 'Udaipur', 'अजमेर': 'Ajmer', 'सिलीगुड़ी': 'Siliguri',
    'धनबाद': 'Dhanbad', 'जमशेदपुर': 'Jamshedpur', 'भिवंडी': 'Bhiwandi',
  };

  static final List<String> _hindiCityKeys = (_hindiCities.keys.toList()..sort((a, b) => b.length.compareTo(a.length)));

  /// Canonical city name found in [text] (Latin or Devanagari), or null.
  static String? cityIn(String text) {
    final t = text.trim();
    for (final k in _hindiCityKeys) {
      if (t.contains(k)) return _hindiCities[k];
    }
    return findCity(t)?.name;
  }

  static const _separators = [' से ', ' तक ', ' se ', ' tak ', ' to ', ' - ', ' -> ', ' ke liye '];

  /// "Delhi se Jaipur", "from Pune to Mumbai", "दिल्ली से जयपुर".
  /// A single city gives only [VoiceRoute.from] when said with "se"/"from",
  /// otherwise it is read as the pickup.
  static VoiceRoute parseRoute(String text) {
    var t = ' ${text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')} ';
    t = t.replaceFirst(' from ', ' ').replaceFirst(' से ', ' से ');
    for (final sep in _separators) {
      final i = t.indexOf(sep);
      if (i >= 0) {
        final a = cityIn(t.substring(0, i));
        final b = cityIn(t.substring(i + sep.length));
        if (a != null || b != null) return VoiceRoute(from: a, to: b);
      }
    }
    final one = cityIn(t);
    return VoiceRoute(from: one);
  }
}
