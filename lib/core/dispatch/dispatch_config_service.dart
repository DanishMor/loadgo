import 'package:flutter/foundation.dart';

import '../services/backend.dart';
import '../services/ttl_cache.dart';
import 'dispatch_models.dart';

/// Reads `config/dispatch` (rings, delays, accept time, bid window). Everything is
/// sanitised by [DispatchConfig.fromMap]; offline or without the document the defaults apply.
class DispatchConfigService {
  DispatchConfigService._();

  static final ValueNotifier<DispatchConfig> notifier = ValueNotifier(DispatchConfig.defaults);
  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));

  static DispatchConfig get current => notifier.value;

  static Future<void> refresh({bool force = false}) async {
    try {
      await _cache.run(() async {
        final snap = await Backend.db.collection('config').doc('dispatch').get();
        notifier.value = DispatchConfig.fromMap(snap.data());
      }, force: force);
    } catch (_) {
      // Offline or signed out: keep the last value (the defaults at first).
    }
  }

  @visibleForTesting
  static void reset() {
    notifier.value = DispatchConfig.defaults;
    _cache.invalidate();
  }
}
