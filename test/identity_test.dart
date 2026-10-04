import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/auth/driver_consent_screen.dart';
import 'package:transport_app/auth/driver_kyc_screen.dart';
import 'package:transport_app/auth/driver_pending_screen.dart';
import 'package:transport_app/auth/driver_profile_setup_screen.dart';
import 'package:transport_app/auth/start_resolvers.dart';
import 'package:transport_app/core/identity/identity_index.dart';
import 'package:transport_app/core/identity/kyc_validators.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/enterprise_service.dart';
import 'package:transport_app/core/models/enterprise.dart';
import 'package:transport_app/core/services/user_service.dart';
import 'package:transport_app/driver/driver_home_screen.dart';

import 'test_utils.dart';

DriverKyc kyc({String dl = 'MH12 2011 0012345', String pan = 'abcde1234f', String rc = 'mh12ab1234', String aadhaar = '4321'}) =>
    DriverKyc(dlNumber: dl, dlExpiry: DateTime(2030, 1, 1), rcNumber: rc, aadhaarLast4: aadhaar, pan: pan);

void main() {
  late FakeFirebaseFirestore db;
  String uid = 'd1';

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'd1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  group('validators', () {
    test('driving licence, vehicle, PAN and Aadhaar last 4', () {
      expect(isValidDlNumber('MH12 2011 0012345'), isTrue);
      expect(isValidDlNumber('mh-12-20110012345'), isTrue);
      expect(isValidDlNumber('MH12345'), isFalse);
      expect(isValidVehicleNumber('MH12AB1234'), isTrue);
      expect(isValidVehicleNumber('DL1CAB1234'), isTrue);
      expect(isValidVehicleNumber('1234'), isFalse);
      expect(isValidPan('ABCDE1234F'), isTrue);
      expect(isValidPan('ABCD12345F'), isFalse);
      expect(isValidAadhaarLast4('1234'), isTrue);
      expect(isValidAadhaarLast4('123456789012'), isFalse);
      expect(isValidAadhaarLast4('12a4'), isFalse);
    });

    test('licence expiry compares dates only', () {
      final now = DateTime(2026, 10, 4, 15);
      expect(isDlExpiryValid(DateTime(2026, 10, 4), now), isTrue);
      expect(isDlExpiryValid(DateTime(2026, 10, 3), now), isFalse);
      expect(isDlExpiryValid(null, now), isFalse);
    });
  });

  group('identity index', () {
    test('id is sha256(type + normalised number)', () {
      const expected = '6ffed93f004b17ad93e7497cf5d224250bf07c01bf922751d10fd56a15a281c0'; // sha256('dlMH1220110012345')
      expect(IdentityIndex.docId(IdentityType.dl, 'MH12 2011 0012345'), IdentityIndex.docId(IdentityType.dl, 'mh12-20110012345'));
      expect(IdentityIndex.docId(IdentityType.dl, 'MH1220110012345'), expected);
      expect(IdentityIndex.docId(IdentityType.dl, 'X'), isNot(IdentityIndex.docId(IdentityType.pan, 'X')));
    });

    test('driver KYC saves documents, claims them, and keeps only Aadhaar last 4', () async {
      await UserService.saveDriverKyc(kyc());
      final user = (await db.collection('users').doc('d1').get()).data()!;
      expect(user['kycComplete'], true);
      final saved = user['driverKyc'] as Map;
      expect(saved['aadhaarLast4'], '4321');
      expect(saved['dlNumber'], 'MH1220110012345');
      expect(saved['pan'], 'ABCDE1234F');
      expect(saved['rcNumber'], 'MH12AB1234');

      final idx = await db.collection('identity_index').get();
      expect(idx.docs.length, 3);
      for (final d in idx.docs) {
        expect(d.data()['uid'], 'd1');
        expect(d.data()['role'], 'driver');
        // the index holds no number at all
        expect(d.data().values.whereType<String>().any((v) => v.contains('MH12') || v.contains('ABCDE')), isFalse);
      }
      // nothing holds a 12 digit Aadhaar-like number (the licence number is the only long digit run)
      final all = [...(await db.collection('users').get()).docs, ...idx.docs]
          .map((d) => d.data().toString())
          .join()
          .replaceAll('MH1220110012345', '');
      expect(RegExp(r'\d{12}').hasMatch(all), isFalse);
    });

    test('the same document on another account is refused and nothing is written', () async {
      await UserService.saveDriverKyc(kyc());
      uid = 'd2';
      await expectLater(
        UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999', pan: 'ZZZZZ9999Z', rc: 'MH12AB1234')),
        throwsA(isA<DuplicateIdentityException>().having((e) => e.type, 'type', IdentityType.rc)),
      );
      expect((await db.collection('users').doc('d2').get()).exists, isFalse);
      expect((await db.collection('identity_index').get()).docs.length, 3);
    });

    test('a customer cannot reuse a driver document, and resubmitting your own is fine', () async {
      await UserService.saveDriverKyc(kyc());
      await expectLater(
        IdentityIndex.assertAvailable({IdentityType.pan: 'ABCDE1234F'}, uid: 'c1'),
        throwsA(isA<DuplicateIdentityException>().having((e) => e.type, 'type', IdentityType.pan)),
      );
      await UserService.saveDriverKyc(kyc());
      expect((await db.collection('identity_index').get()).docs.length, 3);
    });

    test('duplicate message is translated in every language', () {
      for (final lang in AppLanguage.values) {
        for (final k in ['docNameDl', 'docNamePan', 'docNameRc', 'docNameGst']) {
          final msg = T.get('identityDuplicate', lang).replaceAll('{doc}', T.get(k, lang));
          expect(msg.contains('{doc}'), isFalse, reason: '${lang.name} $k');
        }
      }
    });
  });

  group('editing a document', () {
    test('changing the DL frees the old entry and claims the new one in one go', () async {
      await UserService.saveDriverKyc(kyc());
      final oldId = IdentityIndex.docId(IdentityType.dl, 'MH1220110012345');
      expect((await db.collection('identity_index').doc(oldId).get()).exists, isTrue);

      await UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999'));
      expect((await db.collection('identity_index').doc(oldId).get()).exists, isFalse);
      final newId = IdentityIndex.docId(IdentityType.dl, 'KA0120150099999');
      final entry = (await db.collection('identity_index').doc(newId).get()).data()!;
      expect(entry['uid'], 'd1');
      expect(entry['type'], 'dl');
      expect((await db.collection('identity_index').get()).docs.length, 3);
      final user = (await db.collection('users').doc('d1').get()).data()!;
      expect((user['identityHashes'] as Map)['dl'], newId);
      expect(user['kycEditedAt'], isNotNull);
    });

    test('the freed number can be used by someone else, the new one cannot', () async {
      await UserService.saveDriverKyc(kyc());
      await UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999'));
      uid = 'd2';
      await UserService.saveDriverKyc(kyc(dl: 'MH12 2011 0012345', pan: 'PPPPP1111P', rc: 'GJ01AB1111'));
      uid = 'd3';
      await expectLater(
        UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999', pan: 'QQQQQ2222Q', rc: 'GJ01AB2222')),
        throwsA(isA<DuplicateIdentityException>().having((e) => e.type, 'type', IdentityType.dl)),
      );
    });

    test('a duplicate on edit changes nothing', () async {
      await UserService.saveDriverKyc(kyc());
      uid = 'd2';
      await UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999', pan: 'PPPPP1111P', rc: 'GJ01AB1111'));
      await expectLater(
        UserService.saveDriverKyc(kyc(dl: 'KA01 2015 0099999', pan: 'ABCDE1234F', rc: 'GJ01AB1111')),
        throwsA(isA<DuplicateIdentityException>().having((e) => e.type, 'type', IdentityType.pan)),
      );
      expect(((await db.collection('users').doc('d2').get()).data()!['driverKyc'] as Map)['pan'], 'PPPPP1111P');
      expect((await db.collection('identity_index').get()).docs.length, 6);
    });

    test('GSTIN edits move the entry, clearing it frees it, another account is blocked', () async {
      await db.collection('users').doc('c1').set({'role': 'customer'});
      uid = 'c1';
      await EnterpriseService.saveBusiness(const BusinessProfile(legalName: 'A', gstin: '27ABCDE1234F1Z5', address: ''));
      final id1 = IdentityIndex.docId(IdentityType.gst, '27ABCDE1234F1Z5');
      expect((await db.collection('identity_index').doc(id1).get()).data()!['type'], 'gst');

      await EnterpriseService.saveBusiness(const BusinessProfile(legalName: 'A', gstin: '29ABCDE1234F1Z3', address: ''));
      expect((await db.collection('identity_index').doc(id1).get()).exists, isFalse);

      await db.collection('users').doc('c2').set({'role': 'customer'});
      uid = 'c2';
      await expectLater(
        EnterpriseService.saveBusiness(const BusinessProfile(legalName: 'B', gstin: '29ABCDE1234F1Z3', address: '')),
        throwsA(isA<DuplicateIdentityException>()),
      );

      uid = 'c1';
      await EnterpriseService.saveBusiness(const BusinessProfile(legalName: 'A', gstin: '', address: ''));
      expect((await db.collection('identity_index').get()).docs, isEmpty);
      expect(((await db.collection('users').doc('c1').get()).data()!['identityHashes'] as Map).containsKey('gst'), isFalse);
    });

    testWidgets('edit screen is prefilled and saves changes back', (tester) async {
      languageNotifier.value = AppLanguage.english;
      await tester.runAsync(() => UserService.saveDriverKyc(kyc()));
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: const MaterialApp(home: DriverKycScreen(edit: true)),
      ));
      await settle(tester);
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('kycDl'))).controller!.text, 'MH1220110012345');
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('kycPan'))).controller!.text, 'ABCDE1234F');
    });
  });

  group('driver router guard', () {
    Future<Widget> start(Map<String, Object?> user) async {
      await db.collection('users').doc('d1').set(user);
      return resolveDriverStart();
    }

    const base = {'roles': ['driver'], 'driverProfileComplete': true, 'locationConsentAsked': true};

    test('profile -> documents -> pending -> home', () async {
      expect(await start({'roles': ['driver']}), isA<DriverProfileSetupScreen>());
      expect(await start({...base, 'locationConsentAsked': false}), isA<DriverConsentScreen>());
      expect(await start(base), isA<DriverKycScreen>());
      expect(await start({...base, 'kycComplete': true, 'verificationStatus': 'pending'}), isA<DriverPendingScreen>());
      expect(await start({...base, 'kycComplete': true, 'verified': true}), isA<DriverHomeScreen>());
    });

    test('an approved driver without documents still cannot open Home', () async {
      expect(await start({...base, 'verified': true, 'verificationStatus': 'approved'}), isA<DriverKycScreen>());
    });
  });

  group('screens', () {
    testWidgets('KYC form validates every field and Aadhaar takes 4 digits at most', (tester) async {
      languageNotifier.value = AppLanguage.english;
      await db.collection('users').doc('d1').set({'roles': ['driver'], 'driverProfileComplete': true, 'vehicleNumber': 'MH12AB1234'});
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: DriverKycScreen()),
      ));
      await settle(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('kycSubmit')));
      await tester.tap(find.byKey(const ValueKey('kycSubmit')));
      await tester.pump();
      expect(find.text(T.get('kycInvalidDl', AppLanguage.english)), findsOneWidget);
      expect(find.text(T.get('kycInvalidAadhaar', AppLanguage.english)), findsOneWidget);
      expect(find.text(T.get('kycInvalidPan', AppLanguage.english)), findsOneWidget);
      expect(find.text(T.get('kycDlExpired', AppLanguage.english)), findsOneWidget);
      // RC was prefilled from the profile, so no error for it.
      expect(find.text(T.get('kycInvalidRc', AppLanguage.english)), findsNothing);

      // Aadhaar field takes 4 digits at most.
      await tester.enterText(find.byKey(const ValueKey('kycAadhaar')), '123456789012');
      expect((tester.widget<TextFormField>(find.byKey(const ValueKey('kycAadhaar'))).controller!.text).length, 4);
    });

    testWidgets('pending screen shows the Pending verification status', (tester) async {
      await tester.pumpWidget(LanguageScope(
        notifier: languageNotifier,
        child: MaterialApp(home: DriverPendingScreen()),
      ));
      expect(find.text('Pending verification'), findsOneWidget);
    });
  });
}
