/// Public pages for the Play Store listing and the app (hosted from `hosting/`
/// on Firebase Hosting). The base can be changed in `config/app.policyBaseUrl`.
class PolicyLinks {
  PolicyLinks._();

  static const defaultBase = 'https://loadgo-defc2.web.app';
  static String _base = defaultBase;

  static String get base => _base;

  /// Accepts only a plain https URL (no spaces, no query, at most 200
  /// characters); anything else, or null, goes back to the default.
  static String? clean(Object? raw) {
    if (raw is! String) return null;
    final t = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (t.isEmpty || t.length > 200 || t.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(t);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.hasQuery || uri.hasFragment) return null;
    return t;
  }

  static void setBase(Object? raw) => _base = clean(raw) ?? defaultBase;

  static String privacy([String? base]) => '${base ?? _base}/privacy';
  static String terms([String? base]) => '${base ?? _base}/terms';
  static String deleteAccount([String? base]) => '${base ?? _base}/delete-account';
}
