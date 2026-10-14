/// The one place that names the app (Task: name preparation).
///
/// Everything a person can read comes from here: the strings (every `{app}`
/// in the 12 translation tables), the splash screen and role screen, the
/// share and invoice texts, the Terms and Privacy pages in `hosting/`, the
/// Android and iOS label, the web title and the web manifest. To rename the
/// app change the values below and run `dart run tool/apply_app_info.dart`;
/// docs/NAMING.md lists every file and the steps. Pure Dart: no imports, so
/// the tool can read it.
class AppInfo {
  AppInfo._();

  /// The display name, as written in Latin letters.
  static const String name = 'Load 20';

  /// One line under the name, in English.
  static const String tagline = 'Maal bhejo, bharosa ke saath';

  /// How the name is written in each language. Order (same as `AppLanguage`):
  /// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur. A language that
  /// reads Latin letters keeps the Latin name.
  static const List<String> nameInLanguage = [
    name,
    'लोड 20',
    name,
    'ಲೋಡ್ 20',
    'லோட் 20',
    'లోడ్ 20',
    'लोड 20',
    'લોડ 20',
    'লোড 20',
    'ਲੋਡ 20',
    'لوڈ 20',
    'لوڈ 20',
  ];

  /// The tagline in the 12 languages (same order).
  static const List<String> taglines = [
    tagline,
    'माल भेजो, भरोसे के साथ',
    'Maal bhejo, bharosa ke saath',
    'ಸರಕು ಕಳುಹಿಸಿ, ನಂಬಿಕೆಯೊಂದಿಗೆ',
    'சரக்கை அனுப்புங்கள், நம்பிக்கையுடன்',
    'సరుకు పంపండి, నమ్మకంతో',
    'माल पाठवा, विश्वासाने',
    'માલ મોકલો, ભરોસા સાથે',
    'মাল পাঠান, ভরসার সঙ্গে',
    'ਮਾਲ ਭੇਜੋ, ਭਰੋਸੇ ਨਾਲ',
    'مال بھیجیں، بھروسے کے ساتھ',
    'مال بھیجیں، بھروسے کے ساتھ',
  ];

  /// One line about what the app is, for the web page and the store listings.
  static const String description = 'Book trucks and move cargo across India. Customers, drivers and transporters chat and call inside the app.';

  /// Replaces the `{app}` token of a translation with the name in language [index].
  static String fill(String text, int index) => text.contains('{app}') ? text.replaceAll('{app}', nameInLanguage[index]) : text;
}

/// Shown in Settings. Keep equal to `version:` in pubspec.yaml (a test checks).
const String appVersion = '1.0.0+1';
