import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../offers/offers_switch.dart';
import 'backend.dart';
import 'ttl_cache.dart';

/// Reads and writes the `config/offers` switches (default all OFF).
class OffersSwitchService {
  OffersSwitchService._();

  static final ValueNotifier<OffersSwitch> notifier = ValueNotifier(OffersSwitch.allOff);
  static final TtlCache _cache = TtlCache(const Duration(minutes: 15));

  static OffersSwitch get current => notifier.value;

  static Future<void> refresh({bool force = false}) async {
    try {
      await _cache.run(() async {
        final snap = await Backend.db.collection('config').doc('offers').get();
        notifier.value = OffersSwitch.fromMap(snap.data());
      }, force: force);
    } catch (_) {
      // Offline or signed out: keep the last value (OFF at first).
    }
  }

  /// Super admin only (rules). Merges so the referral bonus stays.
  static Future<void> save(OffersSwitch s) async {
    await Backend.db.collection('config').doc('offers').set(s.toMap(), SetOptions(merge: true));
    notifier.value = s;
  }

  @visibleForTesting
  static void reset() {
    notifier.value = OffersSwitch.allOff;
    _cache.invalidate();
  }
}
