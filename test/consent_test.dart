import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/driver_consent_screen.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/user_settings.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/settings_service.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/driver/driver_location_sync.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() {
    db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'd1');
    DriverLocationSync.resetForTest();
    LocationService.useFakeCurrent(() async => (lat: 28.61, lng: 77.21));
  });
  tearDown(() => LocationService.useFakeCurrent(null));

  Future<Map<String, dynamic>> user() async => (await db.collection('users').doc('d1').get()).data() ?? {};

  test('consent off (default): nothing is saved', () async {
    expect(await DriverLocationSync.refresh(), isFalse);
    expect((await user()).containsKey('lastLocation'), isFalse);
  });

  test('consent on: location is saved; turning it off deletes it', () async {
    await SettingsService.saveConsents(const Consents(location: true));
    expect(await DriverLocationSync.refresh(), isTrue);
    expect((await user())['lastLocation'], isNotNull);

    await SettingsService.saveConsents(const Consents(location: false));
    final u = await user();
    expect(u.containsKey('lastLocation'), isFalse);
    expect((u['consents'] as Map)['location'], false);
    DriverLocationSync.resetForTest();
    expect(await DriverLocationSync.refresh(), isFalse);
  });

  test('the onboarding answer is stored and keeps the other consents', () async {
    await SettingsService.saveConsents(const Consents(analytics: true));
    await SettingsService.answerLocationConsent(true);
    var u = await user();
    expect(u['locationConsentAsked'], true);
    expect(u['consents'], {'location': true, 'analytics': true, 'marketing': false});
    await UserService.saveDriverLocation(1, 2);
    await SettingsService.answerLocationConsent(false);
    u = await user();
    expect((u['consents'] as Map)['location'], false);
    expect(u.containsKey('lastLocation'), isFalse);
  });

  testWidgets('consent screen: Allow and Not now both record the answer', (tester) async {
    languageNotifier.value = AppLanguage.english;
    await tester.pumpWidget(LanguageScope(notifier: languageNotifier, child: const MaterialApp(home: DriverConsentScreen())));
    expect(find.text('Use your location?'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('consentSkip')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    final u = await tester.runAsync(user);
    expect(u!['locationConsentAsked'], true);
    expect((u['consents'] as Map)['location'], false);
  });
}
