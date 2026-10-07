import 'package:flutter/foundation.dart';

import '../features/features.dart';
import 'admin_console_service.dart';
import 'backend.dart';
import 'ttl_cache.dart';

/// Reads and writes `config/features` (pilot mode and feature flags).
class FeaturesService {
  FeaturesService._();

  static final ValueNotifier<Features> notifier = ValueNotifier(Features.pilotDefault);
  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));

  static Features get current => notifier.value;
  static bool isOn(String key) => notifier.value.isOn(key);

  static Future<void> refresh({bool force = false}) async {
    try {
      await _cache.run(() async {
        final snap = await Backend.db.collection('config').doc('features').get();
        notifier.value = Features.fromMap(snap.data());
      }, force: force);
    } catch (_) {
      // Offline or signed out: keep the last value (pilot defaults at first).
    }
  }

  /// Super admin only (rules: config/{doc}). Audited like other config writes.
  static Future<void> save(Features f) async {
    await AdminConsoleService.writeConfig('features', f.toMap());
    notifier.value = f;
  }

  @visibleForTesting
  static void reset() {
    notifier.value = Features.pilotDefault;
    _cache.invalidate();
  }
}
