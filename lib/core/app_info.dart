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
  static const String name = 'LoadGo';

  /// One line under the name, in English.
  static const String tagline = 'Truck & Cargo Booking';

  /// How the name is written in each language. Order (same as `AppLanguage`):
  /// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur. A language that
  /// reads Latin letters keeps the Latin name.
  static const List<String> nameInLanguage = [
    name,
    'लोडगो',
    name,
    'ಲೋಡ್‌ಗೋ',
    'லோடுகோ',
    'లోడ్‌గో',
    'लोडगो',
    'લોડગો',
    'লোডগো',
    'ਲੋਡਗੋ',
    'لوڈگو',
    'لوڈگو',
  ];

  /// The tagline in the 12 languages (same order).
  static const List<String> taglines = [
    tagline,
    'ट्रक और कार्गो बुकिंग',
    'Truck aur Cargo Booking',
    'ಟ್ರಕ್ ಮತ್ತು ಕಾರ್ಗೋ ಬುಕ್ಕಿಂಗ್',
    'டிரக் மற்றும் சரக்கு முன்பதிவு',
    'ట్రక్ మరియు కార్గో బుకింగ్',
    'ट्रक आणि कार्गो बुकिंग',
    'ટ્રક અને કાર્ગો બુકિંગ',
    'ট্রাক ও কার্গো বুকিং',
    'ਟਰੱਕ ਅਤੇ ਕਾਰਗੋ ਬੁਕਿੰਗ',
    'ٹرٛک تہٕ کارگو بُکِنگ',
    'ٹرک اور کارگو بکنگ',
  ];

  /// One line about what the app is, for the web page and the store listings.
  static const String description = 'Book trucks and move cargo across India. Customers, drivers and transporters chat and call inside the app.';

  /// Replaces the `{app}` token of a translation with the name in language [index].
  static String fill(String text, int index) => text.contains('{app}') ? text.replaceAll('{app}', nameInLanguage[index]) : text;
}

/// Shown in Settings. Keep equal to `version:` in pubspec.yaml (a test checks).
const String appVersion = '1.0.0+1';
