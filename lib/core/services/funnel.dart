import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_events.dart';
import 'backend.dart';

/// G8: the steps of a new user's first weeks. Each one is logged once per
/// person per phone as `funnel_<step>` with a role code only. No name, phone
/// number, address, id or amount ever goes in. docs/ANALYTICS.md.
enum FunnelStep {
  signup('funnel_signup'),
  profileDone('funnel_profile_done'),
  docsAdded('funnel_docs_added'),
  firstLoad('funnel_first_load'),
  firstBid('funnel_first_bid'),
  firstDelivery('funnel_first_delivery'),
  repeatLoad('funnel_repeat_load');

  final String event;
  const FunnelStep(this.event);
}

class Funnel {
  Funnel._();

  static String _key(String uid) => 'funnel_done_$uid';
  static String _countKey(String uid) => 'funnel_loads_$uid';

  /// Logs [step] the first time it happens for the signed-in person. Never throws.
  static Future<void> mark(FunnelStep step, {String? role}) async {
    try {
      final uid = Backend.uid;
      // Without the person's analytics consent nothing is logged and the step is not used up.
      if (uid == null || !AnalyticsEvents.consent) return;
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getStringList(_key(uid)) ?? const <String>[];
      if (done.contains(step.name)) return;
      await prefs.setStringList(_key(uid), [...done, step.name]);
      await AnalyticsEvents.log(step.event, params: {'role': ?role});
    } catch (_) {}
  }

  /// A load was posted: the first one is `funnel_first_load`, the second one `funnel_repeat_load`.
  static Future<void> loadPosted({String role = 'customer'}) async {
    try {
      final uid = Backend.uid;
      if (uid == null || !AnalyticsEvents.consent) return;
      final prefs = await SharedPreferences.getInstance();
      final n = (prefs.getInt(_countKey(uid)) ?? 0) + 1;
      await prefs.setInt(_countKey(uid), n);
      if (n == 1) await mark(FunnelStep.firstLoad, role: role);
      if (n >= 2) await mark(FunnelStep.repeatLoad, role: role);
    } catch (_) {}
  }
}
