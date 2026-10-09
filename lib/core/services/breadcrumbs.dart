import 'package:flutter/widgets.dart';

/// Removes personal data from text that goes into a log (MASTER-6 Task 42):
/// e-mail and UPI ids, links, phone numbers, Aadhaar, PAN, GST, vehicle
/// numbers, OTP codes, coordinates, long digit runs and Firebase user ids.
class Redactor {
  Redactor._();

  static final _rules = <(RegExp, String)>[
    (RegExp(r'\S+@\S+'), ' '), // e-mail and UPI ids
    (RegExp(r'https?://\S+|www\.\S+', caseSensitive: false), ' '), // links
    (RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b'), '#pan'),
    (RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]\b'), '#gst'),
    (RegExp(r'\b[A-Z]{2}[ -]?\d{1,2}[ -]?[A-Z]{1,3}[ -]?\d{4}\b'), '#vehicle'),
    (RegExp(r'(otp|code|pin)\W{0,3}\d{4,8}', caseSensitive: false), r'$1 #'),
    (RegExp(r'[-+]?\d{1,3}\.\d{4,}\s*,\s*[-+]?\d{1,3}\.\d{4,}'), '#geo'),
    (RegExp(r'(?:\+?\d[\s-]?){7,}\d'), '#'), // phones, Aadhaar with spaces, long ids
    (RegExp(r'\b[A-Za-z0-9]{28}\b'), '#uid'), // Firebase user ids
  ];

  static String clean(String text, {int maxLength = 300}) {
    var t = text;
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
