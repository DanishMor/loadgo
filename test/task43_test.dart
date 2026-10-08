import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/l10n/share_nav_strings.dart';
import 'package:transport_app/core/models/booking.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/share/share_links.dart';
import 'package:transport_app/core/share/share_widgets.dart';
import 'package:transport_app/core/share_text.dart';
import 'package:transport_app/core/widgets/booking_widgets.dart';
import 'package:transport_app/core/widgets/load_card.dart';

Booking booking(String status) => Booking(
      id: 'b1', loadId: 'L1', driverId: 'd1', vehicleId: 'v', customerId: 'c1', status: status, pickup: 'Pune', drop: 'Delhi',
      cargoType: 'x', weight: 1, vehicleType: '20ft', budget: null, pickupDate: null, notes: '', vehicleNumber: 'MH12AB1',
      driverName: 'Ravi', driverPhone: '9876543210', timeline: const {},
    );

void main() {
  setUp(() {
    languageNotifier.value = AppLanguage.english;
    ShareLinks.host = 'loadgo-defc2.web.app';
  });

  group('ShareLinks', () {
    test('builds and parses a load link', () {
      expect(ShareLinks.loadLink('abc123'), 'https://loadgo-defc2.web.app/load/abc123');
      expect(ShareLinks.parseLoadId(ShareLinks.loadLink('abc123')), 'abc123');
      expect(ShareLinks.parseLoadId('  https://loadgo-defc2.web.app/load/abc123  '), 'abc123');
    });

    test('the host is configurable', () {
      ShareLinks.host = 'loadgo.in';
      expect(ShareLinks.loadLink('x1'), 'https://loadgo.in/load/x1');
    });

    test('odd links give no id', () {
      for (final bad in [null, '', 'abc', 'ftp://h/load/1', 'https://h/load', 'https://h/load/', 'https://h/loads/1', 'https://h/load/1/2', 'https://h/load/${'a' * 70}']) {
        expect(ShareLinks.parseLoadId(bad), isNull, reason: '$bad');
      }
    });

    test('an id with odd characters round-trips', () {
      expect(ShareLinks.parseLoadId(ShareLinks.loadLink('a b')), 'a b');
    });

    test('WhatsApp uri carries the encoded text', () {
      final u = ShareLinks.whatsAppUri('Delhi -> Pune\nhttps://x/load/1');
      expect(u.host, 'wa.me');
      expect(u.queryParameters['text'], 'Delhi -> Pune\nhttps://x/load/1');
    });
  });

  group('PhoneVisibility (Task 68: numbers stay private)', () {
    test('no status ever shows the other party\'s number', () {
      for (final s in [null, '', 'open', 'accepted', 'driver_arriving', 'loading', 'picked_up', 'in_transit', 'unloading', 'delivered', 'cancelled']) {
        expect(PhoneVisibility.canShow(s), isFalse, reason: '$s');
        expect(PhoneVisibility.visiblePhone(s, '123'), '', reason: '$s');
      }
    });

    test('share texts carry the driver name but never a phone number', () {
      for (final s in ['accepted', 'in_transit', 'delivered', 'cancelled']) {
        expect(bookingShareText(booking(s)), isNot(contains('9876543210')), reason: s);
        expect(bookingShareText(booking(s)), contains('Ravi'), reason: s);
      }
    });
  });

  group('NavLinks', () {
    test('place name link has no key', () {
      final u = NavLinks.directions(place: 'Jaipur, Rajasthan');
      expect(u.host, 'www.google.com');
      expect(u.path, '/maps/dir/');
      expect(u.queryParameters, {'api': '1', 'destination': 'Jaipur, Rajasthan', 'travelmode': 'driving'});
      expect(u.queryParameters.containsKey('key'), isFalse);
    });

    test('coordinates win over the name', () {
      final u = NavLinks.directions(place: 'x', lat: 26.9124, lng: 75.7873);
      expect(u.queryParameters['destination'], '26.912400,75.787300');
    });
  });

  group('widgets', () {
    Widget app(Widget child) => MaterialApp(home: LanguageScope(notifier: languageNotifier, child: Scaffold(body: SingleChildScrollView(child: child))));

    testWidgets('booking summary shows the driver name and never a phone number or a dialer button', (t) async {
      for (final status in ['accepted', 'in_transit', 'cancelled']) {
        await t.pumpWidget(app(BookingSummary(booking: booking(status), showDriver: true)));
        expect(find.textContaining('9876543210'), findsNothing, reason: status);
        expect(find.byKey(const ValueKey('confirmedCall')), findsNothing, reason: status);
        expect(find.textContaining('Ravi'), findsOneWidget, reason: status);
      }
    });

    testWidgets('load card share menu offers share, WhatsApp and copy', (t) async {
      final load = Load(
        id: 'L1', shipperId: 'c1', pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft',
        budget: 25000, pickupDate: DateTime(2026, 10, 5), notes: '', status: 'open', createdAt: Timestamp.now(),
      );
      await t.pumpWidget(app(LoadCard(load: load)));
      await t.tap(find.byKey(const ValueKey('loadShare_L1')));
      await t.pumpAndSettle();
      expect(find.text('Share…'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Copy text and link'), findsOneWidget);
    });

    testWidgets('navigate button renders its label', (t) async {
      await t.pumpWidget(app(const NavigateButton(label: 'Navigate to drop', place: 'Delhi')));
      expect(find.text('Navigate to drop'), findsOneWidget);
    });
  });

  test('strings have 12 non-empty languages', () {
    for (final e in shareNavStrings.entries) {
      expect(e.value.length, 12, reason: e.key);
      expect(e.value.every((s) => s.isNotEmpty), isTrue, reason: e.key);
    }
  });
}
