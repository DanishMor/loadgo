import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/share/business_card.dart';
import 'package:transport_app/core/theme/app_theme.dart';

void main() {
  const fleetUser = {
    'companyName': 'Asha Roadlines',
    'name': 'Asha Verma',
    'phone': '+919876543210',
    'verified': true,
    'fleet': {'officeCity': 'Jaipur', 'routes': ['Jaipur - Delhi', 'Jaipur - Mumbai'], 'vehicleTypes': ['20ft', '32ft'], 'vehicleCount': 12},
  };

  group('data', () {
    test('a transporter card uses the company, city, routes, trucks and the verified mark', () {
      final d = BusinessCardData.fromUser(fleetUser);
      expect(d.name, 'Asha Roadlines');
      expect(d.city, 'Jaipur');
      expect(d.routes, ['Jaipur - Delhi', 'Jaipur - Mumbai']);
      expect(d.vehicleCount, 12);
      expect(d.verified, isTrue);
    });

    test('a driver card falls back to the driver name, then the plain name', () {
      expect(BusinessCardData.fromUser({'driverName': 'Ramesh', 'name': 'R'}).name, 'Ramesh');
      expect(BusinessCardData.fromUser({'name': 'Plain'}).name, 'Plain');
      expect(BusinessCardData.fromUser({}).isEmpty, isTrue);
      expect(BusinessCardData.fromUser(null).isEmpty, isTrue);
    });

    test('damaged or huge profile fields are tidied: lists capped, strings cut, counts checked', () {
      final d = BusinessCardData.fromUser({
        'name': 'N' * 200,
        'fleet': {'routes': [for (var i = 0; i < 10; i++) 'Route $i ${'x' * 80}'], 'vehicleTypes': [1, null, '  ', '20ft'], 'vehicleCount': -3},
      });
      expect(d.name.length, 60);
      expect(d.routes.length, BusinessCardData.maxRoutes);
      expect(d.routes.first.length, 40);
      expect(d.vehicleTypes, ['20ft']);
      expect(d.vehicleCount, 0);
      expect(BusinessCardData.fromUser({'name': 'A', 'fleet': 'junk', 'verified': 'yes'}).verified, isFalse);
    });

    test('the text version carries the phone only when the data has one', () {
      final d = BusinessCardData.fromUser(fleetUser);
      final withPhone = d.asText((n) => '$n trucks');
      expect(withPhone, contains('+919876543210'));
      expect(withPhone, contains('12 trucks'));
      final without = BusinessCardData(name: d.name, city: d.city, routes: d.routes, vehicleCount: d.vehicleCount).asText((n) => '$n trucks');
      expect(without, isNot(contains('9876')));
    });
  });

  Widget app(Widget child) => MaterialApp(theme: AppTheme.build(Brightness.light), home: child);

  setUp(() => languageNotifier.value = AppLanguage.english);

  testWidgets('the phone is hidden until the switch is turned on, and sharing hands over a picture and the text', (tester) async {
    Uint8List? png;
    String? text;
    await tester.pumpWidget(app(BusinessCardScreen(profile: fleetUser, onShare: (p, t) async {
      png = p;
      text = t;
    })));
    await tester.pumpAndSettle();
    expect(find.text('Asha Roadlines'), findsOneWidget);
    expect(find.text('12 trucks'), findsOneWidget);
    expect(find.text('+919876543210'), findsNothing);
    expect(find.text('Verified on Load 20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bizShare')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the picture is made on a real clock
    await tester.pump();
    expect(text, isNot(contains('9876')), reason: 'the phone is off');

    await tester.tap(find.byKey(const ValueKey('bizPhoneSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('+919876543210'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bizShare')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the picture is made on a real clock
    await tester.pump();
    expect(text, contains('+919876543210'));
    expect(png, isNotNull);
  });

  testWidgets('a person without a phone number cannot turn the switch on; an empty profile asks to fill it in', (tester) async {
    await tester.pumpWidget(app(const BusinessCardScreen(profile: {'name': 'No Phone'})));
    await tester.pumpAndSettle();
    final sw = tester.widget<SwitchListTile>(find.byKey(const ValueKey('bizPhoneSwitch')));
    expect(sw.onChanged, isNull);
    await tester.pumpWidget(app(BusinessCardScreen(key: UniqueKey(), profile: const {})));
    await tester.pumpAndSettle();
    expect(find.text('Fill in your profile first, then your card is ready.'), findsOneWidget);
  });

  testWidgets('a failing share says so instead of crashing', (tester) async {
    await tester.pumpWidget(app(BusinessCardScreen(profile: fleetUser, onShare: (p, t) async => throw StateError('no app'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bizShare')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the picture is made on a real clock
    await tester.pump();
    expect(find.text('Could not share the card. Try again.'), findsOneWidget);
  });

  testWidgets('narrow screen with big text: the card scrolls, nothing overflows', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(2.0)), child: app(const BusinessCardScreen(profile: fleetUser))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
