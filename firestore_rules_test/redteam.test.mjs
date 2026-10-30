// Part 5 (H2): red-team suite. Every case is an ATTACK that must fail, written
// the way a modified client would send it. A few positive controls prove the
// suite is not passing only because every write is rejected for a silly reason.
//
// Attack classes covered (see docs/REDTEAM_RESULTS.md for the counts):
//  A reads of someone else's data, lists without a filter, collection groups
//  B self-escalation (role, riskTier, plan, verified, wallet, admin)
//  C mass assignment and immutable fields
//  D bad numbers (negative, zero, float, huge, string) and bad sizes
//  E timestamp spoofing and id format
//  F state machine jumps and replays
//  G ledger, wallet, payout tampering and self-approval
//  H staff role escalation
//  I banned and restricted accounts
//  J OTP secrets
//  K races (two drivers accept)
//  L storage (see redteam_storage.test.mjs)
//
// Run: sh run-redteam.sh   (starts the emulators; needs Java)
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  Timestamp, collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, limit, orderBy, query, serverTimestamp, setDoc,
  terminate, updateDoc, where, writeBatch,
} from 'firebase/firestore';

const RULES = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
let env;
const opened = new Set();
const as = (uid) => {
  const d = uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
  opened.add(d);
  return d;
};
afterEach(async () => {
  const list = [...opened];
  opened.clear();
  await Promise.all(list.map((d) => terminate(d._delegate ?? d).catch(() => {})));
});

const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const HUGE = 'x'.repeat(20000);
const D = (db, path) => doc(db, ...path.split('/'));
const past = () => Timestamp.fromMillis(Date.now() - 3600_000);

// Count of attacks, printed at the end for docs/REDTEAM_RESULTS.md.
const stats = { attacks: 0, controls: 0 };
const deny = (name, uid, fn) => test(`ATTACK ${name}`, async () => {
  stats.attacks++;
  await assertFails(fn(as(uid)));
});
const allow = (name, uid, fn) => test(`CONTROL ${name}`, async () => {
  stats.controls++;
  await assertSucceeds(fn(as(uid)));
});

after(async () => {
  console.log(`REDTEAM attacks=${stats.attacks} controls=${stats.controls}`);
  await env.cleanup();
});

const LOAD = {
  shipperId: 'cust1', pickup: 'Delhi', drop: 'Mumbai', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000,
  pickupDate: Timestamp.fromDate(new Date('2026-10-05')), notes: '', status: 'open',
};
const VEH = (owner, number) => ({ ownerId: owner, number, type: '20ft', capacity: 10, rcNumber: 'RC1', status: 'active' });
const BOOKING = (over = {}) => ({
  loadId: 'LM', driverId: 'drv1', vehicleId: 'v1', customerId: 'cust1', status: 'in_transit', pickup: 'Delhi', drop: 'Mumbai',
  cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: 25000, pickupDate: LOAD.pickupDate, notes: '',
  vehicleNumber: 'MH12AB1234', driverName: 'Ramesh', driverPhone: '', timeline: { accepted: past() },
  createdAt: past(), updatedAt: past(), ...over,
});

async function reseed() {
  await env.clearFirestore();
  await seed(async (db) => {
    const w = (p, d) => setDoc(D(db, p), d);
    await w('admins/admin1', { createdBy: 'console' });
    await w('admins/sup1', { role: 'support' });
    await w('admins/ver1', { role: 'verifier' });
    await w('admins/fin1', { role: 'finance' });
    await w('admins/fin2', { role: 'finance' });
    await w('users/cust1', { role: 'customer', selectedRole: 'customer', name: 'Asha' });
    await w('users/cust2', { role: 'customer', selectedRole: 'customer', name: 'Bela' });
    await w('users/drv1', { role: 'driver', selectedRole: 'driver', name: 'Ramesh', verified: false, verificationStatus: 'pending' });
    await w('users/drv2', { role: 'driver', selectedRole: 'driver', name: 'Suresh', verified: false, verificationStatus: 'pending' });
    await w('users/flt1', { role: 'fleet', selectedRole: 'fleet', name: 'Co' });
    await w('users/ban1', { role: 'customer', selectedRole: 'customer', riskTier: 'banned' });
    await w('users/rst1', { role: 'driver', selectedRole: 'driver', riskTier: 'restricted' });
    await w('vehicles/v1', VEH('drv1', 'MH12AB1234'));
    await w('vehicles/v2', VEH('drv2', 'KA01CD5678'));
    await w('vehicles/v3', VEH('rst1', 'GJ01EF9999'));
    await w('loads/L1', LOAD);
    await w('loads/LM', { ...LOAD, status: 'matched', driverId: 'drv1', bookingId: 'LM' });
    await w('bookings/LM', BOOKING());
    await w('bookings/LD', BOOKING({ loadId: 'LD', status: 'delivered' }));
    await w('bookings/LA', BOOKING({ loadId: 'LA', status: 'accepted' }));
    await w('bookings/LM/secrets/otp', { pickupOtp: '111111', deliveryOtp: '222222', createdAt: past() });
    await w('offers/L1_drv1', { loadId: 'L1', driverId: 'drv1', customerId: 'cust1', vehicleId: 'v1', vehicleNumber: 'MH12AB1234', pricePaise: 2000000, originalPaise: 2000000, status: 'pending', createdAt: past(), updatedAt: past() });
    await w('offers/L1_drv2', { loadId: 'L1', driverId: 'drv2', customerId: 'cust1', vehicleId: 'v2', vehicleNumber: 'KA01CD5678', pricePaise: 2100000, originalPaise: 2100000, status: 'accepted', createdAt: past(), updatedAt: past() });
    await w('ledger/LD_trip_earning', { driverId: 'drv1', bookingId: 'LD', type: 'trip_earning', amountPaise: 100000, createdAt: past() });
    await w('wallets/drv1', { availablePaise: 100000 });
    await w('payouts/P_req', { driverId: 'drv1', amountPaise: 50000, status: 'requested', createdAt: past() });
    await w('payouts/P_appr', { driverId: 'drv1', amountPaise: 50000, status: 'approved', approvedBy: 'fin1', approvedAt: past(), createdAt: past() });
    await w('payouts/P_paid', { driverId: 'drv1', amountPaise: 50000, status: 'paid', paidBy: 'fin2', paidAt: past(), createdAt: past() });
    await w('audit_events/A1', { type: 'accept', actorId: 'drv1', data: {}, createdAt: past() });
    await w('config/dispatch', { acceptSeconds: 30 });
    await w('ratings/LD_cust1', { bookingId: 'LD', raterId: 'cust1', ratedId: 'drv1', stars: 5, createdAt: past() });
    await w('tickets/T1', { userId: 'cust1', category: 'other', priority: 'low', status: 'open', subject: 'Help me', escalationLevel: 0, createdAt: past(), updatedAt: past() });
    await w('users/cust1/saved_places/p1', { label: 'Home' });
  });
}
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'loadgo-redteam', firestore: { rules: RULES } });
});
beforeEach(reseed);

// ---------------------------------------------------------------- A reads
describe('A. reading other people', () => {
  deny('anonymous reads a user', null, (db) => getDoc(D(db, 'users/cust1')));
  deny('customer reads another customer', 'cust1', (db) => getDoc(D(db, 'users/cust2')));
  deny('driver reads a customer', 'drv1', (db) => getDoc(D(db, 'users/cust1')));
  deny('list all users', 'cust1', (db) => getDocs(collection(db, 'users')));
  deny('list users by role (enumeration)', 'cust1', (db) => getDocs(query(collection(db, 'users'), where('role', '==', 'driver'))));
  deny('list users by phone prefix', 'cust1', (db) => getDocs(query(collection(db, 'users'), where('phone', '>=', '+91'), limit(50))));
  deny('collection group users/*/saved_places', 'cust2', (db) => getDocs(collectionGroup(db, 'saved_places')));
  deny('read another user subcollection', 'cust2', (db) => getDoc(D(db, 'users/cust1/saved_places/p1')));
  deny('collection group messages', 'cust1', (db) => getDocs(collectionGroup(db, 'messages')));
  deny('collection group secrets (OTP)', 'drv1', (db) => getDocs(collectionGroup(db, 'secrets')));
  deny('collection group vehicle photos (plates, RC papers)', 'drv1', (db) => getDocs(query(collectionGroup(db, 'photos'), limit(50))));
  deny('list bookings without filter', 'cust1', (db) => getDocs(collection(db, 'bookings')));
  deny('list bookings of someone else', 'cust2', (db) => getDocs(query(collection(db, 'bookings'), where('customerId', '==', 'cust1'))));
  deny('read a booking as a stranger', 'cust2', (db) => getDoc(D(db, 'bookings/LM')));
  deny('other driver reads a booking', 'drv2', (db) => getDoc(D(db, 'bookings/LM')));
  deny('other driver reads someone else offer', 'drv2', (db) => getDoc(D(db, 'offers/L1_drv1')));
  deny('list all offers', 'drv2', (db) => getDocs(collection(db, 'offers')));
  deny('list offers of another driver', 'drv2', (db) => getDocs(query(collection(db, 'offers'), where('driverId', '==', 'drv1'))));
  deny('stranger reads a ledger line', 'drv2', (db) => getDoc(D(db, 'ledger/LD_trip_earning')));
  deny('stranger lists the ledger', 'drv2', (db) => getDocs(collection(db, 'ledger')));
  deny('stranger reads a wallet', 'drv2', (db) => getDoc(D(db, 'wallets/drv1')));
  deny('stranger reads a payout', 'drv2', (db) => getDoc(D(db, 'payouts/P_req')));
  deny('list all payouts', 'drv1', (db) => getDocs(collection(db, 'payouts')));
  deny('customer reads audit events', 'cust1', (db) => getDoc(D(db, 'audit_events/A1')));
  deny('driver lists audit events', 'drv1', (db) => getDocs(collection(db, 'audit_events')));
  deny('stranger reads a ticket', 'cust2', (db) => getDoc(D(db, 'tickets/T1')));
  deny('list tickets without filter', 'cust2', (db) => getDocs(collection(db, 'tickets')));
  deny('read an admin document of someone else', 'cust1', (db) => getDoc(D(db, 'admins/admin1')));
  deny('list admins', 'cust1', (db) => getDocs(collection(db, 'admins')));
  deny('staff lists admins', 'sup1', (db) => getDocs(collection(db, 'admins')));
  deny('stranger reads matched load of others', 'drv2', (db) => getDoc(D(db, 'loads/LM')));
  deny('list every lane tender without a filter (E30)', 'drv1', (db) => getDocs(collection(db, 'lane_rfqs')));
  deny('read the bids of a tender as another bidder (E30)', 'drv2', (db) => getDocs(collection(db, 'lane_rfqs/LR1/bids')));
  deny('stranger reads goods photos of a matched load (E19)', 'drv2', (db) => getDoc(D(db, 'loads/LM/cargo/goods1')));
  deny('driver writes goods photos into a load (E19)', 'drv1', (db) => setDoc(D(db, 'loads/L1/cargo/goods1'), { slot: 'goods1', path: 'loads/L1/cargo/goods1', at: serverTimestamp() }));
  deny('read an invented collection', 'cust1', (db) => getDoc(D(db, 'secrets_db/x')));
  deny('anonymous reads config', null, (db) => getDoc(D(db, 'config/dispatch')));
  deny('anonymous lists loads', null, (db) => getDocs(collection(db, 'loads')));
  allow('control: owner reads own user', 'cust1', (db) => getDoc(D(db, 'users/cust1')));
  allow('control: driver reads own wallet', 'drv1', (db) => getDoc(D(db, 'wallets/drv1')));
  allow('control: customer lists own bookings', 'cust1', (db) => getDocs(query(collection(db, 'bookings'), where('customerId', '==', 'cust1'))));
  allow('control: admin reads a user', 'admin1', (db) => getDoc(D(db, 'users/cust1')));
});

// ---------------------------------------------------------------- B, C self-escalation, mass assignment
describe('B/C. escalation and mass assignment on users', () => {
  const upd = (uid, data) => (db) => updateDoc(D(db, `users/${uid}`), data);
  allow('control: owner edits own name', 'cust1', upd('cust1', { name: 'Asha K' }));
  deny('customer becomes driver', 'cust1', upd('cust1', { role: 'driver' }));
  deny('customer becomes fleet', 'cust1', upd('cust1', { role: 'fleet', selectedRole: 'fleet' }));
  deny('selectedRole to admin', 'cust1', upd('cust1', { selectedRole: 'admin' }));
  deny('driver self-verifies', 'drv1', upd('drv1', { verified: true, verificationStatus: 'approved' }));
  deny('driver sets verified only', 'drv1', upd('drv1', { verified: true }));
  deny('driver forges verificationMeta', 'drv1', upd('drv1', { verificationMeta: { source: 'manual_review', by: 'admin1', status: 'approved' } }));
  deny('riskTier trusted', 'cust1', upd('cust1', { riskTier: 'trusted' }));
  deny('banned user clears own ban', 'ban1', upd('ban1', { riskTier: 'normal' }));
  deny('restricted user clears riskTier', 'rst1', upd('rst1', { riskTier: 'normal', riskReason: 'ok' }));
  deny('plan pro', 'drv1', upd('drv1', { plan: 'pro' }));
  deny('plan until far future', 'drv1', upd('drv1', { planUntil: Timestamp.fromDate(new Date('2099-01-01')) }));
  deny('doc override', 'drv1', upd('drv1', { docOverrideUntil: Timestamp.fromDate(new Date('2099-01-01')) }));
  deny('reviewFlag', 'cust1', upd('cust1', { reviewFlag: false }));
  deny('chat strikes reset', 'cust1', upd('cust1', { chatStrikes: 0, chatBlockedUntil: past() }));
  deny('cancelCount reset', 'cust1', upd('cust1', { cancelCount: 0 }));
  deny('cancelCount +5', 'cust1', upd('cust1', { cancelCount: 5 }));
  deny('create user doc for another uid', 'cust1', (db) => setDoc(D(db, 'users/newguy'), { role: 'customer' }));
  deny('create own doc as verified driver', 'cust2', (db) => setDoc(D(db, 'users/cust2'), { role: 'driver', verified: true, verificationStatus: 'approved' }));
  deny('create own doc with riskTier', 'cust2', (db) => setDoc(D(db, 'users/cust2'), { role: 'customer', riskTier: 'trusted' }));
  deny('create own doc with plan', 'cust2', (db) => setDoc(D(db, 'users/cust2'), { role: 'driver', plan: 'pro' }));
  deny('create own doc with an invalid role', 'cust2', (db) => setDoc(D(db, 'users/cust2'), { role: 'superuser' }));
  deny('name 20000 chars', 'cust1', upd('cust1', { name: HUGE }));
  deny('email 101 chars', 'cust1', upd('cust1', { email: 'a'.repeat(101) }));
  deny('name is a number', 'cust1', upd('cust1', { name: 12345 }));
  deny('4 emergency contacts', 'cust1', upd('cust1', { emergencyContacts: [{}, {}, {}, {}] }));
  deny('emergency contacts as a map', 'cust1', upd('cust1', { emergencyContacts: { a: 1 } }));
  deny('payout upi with a space', 'drv1', upd('drv1', { payoutProfile: { upiId: 'a b@upi', holder: 'x' } }));
  deny('payout profile extra key', 'drv1', upd('drv1', { payoutProfile: { upiId: 'ab@upi', holder: 'x', bank: 'y' } }));
  deny('fleet vehicleCount negative', 'flt1', upd('flt1', { fleet: { vehicleCount: -1 } }));
  deny('fleet vehicleCount float', 'flt1', upd('flt1', { fleet: { vehicleCount: 1.5 } }));
  deny('fleet routes 11 entries', 'flt1', upd('flt1', { fleet: { routes: Array(11).fill('a') } }));
  deny('full Aadhaar number', 'drv1', upd('drv1', { driverKyc: { dlNumber: 'DL12345678', rcNumber: 'RC123', aadhaarLast4: '123456789012', pan: 'ABCDE1234F', dlExpiry: Timestamp.fromDate(new Date('2030-01-01')) } }));
  deny('delete another user', 'cust1', (db) => deleteDoc(D(db, 'users/cust2')));
  deny('banned user deletes own account', 'ban1', (db) => deleteDoc(D(db, 'users/ban1')));
  deny('restricted user deletes own account', 'rst1', (db) => deleteDoc(D(db, 'users/rst1')));
  deny('write wallet', 'drv1', (db) => setDoc(D(db, 'wallets/drv1'), { balancePaise: 99999999 }));
  deny('admin writes wallet', 'admin1', (db) => setDoc(D(db, 'wallets/drv1'), { balancePaise: 99999999 }));
  deny('write kyc_checks', 'drv1', (db) => setDoc(D(db, 'kyc_checks/drv1'), { status: 'verified' }));
  deny('create an admin doc', 'cust1', (db) => setDoc(D(db, 'admins/cust1'), { role: 'super' }));
  deny('admin creates an admin doc', 'admin1', (db) => setDoc(D(db, 'admins/cust1'), { role: 'super' }));
  deny('support raises own role', 'sup1', (db) => updateDoc(D(db, 'admins/sup1'), { role: 'super' }));
  deny('delete own admin doc', 'admin1', (db) => deleteDoc(D(db, 'admins/admin1')));
  test('extra user field isAdmin grants nothing', async () => {
    stats.attacks++;
    await setDoc(D(as('cust1'), 'users/cust1'), { role: 'customer', selectedRole: 'customer', isAdmin: true, admin: true }, { merge: true }).catch(() => {});
    await assertFails(getDoc(D(as('cust1'), 'users/cust2')));
    await assertFails(updateDoc(D(as('cust1'), 'config/dispatch'), { acceptSeconds: 1 }));
  });
});

// ---------------------------------------------------------------- D, E loads, offers: numbers, sizes, ids, time
describe('D/E. loads and offers: numbers, sizes, ids, time', () => {
  // A load create must bump the hourly counter in the same batch.
  const createLoad = (over, uid = 'cust1', id = 'N1') => async (db) => {
    await seed((s) => setDoc(D(s, `rate_limits/${uid}_load`), { count: 1, windowStart: Timestamp.fromMillis(Date.now() - 7200_000), last: 'seed' }));
    const b = writeBatch(db);
    b.set(D(db, `loads/${id}`), { ...LOAD, shipperId: uid, ...over });
    b.set(D(db, `rate_limits/${uid}_load`), { count: 1, windowStart: serverTimestamp(), last: id });
    return b.commit();
  };
  allow('control: valid load create', 'cust1', createLoad({}));
  allow('control: valid load create with a server createdAt', 'cust1', createLoad({ createdAt: serverTimestamp() }));
  deny('load as someone else', 'cust1', createLoad({ shipperId: 'cust2' }));
  deny('load created already matched', 'cust1', createLoad({ status: 'matched', driverId: 'drv1' }));
  deny('load with a driverId on create', 'cust1', createLoad({ driverId: 'drv1' }));
  deny('load budget -1', 'cust1', createLoad({ budget: -1 }));
  deny('load budget huge', 'cust1', createLoad({ budget: 1e15 }));
  deny('load budget string', 'cust1', createLoad({ budget: '100' }));
  deny('load weight negative', 'cust1', createLoad({ weight: -3 }));
  deny('load weight zero', 'cust1', createLoad({ weight: 0 }));
  deny('load weight huge', 'cust1', createLoad({ weight: 1e9 }));
  deny('load pickup 20000 chars', 'cust1', createLoad({ pickup: HUGE }));
  deny('load notes 20000 chars', 'cust1', createLoad({ notes: HUGE }));
  deny('load cargoType invented', 'cust1', createLoad({ cargoType: 'x'.repeat(500) }));
  deny('load with big array field', 'cust1', createLoad({ extraPickups: Array(500).fill('Delhi') }));
  deny('load with huge map field', 'cust1', createLoad({ estimate: Object.fromEntries(Array.from({ length: 300 }, (_, i) => [`k${i}`, i])) }));
  deny('load pickupDate as string', 'cust1', createLoad({ pickupDate: 'today' }));
  deny('load without counter bump (rate limit bypass)', 'cust1', (db) => setDoc(D(db, 'loads/N2'), { ...LOAD }));
  deny('load with createdAt in the past', 'cust1', createLoad({ createdAt: past() }));
  deny('banned user creates a load', 'ban1', createLoad({ shipperId: 'ban1' }, 'ban1'));
  deny('anonymous creates a load', null, (db) => setDoc(D(db, 'loads/N3'), LOAD));

  // offers
  const offer = (over = {}, uid = 'drv2', vid = 'v2', num = 'KA01CD5678') => async (db) => {
    await seed((s) => setDoc(D(s, `rate_limits/${uid}_offer`), { count: 1, windowStart: Timestamp.fromMillis(Date.now() - 7200_000), last: 'seed' }));
    const id = `L1_${uid}`;
    const b = writeBatch(db);
    b.set(D(db, `offers/${id}`), {
      loadId: 'L1', driverId: uid, customerId: 'cust1', vehicleId: vid, vehicleNumber: num, pricePaise: 2000000, originalPaise: 2000000,
      status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    b.set(D(db, `rate_limits/${uid}_offer`), { count: 1, windowStart: serverTimestamp(), last: id });
    return b.commit();
  };
  // drv2 already has an offer L1_drv2 seeded; use a fresh load for the creates.
  const offerOnNew = (over, uid = 'drv2', vid = 'v2', num = 'KA01CD5678') => async (db) => {
    await seed((s) => setDoc(D(s, 'loads/L9'), LOAD));
    await seed((s) => setDoc(D(s, `rate_limits/${uid}_offer`), { count: 1, windowStart: Timestamp.fromMillis(Date.now() - 7200_000), last: 'seed' }));
    const id = `L9_${uid}`;
    const b = writeBatch(db);
    b.set(D(db, `offers/${id}`), {
      loadId: 'L9', driverId: uid, customerId: 'cust1', vehicleId: vid, vehicleNumber: num, pricePaise: 2000000, originalPaise: 2000000,
      status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    b.set(D(db, `rate_limits/${uid}_offer`), { count: 1, windowStart: serverTimestamp(), last: id });
    return b.commit();
  };
  void offer;
  allow('control: valid offer', 'drv2', offerOnNew({}));
  deny('offer price negative', 'drv2', offerOnNew({ pricePaise: -5, originalPaise: -5 }));
  deny('offer price zero', 'drv2', offerOnNew({ pricePaise: 0, originalPaise: 0 }));
  deny('offer price float', 'drv2', offerOnNew({ pricePaise: 1999999.5, originalPaise: 1999999.5 }));
  deny('offer price above 1e8', 'drv2', offerOnNew({ pricePaise: 100000001, originalPaise: 100000001 }));
  deny('offer price as string', 'drv2', offerOnNew({ pricePaise: '2000000' }));
  deny('offer originalPaise differs', 'drv2', offerOnNew({ originalPaise: 1 }));
  deny('offer already accepted', 'drv2', offerOnNew({ status: 'accepted' }));
  deny('offer as another driver', 'drv2', offerOnNew({ driverId: 'drv1' }));
  deny('offer for another customer', 'drv2', offerOnNew({ customerId: 'cust2' }));
  deny('offer with a vehicle of someone else', 'drv2', offerOnNew({ vehicleId: 'v1', vehicleNumber: 'MH12AB1234' }));
  deny('offer eta 0', 'drv2', offerOnNew({ etaMinutes: 0 }));
  deny('offer eta huge', 'drv2', offerOnNew({ etaMinutes: 99999 }));
  deny('offer noteChip free text', 'drv2', offerOnNew({ noteChip: 'call me on 9876543210' }));
  deny('offer unknown field', 'drv2', offerOnNew({ rank: 1 }));
  deny('offer with companyVerified true', 'drv2', offerOnNew({ companyVerified: true }));
  deny('offer driverName 20000 chars', 'drv2', offerOnNew({ driverName: HUGE }));
  deny('offer by restricted driver', 'rst1', offerOnNew({}, 'rst1', 'v3', 'GJ01EF9999'));
  deny('offer by shipper on own load', 'cust1', offerOnNew({}, 'cust1', 'v2', 'KA01CD5678'));
});

// ---------------------------------------------------------------- F state machine, replay
describe('F. state machine and replay', () => {
  const up = (path, data) => (db) => updateDoc(D(db, path), data);
  const ts = () => serverTimestamp();
  const withEstimate = () => seed((db) => updateDoc(D(db, 'loads/L1'), { estimate: { total: 2000000, tripFare: 2000000, distanceKm: 10 } }));
  deny('driver jumps accepted to delivered', 'drv1', up('bookings/LA', { status: 'delivered', timeline: { accepted: past(), delivered: ts() }, updatedAt: ts() }));
  deny('driver jumps accepted to in_transit', 'drv1', up('bookings/LA', { status: 'in_transit', timeline: { accepted: past(), in_transit: ts() }, updatedAt: ts() }));
  deny('driver steps backward in_transit to accepted', 'drv1', up('bookings/LM', { status: 'accepted', updatedAt: ts() }));
  deny('driver steps to picked_up without OTP', 'drv1', up('bookings/LM', { status: 'picked_up', updatedAt: ts() }));
  deny('driver delivers with a wrong OTP', 'drv1', up('bookings/LM', { status: 'delivered', deliveryOtp: '000000', updatedAt: ts() }));
  deny('driver cancels after delivery', 'drv1', up('bookings/LD', { status: 'cancelled', updatedAt: ts() }));
  deny('customer cancels after delivery', 'cust1', up('bookings/LD', { status: 'cancelled', updatedAt: ts() }));
  deny('customer sets status in_transit', 'cust1', up('bookings/LA', { status: 'in_transit', updatedAt: ts() }));
  deny('customer sets status delivered', 'cust1', up('bookings/LM', { status: 'delivered', updatedAt: ts() }));
  deny('stranger changes a booking', 'cust2', up('bookings/LM', { notes: 'hacked' }));
  deny('other driver changes a booking', 'drv2', up('bookings/LM', { status: 'unloading', updatedAt: ts() }));
  deny('driver changes driverId (hand-off)', 'drv1', up('bookings/LM', { driverId: 'drv2' }));
  deny('driver changes customerId', 'drv1', up('bookings/LM', { customerId: 'cust2' }));
  deny('driver changes agreed fare', 'drv1', up('bookings/LM', { agreedFarePaise: 1 }));
  deny('driver marks pickupOtpVerified', 'drv1', up('bookings/LM', { pickupOtpVerified: true }));
  deny('driver sets paidAmountPaise', 'drv1', up('bookings/LM', { paidAmountPaise: 99999999 }));
  deny('driver confirms payment never marked', 'drv1', up('bookings/LD', { paymentStatus: 'driver_confirmed', paymentConfirmedAt: ts(), updatedAt: ts() }));
  deny('customer marks paid with float', 'cust1', up('bookings/LD', { paymentStatus: 'customer_marked_paid', paidAmountPaise: 10.5, paymentMarkedAt: ts(), updatedAt: ts() }));
  deny('customer marks paid with negative', 'cust1', up('bookings/LD', { paymentStatus: 'customer_marked_paid', paidAmountPaise: -10, paymentMarkedAt: ts(), updatedAt: ts() }));
  deny('customer marks paid with client time', 'cust1', up('bookings/LD', { paymentStatus: 'customer_marked_paid', paidAmountPaise: 1000, paymentMarkedAt: past(), updatedAt: ts() }));
  deny('customer marks paid above 1e8', 'cust1', up('bookings/LD', { paymentStatus: 'customer_marked_paid', paidAmountPaise: 100000001, paymentMarkedAt: ts(), updatedAt: ts() }));
  deny('customer confirms payment as driver', 'cust1', up('bookings/LD', { paymentStatus: 'driver_confirmed', paymentConfirmedAt: ts(), updatedAt: ts() }));
  deny('delete a booking', 'drv1', (db) => deleteDoc(D(db, 'bookings/LM')));
  deny('delete a delivered booking as customer', 'cust1', (db) => deleteDoc(D(db, 'bookings/LD')));
  deny('create a booking without a load accept (forged)', 'drv1', (db) => setDoc(D(db, 'bookings/FAKE'), BOOKING({ loadId: 'L1', status: 'delivered', timeline: { accepted: ts(), delivered: ts() }, createdAt: ts(), updatedAt: ts() })));
  deny('create a booking for a load already matched', 'drv2', (db) => setDoc(D(db, 'bookings/LM2'), BOOKING({ loadId: 'LM', driverId: 'drv2', vehicleId: 'v2', vehicleNumber: 'KA01CD5678', status: 'accepted', timeline: { accepted: ts() }, createdAt: ts(), updatedAt: ts() })));
  // loads
  deny('shipper marks own open load delivered', 'cust1', up('loads/L1', { status: 'delivered' }));
  deny('shipper marks own open load matched with a driver', 'cust1', up('loads/L1', { status: 'matched', driverId: 'drv1' }));
  deny('shipper reopens a matched load', 'cust1', up('loads/LM', { status: 'open' }));
  deny('shipper changes the budget of a matched load', 'cust1', up('loads/LM', { budget: 1 }));
  deny('shipper deletes a matched load', 'cust1', (db) => deleteDoc(D(db, 'loads/LM')));
  deny('stranger edits an open load', 'cust2', up('loads/L1', { budget: 1 }));
  deny('driver edits an open load budget', 'drv1', up('loads/L1', { budget: 99999999 }));
  deny('stranger deletes an open load', 'cust2', (db) => deleteDoc(D(db, 'loads/L1')));
  deny('admin edits an open load', 'admin1', up('loads/L1', { budget: 1 }));
  // offers
  deny('driver raises price of an accepted offer', 'drv2', up('offers/L1_drv2', { pricePaise: 99999999, updatedAt: ts() }));
  deny('driver edits a pending offer to float', 'drv1', up('offers/L1_drv1', { pricePaise: 2000000.5, edited: true, updatedAt: ts() }));
  deny('driver edits a pending offer below 30%', 'drv1', async (db) => { await withEstimate(); return updateDoc(D(db, 'offers/L1_drv1'), { pricePaise: 1, edited: true, updatedAt: ts() }); });
  deny('driver edits a pending offer above 300%', 'drv1', async (db) => { await withEstimate(); return updateDoc(D(db, 'offers/L1_drv1'), { pricePaise: 99999999, edited: true, updatedAt: ts() }); });
  deny('driver self-selects own offer', 'drv1', up('offers/L1_drv1', { status: 'selected', updatedAt: ts() }));
  deny('driver self-accepts own offer', 'drv1', up('offers/L1_drv1', { status: 'accepted', updatedAt: ts() }));
  deny('another driver withdraws it', 'drv2', up('offers/L1_drv1', { status: 'withdrawn', updatedAt: ts() }));
  deny('customer changes the driver price', 'cust1', up('offers/L1_drv1', { pricePaise: 1, updatedAt: ts() }));
  deny('customer accepts on behalf of driver', 'cust1', up('offers/L1_drv1', { status: 'accepted', updatedAt: ts() }));
  deny('stranger customer counters', 'cust2', up('offers/L1_drv1', { status: 'countered', counterPaise: 1, updatedAt: ts() }));
  deny('delete an offer', 'drv1', (db) => deleteDoc(D(db, 'offers/L1_drv1')));
  // ratings
  deny('rate again (replay)', 'cust1', (db) => setDoc(D(db, 'ratings/LD_cust1'), { bookingId: 'LD', raterId: 'cust1', ratedId: 'drv1', stars: 1, createdAt: serverTimestamp() }));
  deny('edit a rating', 'cust1', up('ratings/LD_cust1', { stars: 1 }));
  deny('stars 6', 'drv1', (db) => setDoc(D(db, 'ratings/LD_drv1'), { bookingId: 'LD', raterId: 'drv1', ratedId: 'cust1', stars: 6, createdAt: serverTimestamp() }));
  deny('rate as someone else', 'cust2', (db) => setDoc(D(db, 'ratings/LD_cust1x'), { bookingId: 'LD', raterId: 'cust1', ratedId: 'drv1', stars: 5, createdAt: serverTimestamp() }));
  deny('rate a trip not delivered', 'drv1', (db) => setDoc(D(db, 'ratings/LM_drv1'), { bookingId: 'LM', raterId: 'drv1', ratedId: 'cust1', stars: 5, createdAt: serverTimestamp() }));
});

// ---------------------------------------------------------------- G money
describe('G. ledger, wallet, payouts', () => {
  const ts = () => serverTimestamp();
  deny('driver writes an earning with no payment', 'drv1', (db) => setDoc(D(db, 'ledger/LM_trip_earning'), { driverId: 'drv1', bookingId: 'LM', type: 'trip_earning', amountPaise: 99999999, createdAt: ts() }));
  deny('driver edits a ledger line', 'drv1', (db) => updateDoc(D(db, 'ledger/LD_trip_earning'), { amountPaise: 99999999 }));
  deny('driver deletes a ledger line', 'drv1', (db) => deleteDoc(D(db, 'ledger/LD_trip_earning')));
  deny('admin edits a ledger line', 'admin1', (db) => updateDoc(D(db, 'ledger/LD_trip_earning'), { amountPaise: 1 }));
  deny('admin deletes a ledger line', 'admin1', (db) => deleteDoc(D(db, 'ledger/LD_trip_earning')));
  deny('finance deletes a ledger line', 'fin1', (db) => deleteDoc(D(db, 'ledger/LD_trip_earning')));
  deny('driver writes a ledger line for another driver', 'drv1', (db) => setDoc(D(db, 'ledger/LD_trip_earning2'), { driverId: 'drv2', bookingId: 'LD', type: 'trip_earning', amountPaise: 1, createdAt: ts() }));
  deny('driver self-adjusts the wallet', 'drv1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 99999999, reason: 'bonus please', by: 'drv1', createdAt: ts() }));
  deny('support adjusts the wallet', 'sup1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100, reason: 'support adjusts', by: 'sup1', createdAt: ts() }));
  deny('finance adjusts with a float', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 10.5, reason: 'correction here', by: 'fin1', createdAt: ts() }));
  deny('finance adjusts above the cap', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100000000001, reason: 'correction here', by: 'fin1', createdAt: ts() }));
  deny('finance adjusts with zero', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 0, reason: 'correction here', by: 'fin1', createdAt: ts() }));
  deny('finance adjusts as someone else', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100, reason: 'correction here', by: 'fin2', createdAt: ts() }));
  deny('finance adjusts with client time', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100, reason: 'correction here', by: 'fin1', createdAt: past() }));
  deny('finance adjusts with a bad id', 'fin1', (db) => setDoc(D(db, 'ledger/zzz'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100, reason: 'correction here', by: 'fin1', createdAt: ts() }));
  allow('control: finance signed adjustment', 'fin1', (db) => setDoc(D(db, 'ledger/adj_12345678'), { driverId: 'drv1', type: 'adjustment', amountPaise: 100, reason: 'correction here', by: 'fin1', createdAt: ts() }));

  const payout = (over) => (db) => setDoc(D(db, 'payouts/PNEW'), { driverId: 'drv1', amountPaise: 1000, status: 'requested', createdAt: ts(), ...over });
  deny('payout as someone else', 'drv1', payout({ driverId: 'drv2' }));
  deny('payout already paid', 'drv1', payout({ status: 'paid' }));
  deny('payout already approved', 'drv1', payout({ status: 'approved' }));
  deny('payout 99 paise', 'drv1', payout({ amountPaise: 99 }));
  deny('payout negative', 'drv1', payout({ amountPaise: -1000 }));
  deny('payout float', 'drv1', payout({ amountPaise: 1000.5 }));
  deny('payout above 1e8', 'drv1', payout({ amountPaise: 100000001 }));
  deny('payout string', 'drv1', payout({ amountPaise: '1000' }));
  deny('payout with client time', 'drv1', payout({ createdAt: past() }));
  deny('payout with extra field', 'drv1', payout({ approvedBy: 'fin1' }));
  deny('payout above the wallet balance', 'drv1', payout({ amountPaise: 5000000 }));
  deny('payout by restricted driver', 'rst1', (db) => setDoc(D(db, 'payouts/PR'), { driverId: 'rst1', amountPaise: 1000, status: 'requested', createdAt: ts() }));
  const pu = (path, data, uid) => deny(`payout update ${path} ${JSON.stringify(Object.keys(data))} by ${uid}`, uid, (db) => updateDoc(D(db, path), data));
  pu('payouts/P_req', { status: 'paid', paidBy: 'drv1', paidAt: ts() }, 'drv1');
  pu('payouts/P_req', { amountPaise: 99999999 }, 'drv1');
  pu('payouts/P_req', { status: 'approved', approvedBy: 'sup1', approvedAt: ts() }, 'sup1');
  pu('payouts/P_req', { status: 'approved', approvedBy: 'admin1', approvedAt: ts() }, 'ver1');
  pu('payouts/P_req', { status: 'approved', approvedBy: 'fin2', approvedAt: ts() }, 'fin1');
  pu('payouts/P_req', { status: 'approved', approvedBy: 'fin1', approvedAt: past() }, 'fin1');
  pu('payouts/P_req', { status: 'paid', paidBy: 'fin1', paidAt: ts(), reference: 'UTR123456' }, 'fin1');
  pu('payouts/P_appr', { status: 'paid', paidBy: 'fin1', paidAt: ts(), reference: 'UTR123456' }, 'fin1'); // self-approval: fin1 approved it
  pu('payouts/P_appr', { status: 'paid', paidBy: 'fin2', paidAt: ts(), reference: 'ab' }, 'fin2');
  pu('payouts/P_appr', { status: 'paid', paidBy: 'fin2', paidAt: ts(), reference: 'UTR123456', amountPaise: 1 }, 'fin2');
  pu('payouts/P_paid', { status: 'requested' }, 'fin1');
  pu('payouts/P_paid', { status: 'reversed', reversedBy: 'fin1', reversedAt: ts(), reason: 'x' }, 'fin1');
  pu('payouts/P_paid', { status: 'reversed', reversedBy: 'sup1', reversedAt: ts(), reason: 'transfer returned' }, 'sup1');
  deny('delete a payout', 'fin1', (db) => deleteDoc(D(db, 'payouts/P_req')));
  allow('control: finance approves', 'fin1', (db) => updateDoc(D(db, 'payouts/P_req'), { status: 'approved', approvedBy: 'fin1', approvedAt: ts() }));
  allow('control: a different finance person pays', 'fin2', (db) => updateDoc(D(db, 'payouts/P_appr'), { status: 'paid', paidBy: 'fin2', paidAt: ts(), reference: 'UTR123456' }));
  deny('driver freezes/unfreezes own wallet', 'drv1', (db) => setDoc(D(db, 'wallet_freezes/drv1'), { frozen: false, reason: 'free me', by: 'drv1', updatedAt: ts() }));
  deny('support freezes a wallet', 'sup1', (db) => setDoc(D(db, 'wallet_freezes/drv1'), { frozen: true, reason: 'because', by: 'sup1', updatedAt: ts() }));
  deny('payout counters written by a client', 'drv1', (db) => setDoc(D(db, 'payout_counters/drv1_x'), { count: 0 }));
});

// ---------------------------------------------------------------- H staff roles, audit
describe('H. staff roles, audit, config', () => {
  const ts = () => serverTimestamp();
  deny('support sets a risk tier', 'sup1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'banned', riskReason: 'x', riskUpdatedAt: ts() }));
  deny('finance sets a risk tier', 'fin1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'banned', riskReason: 'x', riskUpdatedAt: ts() }));
  deny('risk tier with an invented value', 'admin1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'god', riskReason: 'x', riskUpdatedAt: ts() }));
  deny('risk update with client time', 'admin1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'review', riskReason: 'x', riskUpdatedAt: past() }));
  deny('risk update with extra field', 'admin1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'review', riskReason: 'x', riskUpdatedAt: ts(), role: 'driver' }));
  allow('control: super sets a risk tier', 'admin1', (db) => updateDoc(D(db, 'users/cust1'), { riskTier: 'review', riskReason: 'x', riskUpdatedAt: ts() }));
  deny('support approves a driver', 'sup1', (db) => updateDoc(D(db, 'users/drv1'), { verified: true, verificationStatus: 'approved', verificationMeta: { source: 'manual_review', by: 'sup1', status: 'approved', at: ts() }, updatedAt: ts() }));
  deny('verifier approves with someone else as by', 'ver1', (db) => updateDoc(D(db, 'users/drv1'), { verified: true, verificationStatus: 'approved', verificationMeta: { source: 'manual_review', by: 'admin1', status: 'approved', at: ts() }, updatedAt: ts() }));
  deny('verifier approves with verified mismatch', 'ver1', (db) => updateDoc(D(db, 'users/drv1'), { verified: true, verificationStatus: 'rejected', verificationMeta: { source: 'manual_review', by: 'ver1', status: 'rejected', at: ts(), reason: 'other' }, updatedAt: ts() }));
  deny('verifier also changes the role', 'ver1', (db) => updateDoc(D(db, 'users/drv1'), { verified: true, verificationStatus: 'approved', role: 'fleet', verificationMeta: { source: 'manual_review', by: 'ver1', status: 'approved', at: ts() }, updatedAt: ts() }));
  allow('control: verifier approves properly', 'ver1', (db) => updateDoc(D(db, 'users/drv1'), { verified: true, verificationStatus: 'approved', verificationMeta: { source: 'manual_review', by: 'ver1', status: 'approved', at: ts() }, updatedAt: ts() }));
  deny('support writes config', 'sup1', (db) => setDoc(D(db, 'config/dispatch'), { acceptSeconds: 1 }));
  deny('finance writes config', 'fin1', (db) => setDoc(D(db, 'config/dispatch'), { acceptSeconds: 1 }));
  deny('customer writes config', 'cust1', (db) => setDoc(D(db, 'config/dispatch'), { acceptSeconds: 1 }));
  deny('delete config', 'admin1', (db) => deleteDoc(D(db, 'config/dispatch')));
  // audit
  const ev = (over) => (db) => setDoc(D(db, 'audit_events/NEW'), { type: 'user_action', actorId: 'cust1', data: {}, createdAt: serverTimestamp(), ...over });
  deny('user forges an admin event type', 'cust1', ev({ type: 'verification' }));
  deny('user forges risk_change', 'cust1', ev({ type: 'risk_change' }));
  deny('user forges payout_decision', 'drv1', ev({ type: 'payout_decision', actorId: 'drv1' }));
  deny('user forges wallet_adjust', 'drv1', ev({ type: 'wallet_adjust', actorId: 'drv1' }));
  deny('event as another actor', 'cust1', ev({ type: 'accept', actorId: 'drv1' }));
  deny('event with client time', 'cust1', ev({ type: 'accept', createdAt: past() }));
  deny('event with unknown type', 'cust1', ev({ type: 'made_up' }));
  deny('event with extra field', 'cust1', ev({ type: 'accept', note: 'x' }));
  deny('event data as a string', 'cust1', ev({ type: 'accept', data: 'x' }));
  deny('edit an audit event', 'admin1', (db) => updateDoc(D(db, 'audit_events/A1'), { type: 'cancel' }));
  deny('delete an audit event', 'admin1', (db) => deleteDoc(D(db, 'audit_events/A1')));
  deny('user deletes own audit event', 'drv1', (db) => deleteDoc(D(db, 'audit_events/A1')));
});

// ---------------------------------------------------------------- I banned / restricted
describe('I. banned and restricted accounts', () => {
  const ts = () => serverTimestamp();
  deny('restricted driver creates a booking', 'rst1', (db) => setDoc(D(db, 'bookings/RB'), BOOKING({ loadId: 'L1', driverId: 'rst1', vehicleId: 'v3', vehicleNumber: 'GJ01EF9999', status: 'accepted', timeline: { accepted: ts() }, createdAt: ts(), updatedAt: ts() })));
  deny('restricted driver adds a payout', 'rst1', (db) => setDoc(D(db, 'payouts/PRR'), { driverId: 'rst1', amountPaise: 1000, status: 'requested', createdAt: ts() }));
  deny('banned customer edits own profile to remove the ban', 'ban1', (db) => updateDoc(D(db, 'users/ban1'), { riskTier: 'normal', riskReason: '', riskUpdatedAt: ts() }));
});

// ---------------------------------------------------------------- J OTP secrets
describe('J. OTP secrets', () => {
  const ts = () => serverTimestamp();
  deny('driver reads the OTP', 'drv1', (db) => getDoc(D(db, 'bookings/LM/secrets/otp')));
  deny('stranger reads the OTP', 'cust2', (db) => getDoc(D(db, 'bookings/LM/secrets/otp')));
  deny('anonymous reads the OTP', null, (db) => getDoc(D(db, 'bookings/LM/secrets/otp')));
  deny('list the secrets', 'cust1', (db) => getDocs(collection(db, 'bookings/LM/secrets')));
  deny('driver overwrites the OTP', 'drv1', (db) => setDoc(D(db, 'bookings/LM/secrets/otp'), { pickupOtp: '000000', deliveryOtp: '000000', createdAt: ts() }));
  deny('customer rewrites the OTP (update)', 'cust1', (db) => updateDoc(D(db, 'bookings/LM/secrets/otp'), { deliveryOtp: '000000' }));
  deny('customer deletes the OTP', 'cust1', (db) => deleteDoc(D(db, 'bookings/LM/secrets/otp')));
  deny('customer creates a 4-digit OTP', 'cust1', (db) => setDoc(D(db, 'bookings/LA/secrets/otp'), { pickupOtp: '1234', deliveryOtp: '222222', createdAt: ts() }));
  deny('customer creates a numeric (not string) OTP', 'cust1', (db) => setDoc(D(db, 'bookings/LA/secrets/otp'), { pickupOtp: 111111, deliveryOtp: '222222', createdAt: ts() }));
  deny('customer creates a secret with another id', 'cust1', (db) => setDoc(D(db, 'bookings/LA/secrets/other'), { pickupOtp: '111111', deliveryOtp: '222222', createdAt: ts() }));
  allow('control: customer reads own booking OTP', 'cust1', (db) => getDoc(D(db, 'bookings/LM/secrets/otp')));
});

// ---------------------------------------------------------------- K race
describe('K. two drivers accept the same load at once', () => {
  test('exactly one booking and the load is matched once', async () => {
    stats.attacks++;
    const acceptBatch = (uid, vid, num) => async () => {
      const db = as(uid);
      const b = writeBatch(db);
      b.set(D(db, 'bookings/L1'), BOOKING({ loadId: 'L1', driverId: uid, vehicleId: vid, vehicleNumber: num, status: 'accepted', timeline: { accepted: serverTimestamp() }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
      b.update(D(db, 'loads/L1'), { status: 'matched', driverId: uid, bookingId: 'L1', matchedAt: serverTimestamp() });
      b.update(D(db, `vehicles/${vid}`), { availability: 'on_trip' });
      return b.commit();
    };
    const results = await Promise.allSettled([acceptBatch('drv1', 'v1', 'MH12AB1234')(), acceptBatch('drv2', 'v2', 'KA01CD5678')()]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    if (ok !== 1) throw new Error(`expected exactly one winner, got ${ok}`);
  });
  deny('second accept after the load is matched', 'drv2', async (db) => {
    await seed((s) => updateDoc(D(s, 'loads/L1'), { status: 'matched', driverId: 'drv1', bookingId: 'L1' }));
    const b = writeBatch(db);
    b.set(D(db, 'bookings/L1'), BOOKING({ loadId: 'L1', driverId: 'drv2', vehicleId: 'v2', vehicleNumber: 'KA01CD5678', status: 'accepted', timeline: { accepted: serverTimestamp() }, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    b.update(D(db, 'loads/L1'), { status: 'matched', driverId: 'drv2', bookingId: 'L1', matchedAt: serverTimestamp() });
    return b.commit();
  });
  deny('self-referral code on own uid', 'cust1', (db) => setDoc(D(db, 'referrals/cust1'), { referrerId: 'cust1', refereeId: 'cust1', createdAt: serverTimestamp() }));
});
