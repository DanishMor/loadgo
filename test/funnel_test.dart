import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport_app/core/services/analytics_events.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/settings_service.dart';
import 'package:transport_app/core/services/funnel.dart';

void main() {
  String? uid;
  late List<(String, Map<String, Object>)> sent;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    uid = 'u1';
    Backend.useFakes(db: FakeFirebaseFirestore(), uid: () => uid);
    sent = [];
    AnalyticsEvents.consent = true;
    AnalyticsEvents.testSink = (n, p) => sent.add((n, p));
  });
  tearDown(() {
    AnalyticsEvents.testSink = null;
    AnalyticsEvents.consent = false;
  });

  test('no consent: nothing is logged and the step is not used up', () async {
    AnalyticsEvents.consent = false;
    await Funnel.mark(FunnelStep.signup, role: 'driver');
    await Funnel.loadPosted();
    expect(sent, isEmpty);
    AnalyticsEvents.consent = true;
    await Funnel.mark(FunnelStep.signup, role: 'driver');
    expect(sent.length, 1);
  });

  test('saving the analytics choice applies it', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'u1');
    await db.collection('users').doc('u1').set({'role': 'driver'});
    await SettingsService.saveConsents(const Consents(analytics: true));
    expect(AnalyticsEvents.consent, isTrue);
    await SettingsService.saveConsents(const Consents());
    expect(AnalyticsEvents.consent, isFalse);
    await db.collection('users').doc('u1').set({'consents': {'analytics': true}}, SetOptions(merge: true));
    await SettingsService.loadConsents();
    expect(AnalyticsEvents.consent, isTrue);
  });

  test('a step is logged once per person with a role code only', () async {
    await Funnel.mark(FunnelStep.signup, role: 'driver');
    await Funnel.mark(FunnelStep.signup, role: 'driver');
    expect(sent.length, 1);
    expect(sent.single.$1, 'funnel_signup');
    expect(sent.single.$2, {'role': 'driver'});
  });

  test('another person on the same phone is counted on their own', () async {
    await Funnel.mark(FunnelStep.firstBid, role: 'driver');
    uid = 'u2';
    await Funnel.mark(FunnelStep.firstBid, role: 'driver');
    expect(sent.length, 2);
  });

  test('first load then repeat on the second one, nothing more after', () async {
    await Funnel.loadPosted();
    await Funnel.loadPosted();
    await Funnel.loadPosted();
    expect(sent.map((e) => e.$1), ['funnel_first_load', 'funnel_repeat_load']);
  });

  test('signed out logs nothing and never throws', () async {
    uid = null;
    await Funnel.mark(FunnelStep.profileDone);
    await Funnel.loadPosted();
    expect(sent, isEmpty);
  });

  test('every event name is valid for Analytics and no param can hold a name or number', () {
    for (final s in FunnelStep.values) {
      expect(AnalyticsEvents.validName(s.event), isTrue, reason: s.event);
    }
    expect(AnalyticsEvents.cleanParams({'role': 'fleet', 'phone': null}), {'role': 'fleet'});
  });
}
