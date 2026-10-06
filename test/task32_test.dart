import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/enterprise/validators.dart';
import 'package:transport_app/core/identity/kyc_auto_check.dart';
import 'package:transport_app/core/identity/profile_extras.dart';
import 'package:transport_app/core/models/business.dart';
import 'package:transport_app/core/models/fleet.dart';
import 'package:transport_app/core/services/admin_user_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/data_export_service.dart';
import 'package:transport_app/core/services/phone_change_service.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/core/settings/account_tools_screens.dart';
import 'package:transport_app/core/widgets/kyc_check_widgets.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'u1';

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'u1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  group('GSTIN checksum (K9)', () {
    test('a real-format number passes, a wrong check character fails', () {
      expect(isValidGstin('27AAPFU0939F1ZV'), isTrue);
      expect(isValidGstin(' 27aapfu0939f1zv '), isTrue);
      expect(isValidGstin('27AAPFU0939F1ZW'), isFalse);
      expect(isValidGstin('27AAPFU0939F1Z'), isFalse);
      expect(gstinCheckChar('27AAPFU0939F1Z'), 'V');
    });
  });

  group('profile extras (K6, K8, A5)', () {
    test('UPI id format and masking', () {
      expect(isValidUpiId('ravi.kumar@okaxis'), isTrue);
      expect(isValidUpiId('ravi@'), isFalse);
      expect(isValidUpiId('no spaces@bank'), isFalse);
      expect(maskUpiId('ravi.kumar@okaxis'), endsWith('@okaxis'));
      expect(maskUpiId('ravi.kumar@okaxis'), isNot(contains('kumar')));
      expect(maskAddress('Plot 4, Sector 9, Gurugram Haryana'), 'Plot 4, Sector…');
      expect(maskAddress('Short'), 'Short');
    });

    test('updateProfile saves addresses, business type and payout profile and blanks remove them', () async {
      await db.collection('users').doc('u1').set({'driverName': 'Ravi', 'role': 'driver'});
      await UserService.updateProfile(
        isDriver: true, name: 'Ravi', email: '', companyName: '',
        currentAddress: 'House 1, Delhi', permanentAddress: 'Village X, UP', upiId: 'ravi@okaxis', holder: 'Ravi Kumar',
      );
      var u = (await db.collection('users').doc('u1').get()).data()!;
      expect(u['addresses'], {'current': 'House 1, Delhi', 'permanent': 'Village X, UP'});
      expect(u['payoutProfile'], {'upiId': 'ravi@okaxis', 'holder': 'Ravi Kumar'});
      final x = ProfileExtras.fromProfile(u);
      expect((x.currentAddress, x.upiId, x.businessType), ('House 1, Delhi', 'ravi@okaxis', null));

      await UserService.updateProfile(isDriver: true, name: 'Ravi', email: '', companyName: '', currentAddress: '', permanentAddress: '', upiId: '', holder: '');
      u = (await db.collection('users').doc('u1').get()).data()!;
      expect(u.containsKey('addresses'), isFalse);
      expect(u.containsKey('payoutProfile'), isFalse);
    });

    test('customers keep a business type; unknown values are dropped; bad UPI throws', () async {
      await db.collection('users').doc('u1').set({'name': 'Asha', 'role': 'customer'});
      await UserService.updateProfile(isDriver: false, name: 'Asha', email: '', companyName: '', businessType: BusinessType.importer);
      expect((await db.collection('users').doc('u1').get())['businessType'], 'importer');
      await UserService.updateProfile(isDriver: false, name: 'Asha', email: '', companyName: '', businessType: 'pirate');
      expect((await db.collection('users').doc('u1').get()).data()!.containsKey('businessType'), isFalse);
      await expectLater(UserService.updateProfile(isDriver: false, name: 'Asha', email: '', companyName: '', upiId: 'bad'), throwsArgumentError);
    });
  });

  group('automatic KYC check (R7, R12)', () {
    final ok = {
      'driverName': 'Ravi',
      'driverKyc': {'dlNumber': 'MH1220190001234', 'dlExpiry': DateTime(2035), 'rcNumber': 'MH12AB1234', 'pan': 'ABCDE1234F', 'aadhaarLast4': '4321'},
    };

    test('clean profile has no problems', () => expect(kycAutoCheck(ok, now: DateTime(2026, 10, 6)), isEmpty));

    test('expired licence, bad formats and a missing name are reported', () {
      final bad = {
        'driverName': ' ',
        'driverKyc': {'dlNumber': 'X', 'dlExpiry': DateTime(2020), 'rcNumber': '1', 'pan': 'no', 'aadhaarLast4': '12'},
      };
      expect(kycAutoCheck(bad, now: DateTime(2026, 10, 6)), [
        KycProblem.licenceFormat, KycProblem.licenceExpired, KycProblem.rcFormat, KycProblem.panFormat, KycProblem.aadhaarFormat, KycProblem.nameMissing,
      ]);
    });

    test('an edit after the last review and an admin flag are reported', () {
      final p = {
        ...ok,
        'kycEditedAt': DateTime(2026, 10, 5),
        'verificationMeta': {'at': DateTime(2026, 10, 1)},
        'reviewFlag': {'kind': 'name', 'note': 'x'},
      };
      expect(kycAutoCheck(p, now: DateTime(2026, 10, 6)), [KycProblem.editedAfterReview, KycProblem.adminFlag]);
      p['kycEditedAt'] = DateTime(2026, 9, 1);
      expect(kycAutoCheck(p, now: DateTime(2026, 10, 6)), [KycProblem.adminFlag]);
    });
  });

  group('review flag (K13)', () {
    setUp(() async {
      uid = 'admin1';
      await db.collection('users').doc('d1').set({'driverName': 'Ravi', 'role': 'driver', 'verificationStatus': 'approved', 'verified': true});
    });

    test('an admin marks a mismatch, it is audited and can be cleared; a short note is refused', () async {
      await expectLater(AdminUserService.setReviewFlag('d1', ReviewKind.name, 'x'), throwsA(isA<UserActionException>()));
      await expectLater(AdminUserService.setReviewFlag('d1', 'bogus', 'long enough note'), throwsArgumentError);
      await AdminUserService.setReviewFlag('d1', ReviewKind.rcOwner, 'RC is in another name');
      var u = (await db.collection('users').doc('d1').get()).data()!;
      expect(u['reviewFlag']['kind'], 'rc_owner');
      expect(u['reviewFlag']['by'], 'admin1');
      expect(u['verificationStatus'], 'approved'); // the flag does not change the verdict
      final events = await db.collection('audit_events').get();
      expect(events.docs.single['data']['action'], UserAction.flag);
      await AdminUserService.clearReviewFlag('d1');
      u = (await db.collection('users').doc('d1').get()).data()!;
      expect(u.containsKey('reviewFlag'), isFalse);
      expect((await db.collection('audit_events').get()).docs.length, 2);
    });

    testWidgets('the driver sees the banner and the admin sees auto-check chips', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            ReviewFlagBanner(profile: Stream.value({'reviewFlag': {'kind': 'name', 'note': 'Name differs from licence'}})),
            const AutoCheckChips(user: {'driverName': 'Ravi'}),
          ]),
        ),
      ));
      await settle(tester);
      expect(find.byKey(const ValueKey('reviewFlagBanner')), findsOneWidget);
      expect(find.textContaining('Name differs from licence'), findsOneWidget);
      expect(find.text('No problems found'), findsOneWidget);
    });
  });

  group('linked accounts (A9)', () {
    testWidgets('lists own company, company teams and fleets; empty state otherwise', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LinkedAccountsScreen(
          profile: Stream.value({'business': {'legalName': 'Asha Traders'}}),
          memberships: Stream.value([const BusinessMember(id: 'o1_u1', ownerId: 'o1', ownerName: 'Big Co', memberId: 'u1', active: true)]),
          fleets: Stream.value([const FleetMember(id: 'f1_u1', ownerId: 'f1', ownerName: 'Singh', driverId: 'u1', active: true)]),
        ),
      ));
      await settle(tester);
      expect(find.text('Own company: Asha Traders'), findsOneWidget);
      expect(find.text('Booker at Big Co'), findsOneWidget);
      expect(find.text("Driver in Singh's fleet"), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: LinkedAccountsScreen(key: UniqueKey(), profile: Stream.value(const {}), memberships: Stream.value(const []), fleets: Stream.value(const []))));
      await settle(tester);
      expect(find.text('No company or fleet is linked to this account.'), findsOneWidget);
    });
  });

  group('data export (BE18)', () {
    test('contains only the user\'s own records with plain JSON values', () async {
      await db.collection('users').doc('u1').set({'name': 'Asha', 'role': 'customer', 'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2))});
      await db.collection('users').doc('u1').collection('saved_places').doc('p1').set({'label': 'Office'});
      await db.collection('loads').doc('L1').set({'shipperId': 'u1', 'pickup': 'Delhi'});
      await db.collection('loads').doc('L2').set({'shipperId': 'u2', 'pickup': 'Pune'});
      await db.collection('bookings').doc('B1').set({'customerId': 'u1', 'driverId': 'd1'});
      await db.collection('notifications').add({'userId': 'u1', 'title': 'Hi'});
      final json = jsonDecode(await DataExportService.buildJson()) as Map<String, dynamic>;
      expect(json['uid'], 'u1');
      expect(json['profile']['createdAt'], '2026-01-02T00:00:00.000Z');
      expect((json['loads'] as List).map((e) => e['id']), ['L1']);
      expect((json['saved_places'] as List).single['label'], 'Office');
      expect((json['bookingsAsCustomer'] as List).single['id'], 'B1');
      expect((json['bookingsAsDriver'] as List), isEmpty);
      expect((json['notifications'] as List).single['title'], 'Hi');
    });
  });

  group('mobile number change (R3)', () {
    test('numbers are normalised to +91 and 10 digits', () {
      expect(PhoneChangeService.normalise('98765 43210'), '+919876543210');
      expect(PhoneChangeService.normalise('+91 98765 43210'), '+919876543210');
      expect(PhoneChangeService.normalise('12345'), isNull);
      expect(PhoneChangeService.normalise('5876543210'), isNull);
    });

    test('record updates the profile phone and writes a phone_change signal without full numbers', () async {
      await db.collection('users').doc('u1').set({'phone': '+919876543210', 'role': 'customer'});
      await PhoneChangeService.record(oldPhone: '+919876543210', newPhone: '+919123456789');
      expect((await db.collection('users').doc('u1').get())['phone'], '+919123456789');
      final s = (await db.collection('risk_signals').get()).docs.single.data();
      expect((s['type'], s['uid']), ('phone_change', 'u1'));
      expect(s['note'], 'from •••3210 to •••6789');
    });
  });
}
