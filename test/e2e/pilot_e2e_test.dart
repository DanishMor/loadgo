import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/pilot/invite_codes.dart';
import 'package:transport_app/core/pilot/waitlist.dart';
import 'package:transport_app/core/services/admin_console_service.dart';
import 'package:transport_app/core/services/backend.dart';
import 'package:transport_app/core/services/server_clock.dart';

/// MASTER-6 Task 49: the pilot story from the owner's side.
/// Invite-only on, a new person is stopped, joins with a code, a person on a
/// closed route joins the waitlist, the owner opens the route, a load nobody
/// took gets a driver suggested and a call-back note.
void main() {
  late FakeFirebaseFirestore db;
  String? uid;

  setUp(() {
    ServerClock.reset();
    PilotAreas.reset();
    db = FakeFirebaseFirestore();
    uid = 'owner1';
    Backend.useFakes(db: db, uid: () => uid);
  });

  test('invite code, waitlist and manual dispatch', () async {
    // 1. the owner closes the pilot: invite only, Delhi and Jaipur open
    await db.collection('config').doc('pilot').set({'inviteOnly': true, 'openCities': ['Delhi', 'Jaipur']});
    await PilotAreas.refresh(force: true);

    // 2. a new customer is stopped; the owner makes a one-use code
    uid = 'cust1';
    expect(await InviteService.mayJoin(uid: 'cust1', phone: '+919800000001'), isFalse);
    uid = 'owner1';
    final code = await InviteService.create(role: 'customer', route: 'Delhi-Jaipur', maxUses: 1, days: 7);

    // 3. the customer joins with the code; a second person cannot reuse it
    uid = 'cust1';
    expect(await InviteService.redeem(code, role: 'driver'), InviteCheck.wrongRole);
    expect(await InviteService.redeem(code, role: 'customer'), InviteCheck.ok);
    expect(await InviteService.mayJoin(uid: 'cust1', phone: '+919800000001'), isTrue);
    uid = 'cust2';
    expect(await InviteService.redeem(code, role: 'customer'), InviteCheck.usedUp);
    expect(await InviteService.mayJoin(uid: 'cust2', phone: '+919800000002'), isFalse);

    // 4. cust2 wants Pune - Delhi, which is closed: the waitlist keeps the wish
    expect(PilotAreas.current.isOpen('Pune'), isFalse);
    await WaitlistService.join(role: 'customer', from: 'Pune', to: 'Delhi');
    expect((await WaitlistService.opened(PilotAreas.current)), isEmpty);

    // 5. the owner opens Pune; the waiting person is told the route is open now
    uid = 'owner1';
    await db.collection('config').doc('pilot').set({'inviteOnly': true, 'openCities': ['Delhi', 'Jaipur', 'Pune']});
    await PilotAreas.refresh(force: true);
    uid = 'cust2';
    expect((await WaitlistService.opened(PilotAreas.current)).single.from, 'Pune');

    // 6. cust1 posted a load an hour ago; nobody took it
    await db.collection('loads').doc('L1').set({
      'shipperId': 'cust1', 'pickup': 'Karol Bagh, Delhi', 'drop': 'Jaipur', 'cargoType': 'Rice', 'weight': 3, 'vehicleType': 'Mini', 'status': 'open',
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))),
    });
    await db.collection('vehicles').doc('v1').set({'ownerId': 'drv1', 'number': 'DL1CV1', 'type': 'Mini', 'capacity': 5, 'status': 'active', 'availability': 'available', 'rcNumber': 'RC'});
    await db.collection('users').doc('drv1').set({'role': 'driver', 'driverName': 'Suresh'});

    // 7. the owner sees it as unfilled, picks the driver, notes a call-back
    uid = 'owner1';
    final unfilled = await AdminConsoleService.unfilledLoads();
    expect(unfilled.map((l) => l.id), ['L1']);
    final candidates = await AdminConsoleService.dispatchCandidates(unfilled.single);
    expect(candidates.map((c) => c.c.driverId), ['drv1']);
    await AdminConsoleService.suggestLoad(unfilled.single, 'drv1', note: 'Customer is waiting, please bid');
    await AdminConsoleService.callbackNote(unfilled.single, 'Call the customer after 6 pm');

    // 8. the driver finds the suggestion; everything the owner did is in the audit log
    final mine = await db.collection('dispatch_suggestions').where('driverId', isEqualTo: 'drv1').get();
    expect(mine.docs.single.data()['loadId'], 'L1');
    final actions = (await db.collection('audit_events').get()).docs.map((e) => e.data()['data']['action']).toSet();
    expect(actions, containsAll(['dispatch_suggest', 'callback_note']));
  });
}
