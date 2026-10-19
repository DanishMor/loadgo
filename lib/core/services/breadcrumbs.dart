import 'package:flutter/widgets.dart';

/// Removes personal data from text that goes into a log (MASTER-6 Task 42):
/// e-mail and UPI ids, links, phone numbers, Aadhaar, PAN, GST, vehicle
/// numbers, OTP codes, coordinates, long digit runs, bank branch codes, tokens
/// and Firebase user ids.
class Redactor {
  Redactor._();

  /// A cleaned one-line text for any error or object, for debug output and crash reports.
  static String safe(Object? error, {int maxLength = 500}) => clean('$error', maxLength: maxLength);

  static final _rules = <(RegExp, String)>[
    // Part 5 (H15): keys and header values first, so nothing below can leave half of one behind.
    (RegExp(r'rzp_(?:live|test)_\w+'), '#key'), // payment gateway keys
    (RegExp(r'AIza[\w-]{30,}'), '#key'), // Google API keys
    (RegExp(r'\bgh[pousr]_\w{20,}'), '#token'), // GitHub tokens
    (RegExp(r'\bBearer\s+\S+', caseSensitive: false), 'Bearer #'), // Authorization header values
    (RegExp(r'-----BEGIN[^-]*PRIVATE KEY-----'), '#key'), // private key blocks
    (RegExp(r'upi://\S+', caseSensitive: false), ' '), // UPI payment links
    (RegExp(r'\S+@\S+'), ' '), // e-mail and UPI ids
    (RegExp(r'https?://\S+|www\.\S+', caseSensitive: false), ' '), // links
    (RegExp(r'\beyJ[\w-]+\.[\w-]+\.[\w-]*'), '#token'), // sign-in tokens (JWT)
    (RegExp(r'\b[\w-]{16,}(?::[\w-]{16,})+'), '#token'), // push tokens (id:key)
    (RegExp(r'\b[A-Z]{4}0[A-Z0-9]{6}\b'), '#ifsc'), // bank branch codes
    (RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b'), '#pan'),
    (RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b'), '#gst'),
    (RegExp(r'\b[A-Z]{2}[ -]?\d{1,2}[ -]?[A-Z]{1,3}[ -]?\d{4}\b'), '#vehicle'),
    (RegExp(r'(otp|code|pin)\W{0,3}\d{4,8}', caseSensitive: false), r'$1 #'),
    (RegExp(r'[-+]?\d{1,3}\.\d{4,}\s*,\s*[-+]?\d{1,3}\.\d{4,}'), '#geo'),
    (RegExp(r'(?:\+?\d[\s-]?){7,}\d'), '#'), // phones, Aadhaar with spaces, long ids
    (RegExp(r'\b\d{6}\b'), '#'), // a bare 6-digit code (login or trip code, PIN code)
    (RegExp(r'\b[A-Za-z0-9]{28}\b'), '#uid'), // Firebase user ids
    (RegExp(r'\b(?=[\w-]*\d)[\w-]{32,}'), '#token'), // other long ids with digits (verification ids, keys)
  ];

  static const _scanLimit = 4000;

  static String clean(String text, {int maxLength = 300}) {
    // Part 5 (H15): cut first. The patterns below can take quadratic time on a very long unbroken text (200 000 letters took minutes),
    // and an error message must never be able to freeze the app while it is being logged. The tail is not needed: the result is short anyway.
    var t = text.length > _scanLimit ? text.substring(0, _scanLimit) : text;
    for (final (re, to) in _rules) {
      t = t.replaceAllMapped(re, (m) => to.contains(r'$1') ? to.replaceAll(r'$1', m.group(1) ?? '') : to);
    }
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maxLength ? t.substring(0, maxLength).trim() : t;
  }
}

/// The last few things the app did (screen opened, button used) so a crash
/// report shows the path to it. Holds only short, fixed labels: route names
/// and action names, never typed text, ids or names.
class Breadcrumbs {
  Breadcrumbs._();

  static const capacity = 25;
  static final List<String> _items = [];

  static List<String> get items => List.unmodifiable(_items);

  /// Adds one label (cleaned, at most 40 characters).
  static void add(String label) {
    final l = Redactor.clean(label, maxLength: 40);
    if (l.isEmpty) return;
    _items.add(l);
    if (_items.length > capacity) _items.removeAt(0);
  }

  /// The trail as one line, newest last, at most [maxLength] characters
  /// (older steps are cut first).
  static String trail({int maxLength = 600}) {
    var s = _items.join(' > ');
    while (s.length > maxLength && s.contains(' > ')) {
      s = s.substring(s.indexOf(' > ') + 3);
    }
    return s.length > maxLength ? s.substring(s.length - maxLength) : s;
  }

  static void clear() => _items.clear();
}

/// Records every screen the app opens or returns to, by route name only.
class BreadcrumbObserver extends NavigatorObserver {
  String _name(Route<dynamic>? r) {
    final n = r?.settings.name;
    if (n != null && n.isNotEmpty && n != '/') return n;
    // Routes are anonymous here: the page widget's type is a fixed label.
    return r == null ? '' : r.runtimeType.toString().replaceAll(RegExp(r'<.*>'), '');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => Breadcrumbs.add('open ${_name(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => Breadcrumbs.add('back ${_name(previousRoute)}');
}
