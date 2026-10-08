import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'ttl_cache.dart';

/// `config/support`, edited by an admin in the config editor:
/// `{"phone": "+911800...", "hours": "Mon-Sat 9am-6pm"}`. Without it the app
/// shows no call button. LATER(paid): a provider-managed support line.
class SupportConfig {
  final String phone;
  final String hours;

  const SupportConfig({this.phone = '', this.hours = ''});

  bool get hasPhone => phone.trim().isNotEmpty;

  /// Digits and a leading plus only: 7 to 15 digits.
  static bool validPhone(String s) => RegExp(r'^\+?[0-9]{7,15}$').hasMatch(s.replaceAll(RegExp(r'[\s-]'), ''));

  factory SupportConfig.fromMap(Map<String, dynamic>? m) {
    final phone = (m?['phone'] as String?)?.trim() ?? '';
    return SupportConfig(
      phone: validPhone(phone) ? phone : '',
      hours: (m?['hours'] as String?)?.trim() ?? '',
    );
  }

  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));
  static SupportConfig _last = const SupportConfig();
  static Object? _forDb; // a different Firestore instance (tests, sign-out) means a fresh read

  /// Read at most once in 15 minutes (MASTER-5 Task 12); [force] after an edit.
  static Future<SupportConfig> load({bool force = false}) async {
    if (!force && _cache.fresh && identical(_forDb, Backend.db)) return _last;
    try {
      _last = SupportConfig.fromMap((await Backend.db.collection('config').doc('support').get()).data());
      _cache.markFetched();
      _forDb = Backend.db;
    } catch (_) {
      // keep the last good value; try again next time
    }
    return _last;
  }

  @visibleForTesting
  static void reset() {
    _cache.invalidate();
    _last = const SupportConfig();
  }
}
