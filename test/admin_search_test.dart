import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/admin/admin_search_screen.dart';
import 'package:transport_app/core/admin/admin_search.dart';
import 'package:transport_app/core/admin/staff_roles.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';

import 'test_utils.dart';

/// MASTER-6 Task 10: admin global search.
void main() {
  Map<AdminLookup, String> plan(String q, {String? role = 'super'}) => AdminSearch.plan(q, role: role).lookups;

  test('classification: booking id, LR number, vehicle number, phone, name', () {
    expect(plan('aB3dE5fG7hJ9kL1mN2pQ'), {AdminLookup.booking: 'aB3dE5fG7hJ9kL1mN2pQ'});
    expect(plan('tr-2026-000012'), {AdminLookup.lr: 'TR-2026-000012'});
    expect(plan('mh 12 ab 1234'), {AdminLookup.vehicle: 'MH12AB1234'});
    expect(plan('+91 98765 43210'), {AdminLookup.phone: '+919876543210'});
    expect(plan('09876543210'), {AdminLookup.phone: '+919876543210'});
    expect(plan('Ravi Kumar'), {AdminLookup.name: 'Ravi Kumar'});
    expect(plan('रवि'), {AdminLookup.name: 'रवि'});
  });

  test('too short, too long and junk give no lookup', () {
    expect(plan('ab'), isEmpty);
    expect(plan('   '), isEmpty);
    expect(plan('x' * 41), isEmpty);
    expect(plan('12345'), isEmpty); // digits that are no mobile, plate or id
    expect(AdminSearch.plan('ab', role: 'super').isEmpty, isTrue);
  });

  test('a vehicle lookup follows the role: finance and unknown roles cannot', () {
    expect(plan('MH12AB1234', role: StaffRole.verifier), isNotEmpty);
    expect(plan('MH12AB1234', role: StaffRole.support), isNotEmpty);
    expect(plan('MH12AB1234', role: StaffRole.finance), isEmpty);
    expect(plan('Ravi Kumar', role: StaffRole.finance), isNotEmpty); // people stay searchable for every role
  });

  test('name spellings: as typed, Capitalised, Title Case', () {
    expect(AdminSearch.nameVariants('ravi kumar'), containsAll(['ravi kumar', 'Ravi kumar', 'Ravi Kumar']));
    expect(AdminSearch.nameVariants('RAVI').toSet(), {'RAVI', 'Ravi'});
  });

  test('the service finds each kind, never returns a phone, and an unknown id gives nothing', () async {
    final db = FakeFirebaseFirestore();
    Backend.useFakes(db: db, uid: () => 'a1');
    await db.collection('users').doc('u1').set({'name': 'Ravi Kumar', 'role': 'customer', 'phone': '+919876543210'});
    await db.collection('users').doc('u2').set({'driverName': 'Ravindra', 'role': 'driver', 'phone': '+919999999999'});
    await db.collection('bookings').doc('aB3dE5fG7hJ9kL1mN2pQ').set({'pickup': 'Delhi', 'drop': 'Jaipur', 'status': 'delivered', 'customerId': 'u1', 'driverId': 'u2'});
    await db.collection('vehicles').doc('v1').set({'number': 'MH12AB1234', 'type': 'Mini', 'status': 'active', 'ownerId': 'u2'});
    await db.collection('lrs').doc('lr1').set({'lrNo': 'TR-2026-000012', 'route': 'Delhi - Jaipur', 'status': 'issued', 'bookingId': 'aB3dE5fG7hJ9kL1mN2pQ'});
    Future<List<AdminHit>> find(String q) => AdminConsoleService.search(AdminSearch.plan(q, role: 'super'));
    expect((await find('Ravi')).map((h) => h.uid).toSet(), {'u1', 'u2'}); // a prefix: Ravi Kumar and Ravindra
    expect((await find('ravi')).map((h) => h.uid).toSet(), {'u1', 'u2'});
    expect((await find('Ravi K')).map((h) => h.uid), ['u1']);
    expect((await find('Ravin')).map((h) => h.uid), ['u2']);
    expect((await find('9876543210')).map((h) => h.uid), ['u1']);
    expect((await find('MH 12 AB 1234')).single.uid, 'u2');
    expect((await find('TR-2026-000012')).single.bookingId, 'aB3dE5fG7hJ9kL1mN2pQ');
    expect((await find('aB3dE5fG7hJ9kL1mN2pQ')).single.subtitle, contains('Delhi → Jaipur'));
    expect(await find('zZ9yY8xX7wW6vV5uU4tT'), isEmpty);
    for (final q in ['Ravi', '9876543210', 'MH12AB1234']) {
      for (final h in await find(q)) {
        expect('${h.title} ${h.subtitle}', isNot(contains('9876')));
      }
    }
  });

  testWidgets('the screen: short query warns, a hit shows its kind, no hit says so', (tester) async {
    var calls = 0;
    await tester.pumpWidget(LanguageScope(
      notifier: languageNotifier,
      child: MaterialApp(
        home: AdminSearchScreen(role: 'super', run: (p) async {
          calls++;
          return p.lookups.containsKey(AdminLookup.name) && p.lookups[AdminLookup.name] == 'Ravi' ? [const AdminHit(kind: AdminLookup.name, id: 'u1', title: 'Ravi Kumar', subtitle: 'customer', uid: 'u1')] : [];
        }),
      ),
    ));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('asQuery')), 'ab');
    await tester.tap(find.byKey(const ValueKey('asGo')));
    await settle(tester);
    expect(find.byKey(const ValueKey('asShort')), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byKey(const ValueKey('asQuery')), 'Ravi');
    await tester.tap(find.byKey(const ValueKey('asGo')));
    await settle(tester);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Person · customer'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('asQuery')), 'Nobody');
    await tester.tap(find.byKey(const ValueKey('asGo')));
    await settle(tester);
    expect(find.byKey(const ValueKey('asNone')), findsOneWidget);
  });
}
