import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/l10n/l10n.dart';
import 'package:transport_app/core/models/load.dart';
import 'package:transport_app/core/network/network_chat_screen.dart';
import 'package:transport_app/core/network/network_logic.dart';
import 'package:transport_app/core/network/network_screen.dart';
import 'package:transport_app/core/network/share_load_sheet.dart';
import 'package:transport_app/core/services/account_deletion_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/location_service.dart';
import 'package:transport_app/core/services/network_service.dart';

import 'test_utils.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth current;
  final people = <String, MockFirebaseAuth>{};
  void signIn(String uid) => current = people.putIfAbsent(uid, () => MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid, phoneNumber: '+91980000000${uid.length}')));
  final now = DateTime(2026, 10, 6, 12);

  Load load({String id = 'L1', String visibility = LoadVisibility.public, String status = 'open', num? budget = 50000}) => Load(
        id: id, shipperId: 'c', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 10, vehicleType: '20ft', budget: budget, pickupDate: null, notes: '', status: status, visibility: visibility);

  setUp(() async {
    db = FakeFirebaseFirestore();
    people.clear();
    signIn('d1');
    Backend.useFakes(db: db, uid: () => current.currentUser?.uid, auth: () => current);
    languageNotifier.value = AppLanguage.english;
    LocationService.useFakeCurrent(() async => (lat: 18.52, lng: 73.86));
    await db.collection('users').doc('d1').set({'driverName': 'Ramesh', 'role': 'driver'});
    await db.collection('users').doc('d2').set({'driverName': 'Suresh', 'role': 'driver'});
    await db.collection('users').doc('d3').set({'name': 'Mahesh', 'role': 'driver'});
  });
  tearDown(() => LocationService.useFakeCurrent(null));

  group('pure logic', () {
    test('pairId is the same from both sides; coordinates round to about 1 km', () {
      expect(pairIdOf('b', 'a'), 'a_b');
      expect(pairIdOf('a', 'b'), 'a_b');
      expect(roundCoord(18.5249), 18.52);
      expect(roundCoord(73.8651), 73.87);
    });

    test('nearby list: nearest first, hides me, expired, hidden modes, connected and far drivers', () {
      DriverPresence p(String uid, double lat, {String mode = 'nearby', DateTime? until}) =>
          DriverPresence(uid: uid, name: uid, lat: lat, lng: 73.86, mode: mode, sharedUntil: until ?? now.add(const Duration(hours: 1)));
      final list = nearbyDrivers(
        [p('far', 19.2), p('near', 18.55), p('me', 18.52), p('old', 18.53, until: now.subtract(const Duration(minutes: 1))), p('trip', 18.53, mode: 'trip'), p('linked', 18.54), p('conn', 18.56, mode: 'connections'), p('away', 25.0)],
        lat: 18.52, lng: 73.86, myUid: 'me', now: now, hide: {'linked'});
      expect(list.map((e) => e.driver.uid), ['near', 'conn', 'far']);
    });

    test('shared load card: only open public loads; paise from the budget', () {
      expect(SharedLoad.canShare(load()), isTrue);
      expect(SharedLoad.canShare(load(visibility: LoadVisibility.invite)), isFalse);
      expect(SharedLoad.canShare(load(visibility: LoadVisibility.favourites)), isFalse);
      expect(SharedLoad.canShare(load(status: 'matched')), isFalse);
      final c = SharedLoad.fromLoad(load());
      expect(c.budgetPaise, 5000000);
      expect(SharedLoad.fromLoad(load(budget: null)).toMap().containsKey('budgetPaise'), isFalse);
      expect(SharedLoad.fromMap(c.toMap())!.drop, 'Delhi');
      expect(SharedLoad.fromMap('x'), isNull);
    });
  });

  group('location privacy and expiry (D11, CH13, CH14)', () {
    test('nearby and connections publish a rounded position for the chosen hours; hidden and trip store none', () async {
      await NetworkService.setLocationMode(mode: 'nearby', name: 'Ramesh', lat: 18.5249, lng: 73.8651, hours: 8, now: now);
      var d = (await db.collection('driver_presence').doc('d1').get()).data()!;
      expect(d['lat'], 18.52);
      expect(d['lng'], 73.87);
      expect((d['geohash'] as String).length, 6);
      expect((d['sharedUntil'] as Timestamp).toDate(), now.add(const Duration(hours: 8)));
      await NetworkService.setLocationMode(mode: 'hidden', name: 'Ramesh');
      d = (await db.collection('driver_presence').doc('d1').get()).data()!;
      expect(d.containsKey('lat'), isFalse);
      expect(d.containsKey('sharedUntil'), isFalse);
      await NetworkService.setLocationMode(mode: 'trip', name: 'Ramesh');
      expect((await NetworkService.watchMyMode().first).mode, 'trip');
      await expectLater(NetworkService.setLocationMode(mode: 'nearby', name: 'R'), throwsArgumentError);
      await NetworkService.setLocationMode(mode: 'connections', name: 'R', lat: 18.5, lng: 73.8, now: now);
      await NetworkService.stopSharing();
      expect((await NetworkService.watchMyMode().first).mode, 'hidden');
    });

    test('another driver finds those who chose nearby, in the cell, not the others', () async {
      signIn('d2');
      await NetworkService.setLocationMode(mode: 'nearby', name: 'Suresh', lat: 18.53, lng: 73.85, now: DateTime.now());
      signIn('d3');
      await NetworkService.setLocationMode(mode: 'connections', name: 'Mahesh', lat: 18.53, lng: 73.85, now: DateTime.now());
      signIn('d1');
      final found = await NetworkService.watchNearby(18.52, 73.86).firstWhere((l) => l.isNotEmpty);
      expect(found.map((e) => e.uid).toSet(), {'d2'});
      final list = nearbyDrivers(found, lat: 18.52, lng: 73.86, myUid: 'd1', now: DateTime.now());
      expect(list.single.km, lessThan(5));
      // far away: a different cell, nobody there
      final none = await NetworkService.watchNearby(28.6, 77.2).first.timeout(const Duration(seconds: 1), onTimeout: () => const []);
      expect(none, isEmpty);
    });
  });

  group('connections, groups and chat (D12, D13, CH2, CH3, CH7, D14)', () {
    Future<void> connect() async {
      await NetworkService.requestConnection(otherUid: 'd2', myName: 'Ramesh', otherName: 'Suresh');
      signIn('d2');
      await NetworkService.accept('d1_d2');
      signIn('d1');
    }

    test('request, incoming view, accept, end', () async {
      await NetworkService.requestConnection(otherUid: 'd2', myName: 'Ramesh', otherName: 'Suresh');
      await expectLater(NetworkService.requestConnection(otherUid: 'd1', myName: 'R', otherName: 'R'), throwsArgumentError);
      var mine = (await NetworkService.watchLinks().first).single;
      expect(mine.id, 'd1_d2');
      expect(mine.incomingFor('d1'), isFalse);
      expect(mine.otherName('d1'), 'Suresh');
      signIn('d2');
      var theirs = (await NetworkService.watchLinks().first).single;
      expect(theirs.incomingFor('d2'), isTrue);
      expect(theirs.otherName('d2'), 'Ramesh');
      expect(theirs.otherUid('d2'), 'd1');
      await NetworkService.accept(theirs.id);
      theirs = (await NetworkService.watchLinks().first).single;
      expect(theirs.connected, isTrue);
      await NetworkService.remove(theirs.id);
      expect(await NetworkService.watchLinks().first, isEmpty);
    });

    test('one to one chat with text and a load card', () async {
      await connect();
      await NetworkService.send('link', 'd1_d2', senderName: 'Ramesh', text: ' hello ');
      await NetworkService.send('link', 'd1_d2', senderName: 'Ramesh', loadCard: SharedLoad.fromLoad(load()));
      await expectLater(NetworkService.send('link', 'd1_d2', senderName: 'R'), throwsException);
      final msgs = await NetworkService.watchMessages('link', 'd1_d2').first;
      expect(msgs.length, 2);
      expect(msgs.first.text, 'hello');
      expect(msgs.last.loadCard!.pickup, 'Pune');
      expect(msgs.last.loadCard!.budgetPaise, 5000000);
      expect(msgs.last.senderName, 'Ramesh');
    });

    test('group: create, add a connection, share a load card, a member leaves, owner deletes', () async {
      await connect();
      final id = await NetworkService.createGroup(name: ' Pune-Delhi ', kind: 'convoy');
      var g = (await NetworkService.watchGroups().first).single;
      expect(g.name, 'Pune-Delhi');
      expect(g.memberIds, ['d1']);
      await NetworkService.addMember(g, 'd2');
      await NetworkService.send('group', id, senderName: 'Ramesh', loadCard: SharedLoad.fromLoad(load()));
      signIn('d2');
      g = (await NetworkService.watchGroups().first).single;
      expect(g.memberIds, ['d1', 'd2']);
      final seen = await NetworkService.watchMessages('group', id).first;
      expect(seen.single.loadCard!.loadId, 'L1');
      await NetworkService.send('group', id, senderName: 'Suresh', text: 'I can take it');
      await NetworkService.removeMember(g, 'd2');
      expect(await NetworkService.watchGroups().first, isEmpty);
      signIn('d1');
      expect((await NetworkService.watchGroups().first).single.memberIds, ['d1']);
      await NetworkService.deleteGroup(id);
      expect(await NetworkService.watchGroups().first, isEmpty);
    });

    test('account deletion removes presence and links, deletes own groups and leaves others', () async {
      await connect();
      await NetworkService.setLocationMode(mode: 'nearby', name: 'Ramesh', lat: 18.5, lng: 73.8, now: DateTime.now());
      final own = await NetworkService.createGroup(name: 'Mine', kind: 'trip');
      signIn('d2');
      final theirs = await NetworkService.createGroup(name: 'Theirs', kind: 'route');
      await NetworkService.addMember((await NetworkService.watchGroups().first).firstWhere((g) => g.id == theirs), 'd1');
      signIn('d1');
      await AccountDeletionService.deleteAccount(deleteAuthUser: () async {});
      expect((await db.collection('driver_presence').doc('d1').get()).exists, isFalse);
      expect((await db.collection('driver_links').doc('d1_d2').get()).exists, isFalse);
      expect((await db.collection('driver_groups').doc(own).get()).exists, isFalse);
      expect((await db.collection('driver_groups').doc(theirs).get()).data()!['memberIds'], ['d2']);
    });
  });

  group('screens', () {
    testWidgets('network screen: privacy mode, nearby list with connect, requests, new group', (tester) async {
      signIn('d2');
      await NetworkService.setLocationMode(mode: 'nearby', name: 'Suresh', lat: 18.53, lng: 73.85, now: DateTime.now());
      signIn('d3');
      await NetworkService.requestConnection(otherUid: 'd1', myName: 'Mahesh', otherName: 'Ramesh');
      signIn('d1');
      await tester.pumpWidget(const MaterialApp(home: NetworkScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('nearby_d2')), findsOneWidget);
      expect(find.text('Suresh'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mode_nearby')));
      await settle(tester);
      expect((await db.collection('driver_presence').doc('d1').get()).data()!['mode'], 'nearby');
      expect(find.byKey(const ValueKey('netStop')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('connect_d2')));
      await settle(tester);
      expect((await db.collection('driver_links').doc('d1_d2').get()).data()!['status'], 'pending');
      await tester.tap(find.byKey(const ValueKey('mode_hidden')));
      await settle(tester);
      expect((await db.collection('driver_presence').doc('d1').get()).data()!.containsKey('lat'), isFalse);

      await tester.tap(find.byKey(const ValueKey('netTabConnections')));
      await settle(tester);
      expect(find.byKey(const ValueKey('request_d1_d3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept_d1_d3')));
      await settle(tester);
      expect((await db.collection('driver_links').doc('d1_d3').get()).data()!['status'], 'connected');

      await tester.pump(const Duration(seconds: 6));
      await tester.tap(find.byKey(const ValueKey('netTabGroups')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('newGroup')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('groupName')), 'Convoy 1');
      await tester.tap(find.byKey(const ValueKey('groupCreate')));
      await settle(tester);
      expect(find.text('Convoy 1'), findsOneWidget);
    });

    testWidgets('share a load: a connection receives a load card, a restricted load is refused', (tester) async {
      await NetworkService.requestConnection(otherUid: 'd2', myName: 'Ramesh', otherName: 'Suresh');
      signIn('d2');
      await NetworkService.accept('d1_d2');
      signIn('d1');
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return TextButton(onPressed: () => showShareToNetwork(c, load()), child: const Text('go'));
      }))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('shareTo_link_d1_d2')));
      await settle(tester);
      final msgs = await NetworkService.watchMessages('link', 'd1_d2').first;
      expect(msgs.single.loadCard!.loadId, 'L1');
      expect(find.text('Load shared'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      showShareToNetwork(ctx, load(id: 'L2', visibility: LoadVisibility.invite));
      await tester.pumpAndSettle();
      expect(find.text('Only open public loads can be shared.'), findsOneWidget);
      expect((await NetworkService.watchMessages('link', 'd1_d2').first).length, 1);
    });

    testWidgets('chat shows a load card bubble and sends text', (tester) async {
      await NetworkService.requestConnection(otherUid: 'd2', myName: 'Ramesh', otherName: 'Suresh');
      signIn('d2');
      await NetworkService.accept('d1_d2');
      await NetworkService.send('link', 'd1_d2', senderName: 'Suresh', loadCard: SharedLoad.fromLoad(load()), text: 'Anyone free?');
      signIn('d1');
      await tester.pumpWidget(const MaterialApp(home: NetworkChatScreen(kind: 'link', id: 'd1_d2', title: 'Suresh')));
      await settle(tester);
      expect(find.byKey(const ValueKey('sharedLoad_L1')), findsOneWidget);
      expect(find.text('Pune → Delhi'), findsOneWidget);
      expect(find.text('Anyone free?'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('netInput')), 'Yes, I am');
      await tester.tap(find.byKey(const ValueKey('netSend')));
      await settle(tester);
      expect((await NetworkService.watchMessages('link', 'd1_d2').first).last.text, 'Yes, I am');
    });
  });
}
