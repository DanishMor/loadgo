// Security rules tests. Run with: npm test  (starts the Firestore emulator)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { GeoPoint, Timestamp, addDoc, deleteField, doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp, increment } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
// admins/{uid} allowlist: admin1 is an admin (created by hand in the Console in real life).
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'admins', 'admin1'), { createdBy: 'console' }));
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const asAdmin = () => env.authenticatedContext('admin1').firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const LOAD = {
  shipperId: 'customer1',
  pickup: 'Delhi',
  drop: 'Mumbai',
  cargoType: 'FMCG',
  weight: 8,
  vehicleType: '20ft',
  budget: 25000,
  pickupDate: Timestamp.fromDate(new Date('2026-10-05')),
  notes: '',
  status: 'open',
};
const VEHICLE = { ownerId: 'driver1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1', status: 'active' };

function bookingFor(loadId, overrides = {}) {
  return {
    loadId,
    driverId: 'driver1',
    vehicleId: 'v1',
    customerId: 'customer1',
    status: 'accepted',
    pickup: LOAD.pickup,
    drop: LOAD.drop,
    cargoType: LOAD.cargoType,
    weight: LOAD.weight,
    vehicleType: LOAD.vehicleType,
    budget: LOAD.budget,
    pickupDate: LOAD.pickupDate,
    notes: '',
    vehicleNumber: VEHICLE.number,
    driverName: 'Ramesh',
    driverPhone: '+919800000000',
    timeline: { accepted: serverTimestamp() },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

/** Same writes as BookingService.accept (batched like the transaction commit). */
function acceptBatch(db, loadId, driver = 'driver1', bookingOverrides = {}) {
  const b = writeBatch(db);
  b.set(doc(db, 'bookings', loadId), bookingFor(loadId, { driverId: driver, ...bookingOverrides }));
  b.update(doc(db, 'loads', loadId), { status: 'matched', driverId: driver, bookingId: loadId, matchedAt: serverTimestamp() });
  b.update(doc(db, 'vehicles', bookingOverrides.vehicleId ?? (driver === 'driver2' ? 'v2' : 'v1')), { availability: 'on_trip' });
  return b.commit();
}

/** Same writes as VehicleService.add: vehicle + number reservation. */
function addVehicle(db, id, data = VEHICLE) {
  const b = writeBatch(db);
  b.set(doc(db, 'vehicle_numbers', data.number), { ownerId: data.ownerId, vehicleId: id });
  b.set(doc(db, 'vehicles', id), data);
  return b.commit();
}

async function seedOpenLoad() {
  await seed(async (db) => {
    await setDoc(doc(db, 'loads', 'L1'), LOAD);
    await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    await setDoc(doc(db, 'vehicles', 'v2'), { ...VEHICLE, ownerId: 'driver2', number: 'KA01CD5678' });
  });
}

const OTPS = { pickupOtp: '482913', deliveryOtp: '771204' };
const PICKUP = { packages: 40, weightTons: 7.5, sealNumber: 'SL-9', damageNote: '' };
const DELIVERY = { receiverName: 'Anil', receiverPhone: '+919811111111', damageNote: '' };

async function seedBooking(status = 'accepted') {
  await seedOpenLoad();
  await seed(async (db) => {
    await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, status: 'matched', driverId: 'driver1', bookingId: 'L1' });
    await setDoc(doc(db, 'bookings', 'L1'), { ...bookingFor('L1'), status, timeline: {} });
  });
}

describe('users', () => {
  test('owner reads/writes own doc; others cannot', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', selectedRole: 'customer' }));
    await assertSucceeds(getDoc(doc(as('u1'), 'users', 'u1')));
    await assertFails(getDoc(doc(as('u2'), 'users', 'u1')));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u1'), { phone: 'x' }));
    await assertFails(getDoc(doc(anon(), 'users', 'u1')));
  });

  test('drivers cannot approve themselves', async () => {
    await assertFails(setDoc(doc(as('d1'), 'users', 'd1'), { verified: true, verificationStatus: 'approved' }));
    await assertSucceeds(setDoc(doc(as('d1'), 'users', 'd1'), { phone: '+91' }));
    // First driver profile save initialises pending/false.
    await assertSucceeds(updateDoc(doc(as('d1'), 'users', 'd1'), { verified: false, verificationStatus: 'pending', driverName: 'R' }));
    await assertFails(updateDoc(doc(as('d1'), 'users', 'd1'), { verificationStatus: 'approved' }));
    await assertFails(updateDoc(doc(as('d1'), 'users', 'd1'), { verified: true }));
    await assertSucceeds(updateDoc(doc(as('d1'), 'users', 'd1'), { driverName: 'Ramesh' }));
  });
});

describe('role lock', () => {
  test('role is set once and then frozen', async () => {
    const ref = doc(as('u1'), 'users', 'u1');
    await assertSucceeds(setDoc(ref, { phone: '+91', role: 'customer', selectedRole: 'customer' }));
    await assertFails(updateDoc(ref, { role: 'driver' }));
    await assertFails(updateDoc(ref, { role: 'driver', selectedRole: 'driver' }));
    await assertFails(updateDoc(ref, { selectedRole: 'driver' }));
    await assertFails(updateDoc(ref, { role: deleteField() }));
    await assertFails(setDoc(ref, { phone: '+91', role: 'driver', selectedRole: 'driver' }));
    await assertSucceeds(updateDoc(ref, { name: 'Anil' }));
  });

  test('only customer or driver are valid roles', async () => {
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1'), { role: 'admin' }));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u2'), { role: 'customer', selectedRole: 'driver' }));
  });

  test('an older account without a role can set it once', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'old1'), { phone: '+91', selectedRole: 'driver' }));
    const ref = doc(as('old1'), 'users', 'old1');
    await assertFails(updateDoc(ref, { role: 'owner' }));
    await assertSucceeds(updateDoc(ref, { role: 'driver' }));
    await assertFails(updateDoc(ref, { role: 'customer' }));
  });

  test('an admin cannot change the role either', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { role: 'customer', selectedRole: 'customer' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { role: 'driver' }));
  });
});

describe('driver KYC and identity index', () => {
  const KYC = { dlNumber: 'MH1220110012345', dlExpiry: Timestamp.fromDate(new Date('2030-01-01')), rcNumber: 'MH12AB1234', aadhaarLast4: '4321', pan: 'ABCDE1234F' };
  const H1 = 'a'.repeat(64);
  const H2 = 'b'.repeat(64);
  const seedUser = (uid, role) => seed((db) => setDoc(doc(db, 'users', uid), { role, selectedRole: role }));

  test('KYC keeps only the last four Aadhaar digits', async () => {
    await seedUser('d1', 'driver');
    const ref = doc(as('d1'), 'users', 'd1');
    await assertFails(updateDoc(ref, { driverKyc: { ...KYC, aadhaarLast4: '123456789012' }, kycComplete: true }));
    await assertFails(updateDoc(ref, { driverKyc: { ...KYC, aadhaarNumber: '123456789012' }, kycComplete: true }));
    await assertFails(updateDoc(ref, { driverKyc: { ...KYC, pan: 'abc' }, kycComplete: true }));
    await assertFails(updateDoc(ref, { kycComplete: true }));
    await assertSucceeds(updateDoc(ref, { driverKyc: KYC, kycComplete: true }));
  });

  test('identity_index: create-only, own uid and role, admin-only update/delete', async () => {
    await seedUser('d1', 'driver');
    await seedUser('d2', 'driver');
    await seedUser('c1', 'customer');
    const entry = (uid, role) => ({ uid, role, type: 'dl', createdAt: serverTimestamp() });
    const claim = async (uid, hash, role = 'driver') => {
      const db = as(uid);
      const b = writeBatch(db);
      b.update(doc(db, 'users', uid), { identityHashes: { dl: hash } });
      b.set(doc(db, 'identity_index', hash), { uid, role, type: 'dl', createdAt: serverTimestamp() });
      return b.commit();
    };
    await assertSucceeds(claim('d1', H1));
    await assertFails(claim('d2', H1));
    // the same document again: by the same account, as another role
    await assertFails(setDoc(doc(as('d1'), 'identity_index', H1), entry('d1', 'driver')));
    await assertFails(claim('c1', H1, 'customer'));
    // cannot claim for someone else, with the wrong role, extra fields or a plain-text id
    await assertFails(setDoc(doc(as('d2'), 'identity_index', H2), entry('d1', 'driver')));
    await assertFails(setDoc(doc(as('d2'), 'identity_index', H2), entry('d2', 'customer')));
    await assertFails(setDoc(doc(as('d2'), 'identity_index', H2), { ...entry('d2', 'driver'), number: 'MH12' }));
    await assertFails(setDoc(doc(as('d2'), 'identity_index', 'MH1220110012345'), entry('d2', 'driver')));
    await assertFails(setDoc(doc(anon(), 'identity_index', H2), entry('d2', 'driver')));
    // update / delete: admin only
    await assertFails(updateDoc(doc(as('d1'), 'identity_index', H1), { uid: 'd2' }));
    await assertFails(deleteDoc(doc(as('d1'), 'identity_index', H1)));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'identity_index', H1), { uid: 'd2' }));
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'identity_index', H1)));
  });

  test('identity_index: get for signed-in users, never list', async () => {
    await seed((db) => setDoc(doc(db, 'identity_index', H1), { uid: 'd1', role: 'driver' }));
    await assertSucceeds(getDoc(doc(as('d2'), 'identity_index', H1)));
    await assertFails(getDoc(doc(anon(), 'identity_index', H1)));
    await assertFails(getDocs(collection(as('d2'), 'identity_index')));
  });

  test('profile and index can be written together in one batch', async () => {
    await seedUser('d1', 'driver');
    const db = as('d1');
    const batch = writeBatch(db);
    batch.set(doc(db, 'users', 'd1'), { driverKyc: KYC, kycComplete: true }, { merge: true });
    batch.update(doc(db, 'users', 'd1'), { identityHashes: { dl: H1 } });
    batch.set(doc(db, 'identity_index', H1), { uid: 'd1', role: 'driver', type: 'dl', createdAt: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });
});

describe('identity edits', () => {
  const H = (c) => c.repeat(64);
  const seedDriver = (uid, hashes) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', uid), { role: 'driver', selectedRole: 'driver', identityHashes: hashes });
      for (const [type, h] of Object.entries(hashes)) await setDoc(doc(db, 'identity_index', h), { uid, role: 'driver', type });
    });
  const edit = (uid, { hashes, create = [], del = [] }) => {
    const db = as(uid);
    const b = writeBatch(db);
    b.update(doc(db, 'users', uid), { identityHashes: hashes });
    for (const [type, h] of create) b.set(doc(db, 'identity_index', h), { uid, role: 'driver', type, createdAt: serverTimestamp() });
    for (const h of del) b.delete(doc(db, 'identity_index', h));
    return b.commit();
  };

  test('changing a number: delete old + create new in one batch works', async () => {
    await seedDriver('d1', { dl: H('a'), pan: H('b') });
    await assertSucceeds(edit('d1', { hashes: { dl: H('c'), pan: H('b') }, create: [['dl', H('c')]], del: [H('a')] }));
    let gone;
    await seed(async (db) => { gone = !(await getDoc(doc(db, 'identity_index', H('a')))).exists(); });
    assert.equal(gone, true);
  });

  test('deleting without a replacement is refused (cannot free a number to reuse it elsewhere)', async () => {
    await seedDriver('d1', { dl: H('a'), pan: H('b') });
    await assertFails(deleteDoc(doc(as('d1'), 'identity_index', H('a'))));
    await assertFails(edit('d1', { hashes: { dl: H('a'), pan: H('b') }, del: [H('a')] }));
    await assertFails(edit('d1', { hashes: { dl: H('d'), pan: H('b') }, del: [H('a')] }));
    await assertFails(edit('d1', { hashes: { pan: H('b') }, del: [H('a')] }));
  });

  test('a replacement that belongs to someone else does not count', async () => {
    await seedDriver('d1', { dl: H('a') });
    await seedDriver('d2', { dl: H('e') });
    await assertFails(edit('d1', { hashes: { dl: H('e') }, del: [H('a')] }));
  });

  test('creating an entry the profile does not name is refused', async () => {
    await seedDriver('d1', { dl: H('a') });
    await assertFails(edit('d1', { hashes: { dl: H('a') }, create: [['pan', H('f')]] }));
  });

  test('GST can be cleared, other documents cannot', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', 'c1'), { role: 'customer', selectedRole: 'customer', identityHashes: { gst: H('9') } });
      await setDoc(doc(db, 'identity_index', H('9')), { uid: 'c1', role: 'customer', type: 'gst' });
    });
    const db = as('c1');
    const b = writeBatch(db);
    b.update(doc(db, 'users', 'c1'), { identityHashes: {} });
    b.delete(doc(db, 'identity_index', H('9')));
    await assertSucceeds(b.commit());
  });

  test('entries made before the type field existed can be replaced, not just dropped', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', 'd1'), { role: 'driver', selectedRole: 'driver' });
      await setDoc(doc(db, 'identity_index', H('1')), { uid: 'd1', role: 'driver' });
    });
    await assertFails(deleteDoc(doc(as('d1'), 'identity_index', H('1'))));
    await assertSucceeds(edit('d1', { hashes: { dl: H('2') }, create: [['dl', H('2')]], del: [H('1')] }));
  });

  test('identityHashes must be known keys with hash values', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'd1'), { role: 'driver', selectedRole: 'driver' }));
    const ref = doc(as('d1'), 'users', 'd1');
    await assertFails(updateDoc(ref, { identityHashes: { aadhaar: H('a') } }));
    await assertFails(updateDoc(ref, { identityHashes: { dl: '1234' } }));
    await assertSucceeds(updateDoc(ref, { identityHashes: { dl: H('a') } }));
  });
});

describe('driver last location', () => {
  const loc = (over = {}) => ({ lat: 28.61, lng: 77.21, geohash: 'ttnfv2u9d', updatedAt: serverTimestamp(), ...over });
  test('owner saves a valid position with a geohash; bad data is refused', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'd1'), { role: 'driver', selectedRole: 'driver', consents: { location: true, analytics: false, marketing: false } }));
    const ref = doc(as('d1'), 'users', 'd1');
    await assertSucceeds(updateDoc(ref, { lastLocation: loc() }));
    await assertFails(updateDoc(ref, { lastLocation: loc({ lat: 123 }) }));
    await assertFails(updateDoc(ref, { lastLocation: loc({ lng: 'x' }) }));
    await assertFails(updateDoc(ref, { lastLocation: loc({ geohash: 'NOT A HASH!' }) }));
    await assertFails(updateDoc(ref, { lastLocation: loc({ updatedAt: Timestamp.fromDate(new Date('2020-01-01')) }) }));
    await assertFails(updateDoc(ref, { lastLocation: { ...loc(), address: 'home' } }));
    await assertFails(updateDoc(doc(as('d2'), 'users', 'd1'), { lastLocation: loc() }));
  });
});

describe('location consent', () => {
  const loc = { lat: 28.61, lng: 77.21, geohash: 'ttnfv2u9d', updatedAt: serverTimestamp() };
  test('no location is stored without consent; switching consent off can delete it', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'd1'), { role: 'driver', selectedRole: 'driver' }));
    const ref = doc(as('d1'), 'users', 'd1');
    await assertFails(updateDoc(ref, { lastLocation: loc }));
    await assertSucceeds(updateDoc(ref, { consents: { location: true, analytics: false, marketing: false }, lastLocation: loc }));
    await assertFails(updateDoc(ref, { consents: { location: false, analytics: false, marketing: false } }));
    await assertSucceeds(updateDoc(ref, { consents: { location: false, analytics: false, marketing: false }, lastLocation: deleteField() }));
    await assertFails(updateDoc(ref, { lastLocation: loc }));
  });
});

describe('pickup geohash', () => {
  test('optional, must look like a geohash', async () => {
    await assertSucceeds(addDoc(collection(as('customer1'), 'loads'), { ...LOAD, pickupGeohash: 'ttnfv2u' }));
    await assertFails(addDoc(collection(as('customer1'), 'loads'), { ...LOAD, pickupGeohash: 'NOT A HASH' }));
    await assertFails(addDoc(collection(as('customer1'), 'loads'), { ...LOAD, pickupGeohash: 12 }));
  });

  test('admin can backfill an old load, but not change anything else or overwrite', async () => {
    await seed((db) => setDoc(doc(db, 'loads', 'old'), LOAD));
    await seed((db) => setDoc(doc(db, 'loads', 'new'), { ...LOAD, pickupGeohash: 'ttnfv2u' }));
    await assertFails(updateDoc(doc(as('customer2'), 'loads', 'old'), { pickupGeohash: 'ttnfv2u' }));
    await assertFails(updateDoc(doc(asAdmin(), 'loads', 'old'), { pickupGeohash: 'ttnfv2u', budget: 1 }));
    await assertFails(updateDoc(doc(asAdmin(), 'loads', 'old'), { pickupGeohash: 'BAD' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'loads', 'old'), { pickupGeohash: 'ttnfv2u' }));
    await assertFails(updateDoc(doc(asAdmin(), 'loads', 'new'), { pickupGeohash: 'ttnfv2v' }));
  });
});

describe('booking types', () => {
  const post = (extra) => addDoc(collection(as('customer1'), 'loads'), { ...LOAD, ...extra });
  const MOVERS = { items: [{ name: 'Sofa', qty: 1 }], floor: 2, hasLift: false, packing: true };

  test('helpers 0-4 on any type', async () => {
    await assertSucceeds(post({ helpers: 0 }));
    await assertSucceeds(post({ helpers: 4, bookingType: 'freight' }));
    await assertFails(post({ helpers: 5 }));
    await assertFails(post({ helpers: -1 }));
    await assertFails(post({ helpers: 1.5 }));
  });

  test('rental needs 4, 8 or 12 hours and nothing else may carry hours', async () => {
    await assertSucceeds(post({ bookingType: 'rental', rentalHours: 8 }));
    await assertFails(post({ bookingType: 'rental', rentalHours: 6 }));
    await assertFails(post({ bookingType: 'rental' }));
    await assertFails(post({ rentalHours: 8 }));
    await assertFails(post({ bookingType: 'movers', movers: MOVERS, rentalHours: 4 }));
  });

  test('movers needs a valid request and only movers may have one', async () => {
    await assertSucceeds(post({ bookingType: 'movers', movers: MOVERS }));
    await assertFails(post({ bookingType: 'movers' }));
    await assertFails(post({ bookingType: 'movers', movers: { ...MOVERS, items: [] } }));
    await assertFails(post({ bookingType: 'movers', movers: { ...MOVERS, floor: 99 } }));
    await assertFails(post({ bookingType: 'movers', movers: { ...MOVERS, items: [{ name: 'Sofa', qty: 0 }] } }));
    await assertFails(post({ bookingType: 'movers', movers: { ...MOVERS, hasLift: 'yes' } }));
    await assertFails(post({ bookingType: 'movers', movers: { ...MOVERS, extra: 1 } }));
    await assertFails(post({ movers: MOVERS }));
    await assertFails(post({ bookingType: 'teleport' }));
  });

  test('estimate lines must be non-negative integers', async () => {
    const est = { total: 1000, tripFare: 900, distanceKm: 10 };
    await assertSucceeds(post({ estimate: { ...est, helperCharge: 300, rentalCharge: 0, packingCharge: 100 } }));
    await assertFails(post({ estimate: { ...est, helperCharge: -1 } }));
    await assertFails(post({ estimate: { ...est, floorCharge: 1.5 } }));
  });
});

describe('customer offers', () => {
  const future = Timestamp.fromDate(new Date('2035-01-01'));
  const past = Timestamp.fromDate(new Date('2020-01-01'));
  const promoDoc = (over = {}) => ({
    code: 'SAVE10', type: 'percent', value: 10, maxDiscountPaise: 0, minOrderPaise: 0, expiresAt: future,
    usageLimit: 3, perUserLimit: 1, active: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
  });
  const seedPromo = (over = {}) => seed((db) => setDoc(doc(db, 'promos', over.code ?? 'SAVE10'), promoDoc({ ...over, createdAt: Timestamp.now(), updatedAt: Timestamp.now() })));
  const EST = { total: 50000, tripFare: 45000, distanceKm: 10 };

  // One batch: the load with its promo / credits, plus the documents the rules ask for.
  function postOffer(uid, { id = 'L9', promo, credits = 0, slot, use, est = EST, extra = [] } = {}) {
    if (est === undefined) est = EST;
    const db = as(uid);
    const b = writeBatch(db);
    const load = { ...LOAD, shipperId: uid, estimate: est };
    if (est === false) delete load.estimate;
    if (promo) load.promo = { ...promo, slot: slot ?? 1, use: use ?? 1 };
    if (credits) load.creditsUsedPaise = credits;
    b.set(doc(db, 'loads', id), load);
    if (promo && slot !== null) b.set(doc(db, 'promos', promo.code, 'slots', String(slot ?? 1)), { loadId: id, createdAt: serverTimestamp() });
    if (promo && use !== null) b.set(doc(db, 'promos', promo.code, 'uses', `${uid}_${use ?? 1}`), { uid, loadId: id, createdAt: serverTimestamp() });
    if (credits) b.set(doc(db, 'users', uid, 'credits', `spend_${id}`), { amountPaise: -credits, kind: 'spend', loadId: id, createdAt: serverTimestamp() });
    for (const fn of extra) fn(b, db);
    return b.commit();
  }

  test('admins manage promo codes; others only read one by code', async () => {
    await assertSucceeds(setDoc(doc(asAdmin(), 'promos', 'SAVE10'), promoDoc()));
    await assertFails(setDoc(doc(as('customer1'), 'promos', 'NEWONE'), promoDoc({ code: 'NEWONE' })));
    await assertSucceeds(getDoc(doc(as('customer1'), 'promos', 'SAVE10')));
    await assertFails(getDocs(collection(as('customer1'), 'promos')));
    await assertSucceeds(getDocs(collection(asAdmin(), 'promos')));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'promos', 'SAVE10'), { active: false, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(asAdmin(), 'promos', 'BAD'), promoDoc({ code: 'BAD', value: 150 })));
    await assertFails(setDoc(doc(asAdmin(), 'promos', 'OTHER'), promoDoc({ code: 'SAVE10' })));
    await assertFails(setDoc(doc(asAdmin(), 'promos', 'low'), promoDoc({ code: 'low' })));
    await assertFails(setDoc(doc(asAdmin(), 'promos', 'ZERO'), promoDoc({ code: 'ZERO', perUserLimit: 0 })));
  });

  test('a load can carry a promo only with the exact discount and its slot / use documents', async () => {
    await seedPromo();
    await assertSucceeds(postOffer('customer1', { promo: { code: 'SAVE10', discountPaise: 5000 } }));
    await seedPromo({ code: 'SAVE10' });
  });

  test('wrong discount, missing documents or a bad number are refused', async () => {
    await seedPromo();
    const p = (d) => ({ code: 'SAVE10', discountPaise: d });
    await assertFails(postOffer('customer1', { promo: p(6000) }));
    await assertFails(postOffer('customer1', { promo: p(0) }));
    await assertFails(postOffer('customer1', { promo: p(5000), slot: null }));
    await assertFails(postOffer('customer1', { promo: p(5000), use: null }));
    await assertFails(postOffer('customer1', { promo: p(5000), slot: 4 }), 'slot above the usage limit');
    await assertFails(postOffer('customer1', { promo: p(5000), slot: 0 }));
    await assertFails(postOffer('customer1', { promo: p(5000), use: 2 }), 'second use but perUserLimit is 1');
    await assertFails(postOffer('customer1', { promo: p(5000), est: false }));
  });

  test('cap and flat codes use the same arithmetic as the app', async () => {
    await seedPromo({ code: 'CAP', value: 50, maxDiscountPaise: 3000 });
    await assertFails(postOffer('customer1', { promo: { code: 'CAP', discountPaise: 25000 } }));
    await assertSucceeds(postOffer('customer1', { promo: { code: 'CAP', discountPaise: 3000 } }));
    await seedPromo({ code: 'FLAT', type: 'flat', value: 80000 });
    await assertSucceeds(postOffer('customer2', { id: 'L10', promo: { code: 'FLAT', discountPaise: 50000 } }));
  });

  test('expired, switched-off and too-small orders are refused', async () => {
    const p = (code) => ({ code, discountPaise: 5000 });
    await seedPromo({ code: 'OLD', expiresAt: past });
    await seedPromo({ code: 'OFF', active: false });
    await seedPromo({ code: 'BIG', minOrderPaise: 60000 });
    await assertFails(postOffer('customer1', { promo: p('OLD') }));
    await assertFails(postOffer('customer1', { promo: p('OFF') }));
    await assertFails(postOffer('customer1', { promo: p('BIG') }));
  });

  test('a slot or per-user number cannot be taken twice', async () => {
    await seedPromo({ perUserLimit: 2 });
    const p = { code: 'SAVE10', discountPaise: 5000 };
    await assertSucceeds(postOffer('customer1', { id: 'A', promo: p, slot: 1, use: 1 }));
    await assertFails(postOffer('customer2', { id: 'B', promo: p, slot: 1, use: 1 }), 'slot 1 is taken');
    await assertFails(postOffer('customer1', { id: 'C', promo: p, slot: 2, use: 1 }), 'use 1 is taken');
    await assertSucceeds(postOffer('customer1', { id: 'D', promo: p, slot: 2, use: 2 }));
    await assertFails(postOffer('customer1', { id: 'E', promo: p, slot: 3, use: 3 }), 'beyond perUserLimit');
    await assertSucceeds(postOffer('customer2', { id: 'F', promo: p, slot: 3, use: 1 }));
    await assertFails(postOffer('customer3', { id: 'G', promo: p, slot: 4, use: 1 }), 'beyond usageLimit');
  });

  test('slot documents cannot be forged for someone else\'s load or edited', async () => {
    await seedPromo();
    await seed((db) => setDoc(doc(db, 'loads', 'LX'), { ...LOAD, shipperId: 'customer2' }));
    await assertFails(setDoc(doc(as('customer1'), 'promos', 'SAVE10', 'slots', '1'), { loadId: 'LX', createdAt: serverTimestamp() }));
    await assertSucceeds(postOffer('customer1', { promo: { code: 'SAVE10', discountPaise: 5000 } }));
    await assertFails(updateDoc(doc(as('customer1'), 'promos', 'SAVE10', 'slots', '1'), { loadId: 'other' }));
    await assertFails(deleteDoc(doc(as('customer1'), 'promos', 'SAVE10', 'slots', '1')));
    await assertSucceeds(getDoc(doc(as('customer2'), 'promos', 'SAVE10', 'slots', '1')));
  });

  test('the promo cannot be added or changed after posting', async () => {
    await seedPromo();
    await seed((db) => setDoc(doc(db, 'loads', 'L1'), { ...LOAD, estimate: EST }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { promo: { code: 'SAVE10', discountPaise: 5000, slot: 1, use: 1 } }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { creditsUsedPaise: 100 }));
  });

  test('credits: spend lines match the load; positive lines come only from referral or admin', async () => {
    await assertSucceeds(postOffer('customer1', { credits: 12000 }));
    await assertFails(postOffer('customer1', { id: 'L10', credits: 12000, est: { total: 5000, tripFare: 4000, distanceKm: 1 } }), 'more than the order');
    // spend line that does not match the load's creditsUsedPaise
    const db = as('customer1');
    const b = writeBatch(db);
    b.set(doc(db, 'loads', 'L11'), { ...LOAD, shipperId: 'customer1', estimate: EST, creditsUsedPaise: 100 });
    b.set(doc(db, 'users', 'customer1', 'credits', 'spend_L11'), { amountPaise: -500, kind: 'spend', loadId: 'L11', createdAt: serverTimestamp() });
    await assertFails(b.commit());
    // credits claimed on a load without the ledger line
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L12'), { ...LOAD, shipperId: 'customer1', estimate: EST, creditsUsedPaise: 100 }));
    // free money
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'credits', 'x'), { amountPaise: 999999, kind: 'spend', createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'credits', 'x'), { amountPaise: 999999, kind: 'admin_grant', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('customer1'), 'users', 'customer1', 'credits', 'spend_L9'), { amountPaise: 0 }));
    await assertFails(deleteDoc(doc(as('customer1'), 'users', 'customer1', 'credits', 'spend_L9')));
  });

  test('credits: admins grant and deduct; owners read, others do not', async () => {
    await assertSucceeds(addDoc(collection(asAdmin(), 'users', 'customer1', 'credits'), { amountPaise: 50000, kind: 'admin_grant', note: 'sorry', createdAt: serverTimestamp() }));
    await assertSucceeds(addDoc(collection(asAdmin(), 'users', 'customer1', 'credits'), { amountPaise: -20000, kind: 'admin_deduct', createdAt: serverTimestamp() }));
    await assertFails(addDoc(collection(asAdmin(), 'users', 'customer1', 'credits'), { amountPaise: 0, kind: 'admin_grant', createdAt: serverTimestamp() }));
    await assertSucceeds(getDocs(collection(as('customer1'), 'users', 'customer1', 'credits')));
    await assertFails(getDocs(collection(as('customer2'), 'users', 'customer1', 'credits')));
  });

  describe('referral', () => {
    const fresh = Timestamp.now();
    const old = Timestamp.fromDate(new Date(Date.now() - 9 * 86400000));
    const seedUsers = (refereeCreated = fresh) =>
      seed(async (db) => {
        await setDoc(doc(db, 'users', 'referrer'), { role: 'customer', createdAt: old, referralCode: 'FRIEND' });
        await setDoc(doc(db, 'referral_codes', 'FRIEND'), { uid: 'referrer' });
        await setDoc(doc(db, 'users', 'newbie'), { role: 'customer', createdAt: refereeCreated });
      });
    const apply = (uid, { code = 'FRIEND', referrer = 'referrer', amountIn = 10000, amountFrom = 10000, skipFrom = false, skipIn = false } = {}) => {
      const db = as(uid);
      const b = writeBatch(db);
      b.set(doc(db, 'referrals', uid), { referrerUid: referrer, code, createdAt: serverTimestamp() });
      if (!skipIn) b.set(doc(db, 'users', uid, 'credits', 'referral_in'), { amountPaise: amountIn, kind: 'referral', createdAt: serverTimestamp() });
      if (!skipFrom) b.set(doc(db, 'users', referrer, 'credits', `referral_from_${uid}`), { amountPaise: amountFrom, kind: 'referral', createdAt: serverTimestamp() });
      return b.commit();
    };

    test('a new customer applies a friend\'s code once and both get a credit line', async () => {
      await seedUsers();
      await assertSucceeds(apply('newbie'));
      await assertFails(apply('newbie'), 'a second referral');
      await assertSucceeds(getDoc(doc(as('referrer'), 'referrals', 'newbie')));
      await assertFails(getDoc(doc(as('customer2'), 'referrals', 'newbie')));
    });

    test('abuse: own code, wrong owner, old account, wrong amount, missing line', async () => {
      await seedUsers();
      await assertFails(apply('referrer', { referrer: 'referrer' }), 'own code');
      await assertFails(apply('newbie', { referrer: 'someoneElse' }), 'code belongs to another user');
      await assertFails(apply('newbie', { amountIn: 99999 }));
      await assertFails(apply('newbie', { amountFrom: 99999 }));
      await assertFails(apply('newbie', { skipFrom: true }));
      await assertFails(apply('newbie', { skipIn: true }));
      await seed((db) => setDoc(doc(db, 'users', 'newbie'), { role: 'customer', createdAt: old }));
      await assertFails(apply('newbie'), 'account older than 7 days');
    });

    test('the bonus follows config/offers', async () => {
      await seedUsers();
      await seed((db) => setDoc(doc(db, 'config', 'offers'), { referralBonusPaise: 25000 }));
      await assertFails(apply('newbie'));
      await assertSucceeds(apply('newbie', { amountIn: 25000, amountFrom: 25000 }));
    });

    test('referral credit lines cannot be written without a referral', async () => {
      await seedUsers();
      await assertFails(setDoc(doc(as('newbie'), 'users', 'newbie', 'credits', 'referral_in'), { amountPaise: 10000, kind: 'referral', createdAt: serverTimestamp() }));
      await assertFails(setDoc(doc(as('newbie'), 'users', 'referrer', 'credits', 'referral_from_newbie'), { amountPaise: 10000, kind: 'referral', createdAt: serverTimestamp() }));
    });

    test('each user claims one code, set once on the profile', async () => {
      await seed((db) => setDoc(doc(db, 'users', 'u1'), { role: 'customer', createdAt: fresh }));
      const db = as('u1');
      const claim = (code) => {
        const b = writeBatch(db);
        b.update(doc(db, 'users', 'u1'), { referralCode: code });
        b.set(doc(db, 'referral_codes', code), { uid: 'u1', createdAt: serverTimestamp() });
        return b.commit();
      };
      await assertFails(claim('abc'), 'too short');
      await assertSucceeds(claim('ABCD23'));
      await assertFails(claim('ZZZZ99'), 'a second code');
      await assertFails(updateDoc(doc(db, 'users', 'u1'), { referralCode: 'ZZZZ99' }));
      await seed((d) => setDoc(doc(d, 'users', 'u2'), { role: 'customer', createdAt: fresh }));
      const db2 = as('u2');
      const b2 = writeBatch(db2);
      b2.update(doc(db2, 'users', 'u2'), { referralCode: 'ABCD23' });
      b2.set(doc(db2, 'referral_codes', 'ABCD23'), { uid: 'u2', createdAt: serverTimestamp() });
      await assertFails(b2.commit(), 'code already taken');
      await assertSucceeds(getDoc(doc(db2, 'referral_codes', 'ABCD23')));
      await assertFails(getDocs(collection(db2, 'referral_codes')));
    });
  });
});

describe('driver extras', () => {
  const now = Date.now();
  const days = (n) => Timestamp.fromDate(new Date(now + n * 86400000));
  const seedDelivered = (status = 'delivered') => seed((db) => setDoc(doc(db, 'bookings', 'B1'), { ...bookingFor('L1'), status, timeline: {} }));
  const tip = (over = {}) => ({ bookingId: 'B1', customerId: 'customer1', driverId: 'driver1', amountPaise: 5000, createdAt: serverTimestamp(), ...over });

  describe('tips', () => {
    test('the customer tips a delivered booking once; both parties read it', async () => {
      await seedDelivered();
      await assertSucceeds(setDoc(doc(as('customer1'), 'tips', 'B1'), tip()));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ amountPaise: 9000 })), 'second tip is an update');
      await assertSucceeds(getDoc(doc(as('driver1'), 'tips', 'B1')));
      await assertSucceeds(getDoc(doc(as('customer1'), 'tips', 'B1')));
      await assertFails(getDoc(doc(as('driver2'), 'tips', 'B1')));
      await assertFails(deleteDoc(doc(as('customer1'), 'tips', 'B1')));
    });

    test('refused: not delivered, wrong party, bad amount, wrong driver, extra fields', async () => {
      await seedDelivered('in_transit');
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip()));
      await seedDelivered();
      await assertFails(setDoc(doc(as('customer2'), 'tips', 'B1'), tip({ customerId: 'customer2' })));
      await assertFails(setDoc(doc(as('driver1'), 'tips', 'B1'), tip({ customerId: 'driver1' })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ amountPaise: 50 })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ amountPaise: 500001 })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ amountPaise: 99.5 })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ driverId: 'driver2' })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ note: 'x' })));
      await assertFails(setDoc(doc(as('customer1'), 'tips', 'B1'), tip({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
    });
  });

  describe('incentives and claims', () => {
    const inc = (over = {}) => ({ title: 'Weekly 10', targetTrips: 10, windowDays: 7, bonusPaise: 50000, startsAt: days(-1), active: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
    const seedInc = (over = {}) => seed(async (db) => {
      await setDoc(doc(db, 'incentives', 'I1'), { ...inc(over), createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' });
    });
    const claim = (over = {}) => ({ incentiveId: 'I1', driverId: 'driver1', bonusPaise: 50000, status: 'claimed', createdAt: serverTimestamp(), ...over });

    test('only admins write incentives, with sane numbers; everyone signed in reads', async () => {
      await assertSucceeds(setDoc(doc(asAdmin(), 'incentives', 'I1'), inc()));
      await assertFails(setDoc(doc(as('driver1'), 'incentives', 'I2'), inc()));
      await assertSucceeds(getDoc(doc(as('driver1'), 'incentives', 'I1')));
      await assertFails(setDoc(doc(asAdmin(), 'incentives', 'I3'), inc({ targetTrips: 0 })));
      await assertFails(setDoc(doc(asAdmin(), 'incentives', 'I3'), inc({ windowDays: 400 })));
      await assertFails(setDoc(doc(asAdmin(), 'incentives', 'I3'), inc({ bonusPaise: 1.5 })));
      await assertFails(setDoc(doc(asAdmin(), 'incentives', 'I3'), inc({ title: 'x' })));
      await assertSucceeds(updateDoc(doc(asAdmin(), 'incentives', 'I1'), { active: false, updatedAt: serverTimestamp() }));
    });

    test('a driver claims once with the exact bonus inside the window', async () => {
      await seedInc();
      await assertSucceeds(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()));
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()), 'second claim');
      await assertSucceeds(getDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1')));
      await assertFails(getDoc(doc(as('driver2'), 'incentive_claims', 'I1_driver1')));
      await assertSucceeds(getDoc(doc(asAdmin(), 'incentive_claims', 'I1_driver1')));
    });

    test('refused: bigger bonus, someone else, wrong id, paid status, inactive, outside the window', async () => {
      await seedInc();
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim({ bonusPaise: 99999 })));
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver2'), claim({ driverId: 'driver2' })));
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'other'), claim()));
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim({ status: 'paid' })));
      await seedInc({ active: false });
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()));
      await seedInc({ startsAt: days(-30) });
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()), 'window and grace are over');
      await seedInc({ startsAt: days(2) });
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()), 'not started');
    });

    test('a restricted driver cannot claim; only an admin marks a claim paid', async () => {
      await seedInc();
      await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', riskTier: 'restricted' }));
      await assertFails(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()));
      await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' }));
      await assertSucceeds(setDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), claim()));
      await assertFails(updateDoc(doc(as('driver1'), 'incentive_claims', 'I1_driver1'), { status: 'paid', paidAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(asAdmin(), 'incentive_claims', 'I1_driver1'), { status: 'paid', bonusPaise: 1 }));
      await assertSucceeds(updateDoc(doc(asAdmin(), 'incentive_claims', 'I1_driver1'), { status: 'paid', paidAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(asAdmin(), 'incentive_claims', 'I1_driver1'), { status: 'claimed' }));
    });
  });

  describe('plans', () => {
    test('a driver asks for Pro; asking again only after an answer', async () => {
      const req = () => ({ uid: 'driver1', plan: 'pro', status: 'pending', createdAt: serverTimestamp() });
      await assertSucceeds(setDoc(doc(as('driver1'), 'plan_requests', 'driver1'), req()));
      await assertFails(setDoc(doc(as('driver1'), 'plan_requests', 'driver1'), req()), 'still pending');
      await assertFails(setDoc(doc(as('driver1'), 'plan_requests', 'driver2'), { ...req(), uid: 'driver2' }));
      await assertFails(setDoc(doc(as('driver2'), 'plan_requests', 'driver2'), { ...req(), uid: 'driver2', status: 'approved' }));
      await assertSucceeds(updateDoc(doc(asAdmin(), 'plan_requests', 'driver1'), { status: 'rejected', answeredAt: serverTimestamp() }));
      await assertSucceeds(setDoc(doc(as('driver1'), 'plan_requests', 'driver1'), req()));
      await assertFails(updateDoc(doc(as('driver1'), 'plan_requests', 'driver1'), { status: 'approved' }));
    });

    test('only an admin can change users.plan; nobody can give themselves Pro', async () => {
      await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' }));
      await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { plan: 'pro' }));
      await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { planUntil: Timestamp.fromDate(new Date('2030-01-01')) }));
      await assertFails(setDoc(doc(as('driver9'), 'users', 'driver9'), { plan: 'pro' }));
      await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'driver1'), { plan: 'pro', planUntil: days(30), updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(asAdmin(), 'users', 'driver1'), { plan: 'gold', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(asAdmin(), 'users', 'driver1'), { plan: 'pro', name: 'x', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { plan: 'free' }));
      await assertSucceeds(updateDoc(doc(as('driver1'), 'users', 'driver1'), { driverName: 'Ramesh' }));
    });
  });
});

describe('reminder queries', () => {
  test('a customer can list the offers made on their loads, a driver their own, nobody else\'s', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'offers', 'L1_driver1'), { loadId: 'L1', driverId: 'driver1', customerId: 'customer1', status: 'pending' });
      await setDoc(doc(db, 'offers', 'L2_driver2'), { loadId: 'L2', driverId: 'driver2', customerId: 'customer2', status: 'pending' });
    });
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'offers'), where('customerId', '==', 'customer1'))));
    await assertSucceeds(getDocs(query(collection(as('driver1'), 'offers'), where('driverId', '==', 'driver1'))));
    await assertFails(getDocs(query(collection(as('customer1'), 'offers'), where('customerId', '==', 'customer2'))));
  });
});

describe('vehicle profile, goods flags and review record', () => {
  test('vehicle: dimensions, fuel, body type and tyre date are validated', async () => {
    let n = 0;
    const v = (extra) => {
      n += 1;
      const number = `MH12AB${1000 + n}`;
      return addVehicle(as('driver1'), `vp${n}`, { ...VEHICLE, number, ...extra });
    };
    await assertSucceeds(v({ lengthM: 6.1, widthM: 2.4, heightM: 2.4, fuel: 'diesel', bodyType: 'closed', nextTyreCheckDate: Timestamp.fromDate(new Date('2026-12-01')) }));
    await assertFails(v({ lengthM: 0 }));
    await assertFails(v({ lengthM: 31 }));
    await assertFails(v({ widthM: 'wide' }));
    await assertFails(v({ fuel: 'coal' }));
    await assertFails(v({ bodyType: 'boat' }));
    await assertFails(v({ nextTyreCheckDate: 'soon' }));
    await assertSucceeds(v({}));
  });

  test('load: fragile and highValue must be booleans', async () => {
    const post = (extra) => addDoc(collection(as('customer1'), 'loads'), { ...LOAD, ...extra });
    await assertSucceeds(post({ fragile: true, highValue: false }));
    await assertFails(post({ fragile: 'yes' }));
    await assertFails(post({ highValue: 1 }));
  });

  test('online flag is free for the owner', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'users', 'driver1'), { online: true, onlineChangedAt: serverTimestamp() }));
  });

  test('review record: only an admin writes it, as themselves, matching the decision', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verified: false, verificationStatus: 'pending' }));
    const meta = (over = {}) => ({ source: 'manual_review', by: 'admin1', status: 'approved', at: serverTimestamp(), ...over });
    const approve = (over = {}, status = 'approved') =>
      updateDoc(doc(asAdmin(), 'users', 'driver1'), { verified: status === 'approved', verificationStatus: status, verificationMeta: meta(over), updatedAt: serverTimestamp() });
    await assertFails(approve({ by: 'someoneElse' }));
    await assertFails(approve({ source: 'kyc_api' }));
    await assertFails(approve({ status: 'rejected' }));
    await assertFails(approve({ extra: 1 }));
    await assertFails(approve({ at: Timestamp.fromDate(new Date('2020-01-01')) }));
    await assertSucceeds(approve());
    // owners cannot forge or change it
    await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { verificationMeta: meta() }));
    await assertFails(setDoc(doc(as('newdriver'), 'users', 'newdriver'), { verificationMeta: meta() }));
  });
});

describe('payouts, fraud cases, detention and config audit', () => {
  test('payouts: a driver asks once for a valid amount; only admins answer', async () => {
    const req = (over = {}) => ({ driverId: 'driver1', amountPaise: 5000, status: 'requested', createdAt: serverTimestamp(), ...over });
    await assertSucceeds(addDoc(collection(as('driver1'), 'payouts'), req()));
    await assertFails(addDoc(collection(as('driver1'), 'payouts'), req({ amountPaise: 50 })));
    await assertFails(addDoc(collection(as('driver1'), 'payouts'), req({ amountPaise: 100000001 })));
    await assertFails(addDoc(collection(as('driver1'), 'payouts'), req({ amountPaise: 99.5 })));
    await assertFails(addDoc(collection(as('driver1'), 'payouts'), req({ status: 'paid' })));
    await assertFails(addDoc(collection(as('driver2'), 'payouts'), req()));
    await seed((db) => setDoc(doc(db, 'users', 'driver3'), { role: 'driver', selectedRole: 'driver', riskTier: 'suspended' }));
    await assertFails(addDoc(collection(as('driver3'), 'payouts'), req({ driverId: 'driver3' })));
    await seed((db) => setDoc(doc(db, 'payouts', 'P1'), { driverId: 'driver1', amountPaise: 5000, status: 'requested' }));
    await assertFails(updateDoc(doc(as('driver1'), 'payouts', 'P1'), { status: 'paid' }));
    await assertFails(updateDoc(doc(asAdmin(), 'payouts', 'P1'), { status: 'paid', amountPaise: 1, handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'payouts', 'P1'), { status: 'paid', handledBy: 'someone', handledAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'payouts', 'P1'), { status: 'paid', handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'payouts', 'P1'), { status: 'rejected', handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(as('driver1'), 'payouts', 'P1')));
    await assertFails(getDoc(doc(as('driver2'), 'payouts', 'P1')));
  });

  test('fraud cases: admin only, notes append-only, closing needs an outcome', async () => {
    const c = (over = {}) => ({ userId: 'u1', summary: 'Fake papers', status: 'open', reportIds: [], createdBy: 'admin1', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
    await assertFails(setDoc(doc(as('driver1'), 'fraud_cases', 'C1'), c({ createdBy: 'driver1' })));
    await assertFails(setDoc(doc(asAdmin(), 'fraud_cases', 'C1'), c({ summary: 'x' })));
    await assertFails(setDoc(doc(asAdmin(), 'fraud_cases', 'C1'), c({ createdBy: 'other' })));
    await assertSucceeds(setDoc(doc(asAdmin(), 'fraud_cases', 'C1'), c()));
    await assertFails(getDoc(doc(as('driver1'), 'fraud_cases', 'C1')));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'fraud_cases', 'C1'), { status: 'investigating', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'fraud_cases', 'C1'), { status: 'resolved', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'fraud_cases', 'C1'), { status: 'resolved', outcome: 'jailed', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'fraud_cases', 'C1'), { userId: 'u2', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'fraud_cases', 'C1'), { status: 'resolved', outcome: 'warned', resolvedBy: 'admin1', resolvedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    const note = (over = {}) => ({ by: 'admin1', text: 'Checked', createdAt: serverTimestamp(), ...over });
    await assertSucceeds(addDoc(collection(asAdmin(), 'fraud_cases', 'C1', 'notes'), note()));
    await assertFails(addDoc(collection(asAdmin(), 'fraud_cases', 'C1', 'notes'), note({ by: 'x' })));
    await assertFails(addDoc(collection(asAdmin(), 'fraud_cases', 'C1', 'notes'), note({ text: '' })));
    await assertFails(addDoc(collection(as('driver1'), 'fraud_cases', 'C1', 'notes'), note({ by: 'driver1' })));
  });

  test('config changes are audited by admins only', async () => {
    const ev = (uid) => ({ type: 'config_change', actorId: uid, targetId: 'pricing', data: { doc: 'pricing', changedKeys: ['gstPercent'] }, createdAt: serverTimestamp() });
    await assertSucceeds(addDoc(collection(asAdmin(), 'audit_events'), ev('admin1')));
    await assertFails(addDoc(collection(as('driver1'), 'audit_events'), ev('driver1')));
  });

  describe('detention', () => {
    const seedStage = (status, detention) => seed((db) => setDoc(doc(db, 'bookings', 'D1'), { ...bookingFor('L1'), status, timeline: {}, ...(detention ? { detention } : {}) }));
    const set = (uid, status, detention) => updateDoc(doc(as(uid), 'bookings', 'D1'), { detention, updatedAt: serverTimestamp() });

    test('start the clock while loading, stop it with the minutes waited', async () => {
      await seedStage('loading');
      await assertSucceeds(set('driver1', 'loading', { loadingStartedAt: serverTimestamp() }));
      await seedStage('loading', { loadingStartedAt: Timestamp.fromMillis(Date.now() - 20 * 60000) });
      await assertSucceeds(set('driver1', 'loading', { loadingMinutes: 21 }));
    });

    test('refused: wrong stage, other people, too many minutes, shrinking, forged start', async () => {
      await seedStage('in_transit');
      await assertFails(set('driver1', 'in_transit', { loadingStartedAt: serverTimestamp() }));
      await seedStage('loading');
      await assertFails(set('customer1', 'loading', { loadingStartedAt: serverTimestamp() }));
      await assertFails(set('driver2', 'loading', { loadingStartedAt: serverTimestamp() }));
      await assertFails(set('driver1', 'loading', { loadingMinutes: 30 }), 'minutes without a running clock');
      await assertFails(set('driver1', 'loading', { loadingStartedAt: Timestamp.fromMillis(Date.now() - 3600000) }), 'start must be now');
      await assertFails(set('driver1', 'loading', { loadingStartedAt: serverTimestamp(), extra: 1 }));
      await seedStage('loading', { loadingStartedAt: Timestamp.fromMillis(Date.now() - 20 * 60000) });
      await assertFails(set('driver1', 'loading', { loadingMinutes: 90 }), 'more than the clock ran');
      await assertFails(set('driver1', 'loading', { loadingMinutes: 5000 }));
      await seedStage('loading', { loadingMinutes: 40 });
      await assertFails(set('driver1', 'loading', { loadingMinutes: 10 }), 'minutes cannot shrink');
    });

    test('unloading works the same and does not disturb loading minutes', async () => {
      await seedStage('unloading', { loadingMinutes: 40 });
      await assertSucceeds(set('driver1', 'unloading', { loadingMinutes: 40, unloadingStartedAt: serverTimestamp() }));
    });
  });
});

describe('trip evidence', () => {
  const seedB = (status, extra = {}) => seed((db) => setDoc(doc(db, 'bookings', 'E1'), { ...bookingFor('L1'), status, timeline: {}, ...extra }));
  const upd = (uid, data) => updateDoc(doc(as(uid), 'bookings', 'E1'), { ...data, updatedAt: serverTimestamp() });

  test('GPS evidence: once, by the driver, at the right stage, stamped now', async () => {
    await seedB('loading');
    await assertFails(upd('driver1', { pickupGps: new GeoPoint(28.6, 77.2), pickupGpsAt: serverTimestamp() }), 'not picked up yet');
    await seedB('picked_up');
    await assertFails(upd('customer1', { pickupGps: new GeoPoint(28.6, 77.2), pickupGpsAt: serverTimestamp() }));
    await assertFails(upd('driver1', { pickupGps: new GeoPoint(28.6, 77.2) }), 'needs the timestamp');
    await assertFails(upd('driver1', { pickupGps: 'Delhi', pickupGpsAt: serverTimestamp() }));
    await assertFails(upd('driver1', { pickupGps: new GeoPoint(28.6, 77.2), pickupGpsAt: Timestamp.fromDate(new Date('2020-01-01')) }));
    await assertSucceeds(upd('driver1', { pickupGps: new GeoPoint(28.6, 77.2), pickupGpsAt: serverTimestamp() }));
    await seedB('picked_up', { pickupGps: new GeoPoint(1, 1), pickupGpsAt: Timestamp.now() });
    await assertFails(upd('driver1', { pickupGps: new GeoPoint(28.6, 77.2), pickupGpsAt: serverTimestamp() }), 'cannot be replaced');
    await seedB('in_transit');
    await assertFails(upd('driver1', { deliveryGps: new GeoPoint(26.9, 75.8), deliveryGpsAt: serverTimestamp() }), 'too early');
    await seedB('unloading');
    await assertSucceeds(upd('driver1', { deliveryGps: new GeoPoint(26.9, 75.8), deliveryGpsAt: serverTimestamp() }));
  });

  test('odometer: start before pickup, end after, never below start, once each', async () => {
    await seedB('loading');
    await assertSucceeds(upd('driver1', { odometerStart: 120500 }));
    await assertFails(upd('driver1', { odometerStart: -5 }));
    await assertFails(upd('driver1', { odometerStart: 12.5 }));
    await assertFails(upd('driver1', { odometerEnd: 120600 }), 'trip has not started');
    await seedB('in_transit', { odometerStart: 120500 });
    await assertFails(upd('driver1', { odometerEnd: 120400 }), 'below the start');
    await assertFails(upd('customer1', { odometerEnd: 120900 }));
    await assertSucceeds(upd('driver1', { odometerEnd: 120900 }));
    await seedB('in_transit', { odometerStart: 120500, odometerEnd: 120900 });
    await assertFails(upd('driver1', { odometerEnd: 121000 }), 'once');
    await assertFails(upd('driver1', { odometerStart: 1 }), 'once');
  });

  test('signature: driver only, once, while unloading or delivered', async () => {
    const sig = (over = {}) => ({ strokes: [{ p: [0.1, 0.2, 0.5, 0.6] }], driverId: 'driver1', createdAt: serverTimestamp(), ...over });
    const ref = (uid) => doc(as(uid), 'bookings', 'E1', 'signatures', 'receiver');
    await seedB('in_transit');
    await assertFails(setDoc(ref('driver1'), sig()));
    await seedB('unloading');
    await assertFails(setDoc(ref('customer1'), sig({ driverId: 'customer1' })));
    await assertFails(setDoc(ref('driver1'), sig({ strokes: [] })));
    await assertFails(setDoc(ref('driver1'), sig({ extra: 1 })));
    await assertFails(setDoc(doc(as('driver1'), 'bookings', 'E1', 'signatures', 'other'), sig()));
    await assertSucceeds(setDoc(ref('driver1'), sig()));
    await assertFails(setDoc(ref('driver1'), sig()), 'second signature');
    await assertSucceeds(getDoc(ref('customer1')));
    await assertFails(getDoc(ref('driver2')));
    await assertFails(deleteDoc(ref('driver1')));
  });

  test('cargo documents: either party appends, nobody edits or deletes', async () => {
    await seedB('in_transit');
    const d = (uid, over = {}) => ({ type: 'invoice', number: 'INV-1', addedBy: uid, createdAt: serverTimestamp(), ...over });
    const col = (uid) => collection(as(uid), 'bookings', 'E1', 'cargo_docs');
    await assertSucceeds(addDoc(col('customer1'), d('customer1')));
    await assertSucceeds(addDoc(col('driver1'), d('driver1', { type: 'eway_bill', number: '123456789012', leg: 2, note: 'leg two' })));
    await assertFails(addDoc(col('driver2'), d('driver2')), 'not a party');
    await assertFails(addDoc(col('customer1'), d('driver1')), 'addedBy must be the caller');
    await assertFails(addDoc(col('customer1'), d('customer1', { type: 'passport' })));
    await assertFails(addDoc(col('customer1'), d('customer1', { number: '' })));
    await assertFails(addDoc(col('customer1'), d('customer1', { number: 'x'.repeat(41) })));
    await assertFails(addDoc(col('customer1'), d('customer1', { leg: 3 })));
    await assertFails(addDoc(col('customer1'), d('customer1', { note: 'n'.repeat(201) })));
    const snap = await getDocs(col('customer1'));
    await assertFails(updateDoc(snap.docs[0].ref, { number: 'CHANGED' }));
    await assertFails(deleteDoc(snap.docs[0].ref));
    await assertFails(getDocs(col('driver2')));
  });

  test('new notification types are accepted for the booking parties', async () => {
    await seedB('delivered');
    const n = (type, userId) => ({ userId, type, message: 'x', relatedId: 'E1', read: false, createdAt: serverTimestamp() });
    const db = as('customer1');
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'E1'), { paymentStatus: 'customer_marked_paid', paidAmountPaise: 25000, paymentMarkedAt: serverTimestamp(), updatedAt: serverTimestamp() });
    b.set(doc(db, 'notifications', 'n1'), n('payment_marked', 'driver1'));
    await assertSucceeds(b.commit());
    await assertSucceeds(addDoc(collection(as('driver1'), 'notifications'), n('accident_reported', 'customer1')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), n('made_up', 'customer1')));
  });
});

describe('devices and risk signals', () => {
  const dev = (over = {}) => ({ label: 'android', trusted: true, revoked: false, firstSeenAt: serverTimestamp(), lastSeenAt: serverTimestamp(), lastLoginAt: serverTimestamp(), ...over });
  const DID = 'abcdefgh12345678';

  test('a user keeps their own device list', async () => {
    const ref = (uid) => doc(as(uid), 'users', 'u1', 'devices', DID);
    await assertSucceeds(setDoc(ref('u1'), dev()));
    await assertFails(setDoc(ref('u2'), dev()));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'devices', 'x'), dev()), 'id too short');
    await assertFails(setDoc(ref('u1'), dev({ trusted: 'yes' })));
    await assertFails(setDoc(ref('u1'), dev({ label: 'x'.repeat(41) })));
    await assertFails(setDoc(ref('u1'), dev({ imei: '123' })));
    await assertSucceeds(updateDoc(ref('u1'), { revoked: true, trusted: false }));
    await assertSucceeds(getDoc(ref('u1')));
    await assertFails(getDoc(ref('u2')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'users', 'u1', 'devices', DID)));
  });

  test('device links: own uid only, id from device and uid, admins read', async () => {
    const link = (uid, over = {}) => ({ deviceId: DID, uid, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('u1'), 'device_links', `${DID}_u1`), link('u1')));
    await assertFails(setDoc(doc(as('u1'), 'device_links', `${DID}_u2`), link('u2')));
    await assertFails(setDoc(doc(as('u1'), 'device_links', 'wrongid'), link('u1')));
    await assertFails(updateDoc(doc(as('u1'), 'device_links', `${DID}_u1`), { uid: 'u2' }));
    await assertSucceeds(getDocs(collection(asAdmin(), 'device_links')));
    await assertFails(getDocs(collection(as('u1'), 'device_links')));
  });

  test('risk signals: written for yourself, read by admins', async () => {
    const sig = (uid, over = {}) => ({ uid, type: 'new_device', deviceId: DID, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(addDoc(collection(as('u1'), 'risk_signals'), sig('u1')));
    await assertSucceeds(addDoc(collection(as('u1'), 'risk_signals'), sig('u1', { type: 'high_value', amountPaise: 6000000, note: 'load X' })));
    await assertFails(addDoc(collection(as('u1'), 'risk_signals'), sig('u2')));
    await assertFails(addDoc(collection(as('u1'), 'risk_signals'), sig('u1', { type: 'hacked' })));
    await assertFails(addDoc(collection(as('u1'), 'risk_signals'), sig('u1', { extra: 1 })));
    await assertSucceeds(getDocs(collection(asAdmin(), 'risk_signals')));
    await assertFails(getDocs(collection(as('u1'), 'risk_signals')));
  });
});

describe('scheduled bookings', () => {
  const inDays = (d) => Timestamp.fromMillis(Date.now() + d * 86400000);
  const inMinutes = (m) => Timestamp.fromMillis(Date.now() + m * 60000);
  const post = (at) => addDoc(collection(as('customer1'), 'loads'), { ...LOAD, scheduledAt: at });

  test('a load may be scheduled between 30 minutes and 90 days ahead', async () => {
    await assertSucceeds(post(inDays(3)));
    await assertSucceeds(post(inMinutes(90)));
    await assertFails(post(inMinutes(5)), 'too soon');
    await assertFails(post(inDays(120)), 'too far');
    await assertFails(post(Timestamp.fromDate(new Date('2020-01-01'))));
    await assertFails(addDoc(collection(as('customer1'), 'loads'), { ...LOAD, scheduledAt: 'tomorrow' }));
  });

  test('the booking must carry the load\'s scheduled time', async () => {
    const at = inDays(2);
    await seed(async (db) => {
      await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, scheduledAt: at });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1'), 'missing scheduledAt');
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { scheduledAt: inDays(5) }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { scheduledAt: at }));
  });

  describe('customer cancels an advance booking', () => {
    const seedMatched = (extra = {}, status = 'accepted') =>
      seed(async (db) => {
        const at = inDays(2);
        await setDoc(doc(db, 'loads', 'S1'), { ...LOAD, status: 'matched', driverId: 'driver1', bookingId: 'S1', scheduledAt: at });
        await setDoc(doc(db, 'bookings', 'S1'), { ...bookingFor('S1'), scheduledAt: at, status, timeline: {}, ...extra });
        await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', selectedRole: 'customer', cancelCount: 0 });
      });
    const cancel = (uid, { by = 'customer', charge = 0, loadCancelled = true, count = 1, closeLoad = true } = {}) => {
      const db = as(uid);
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'S1'), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation: { by, chargePaise: charge }, updatedAt: serverTimestamp() });
      if (closeLoad) b.update(doc(db, 'loads', 'S1'), { status: 'closed', cancelled: loadCancelled, cancelledAt: serverTimestamp() });
      b.set(doc(db, 'users', uid), { cancelCount: increment(count) }, { merge: true });
      return b.commit();
    };

    test('works before the driver starts, with a counted cancellation', async () => {
      await seedMatched();
      await assertSucceeds(cancel('customer1', { charge: 30000 }));
    });

    test('refused: not an advance booking, already started, wrong party, wrong charge shape', async () => {
      await seedMatched({}, 'driver_arriving');
      await assertFails(cancel('customer1'), 'driver already started');
      await seedMatched();
      await assertFails(cancel('customer2'), 'not the customer');
      await assertFails(cancel('customer1', { by: 'driver' }), 'by must be customer');
      await assertFails(cancel('customer1', { charge: -5 }));
      await assertFails(cancel('customer1', { closeLoad: false }), 'load must close in the same batch');
      await assertFails(cancel('customer1', { loadCancelled: false }), 'load must be marked cancelled');
      await assertFails(cancel('customer1', { count: 0 }), 'cancellation must be counted');
      await seed((db) => setDoc(doc(db, 'bookings', 'S1'), { ...bookingFor('S1'), status: 'accepted', timeline: {} }));
      await assertFails(cancel('customer1'), 'booking has no scheduled time');
    });
  });
});

describe('empty truck board', () => {
  const day = (n) => Timestamp.fromMillis(Date.now() + n * 86400000);
  const seedDriver = (verified = true) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verified });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
  const post = (over = {}) => ({
    driverId: 'driver1', driverName: 'Ramesh', vehicleId: 'v1', vehicleNumber: VEHICLE.number, vehicleType: VEHICLE.type, capacity: 10,
    fromCity: 'Pune', toCity: 'Delhi', availableDate: day(3), note: 'Open body', status: 'open', createdAt: serverTimestamp(), ...over,
  });

  test('a verified driver posts their own active vehicle within 30 days', async () => {
    await seedDriver();
    await assertSucceeds(addDoc(collection(as('driver1'), 'truck_posts'), post()));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ availableDate: day(45) })));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ fromCity: 'P' })));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ note: 'n'.repeat(201) })));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ vehicleNumber: 'FAKE000000' })));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ status: 'closed' })));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post({ extra: 1 })));
    await assertFails(addDoc(collection(as('driver2'), 'truck_posts'), post()), 'not their post');
    await assertFails(addDoc(collection(as('driver2'), 'truck_posts'), post({ driverId: 'driver2' })), 'not their vehicle');
  });

  test('an unverified or restricted driver cannot post', async () => {
    await seedDriver(false);
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post()));
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verified: true, riskTier: 'restricted' }));
    await assertFails(addDoc(collection(as('driver1'), 'truck_posts'), post()));
  });

  test('anyone signed in reads the board; only the owner closes a post', async () => {
    await seedDriver();
    await seed((db) => setDoc(doc(db, 'truck_posts', 'P1'), { ...post(), createdAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(as('customer1'), 'truck_posts', 'P1')));
    await assertFails(getDoc(doc(anon(), 'truck_posts', 'P1')));
    await assertFails(updateDoc(doc(as('customer1'), 'truck_posts', 'P1'), { status: 'closed', closedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'truck_posts', 'P1'), { fromCity: 'Agra' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'truck_posts', 'P1'), { status: 'closed', closedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(as('driver1'), 'truck_posts', 'P1')));
  });

  describe('requests', () => {
    const req = (uid, over = {}) => ({
      postId: 'P1', driverId: 'driver1', customerId: uid, customerName: 'Anil', pickup: 'Pune', drop: 'Delhi', weight: 6, vehicleType: '20ft',
      note: 'Fragile', status: 'pending', createdAt: serverTimestamp(), ...over,
    });
    const seedPost = (status = 'open') => seed((db) => setDoc(doc(db, 'truck_posts', 'P1'), { ...post({ status }), createdAt: Timestamp.now() }));

    test('one request per customer per open post, for the post\'s driver', async () => {
      await seedPost();
      await assertSucceeds(setDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), req('customer1')));
      await assertFails(setDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), req('customer1')), 'a second request is an update');
      await assertFails(setDoc(doc(as('customer2'), 'truck_requests', 'P1_customer1'), req('customer2')), 'id must match the caller');
      await assertFails(setDoc(doc(as('customer2'), 'truck_requests', 'P1_customer2'), req('customer2', { driverId: 'driver2' })), 'wrong driver for the post');
      await assertFails(setDoc(doc(as('customer2'), 'truck_requests', 'P1_customer2'), req('customer2', { weight: 500 })));
      await assertFails(setDoc(doc(as('customer2'), 'truck_requests', 'P1_customer2'), req('customer2', { pickup: 'P' })));
      await assertFails(setDoc(doc(as('customer2'), 'truck_requests', 'P1_customer2'), req('customer2', { status: 'accepted' })));
      await assertFails(setDoc(doc(as('driver1'), 'truck_requests', 'P1_driver1'), req('driver1')), 'own post');
    });

    test('a closed post takes no requests', async () => {
      await seedPost('closed');
      await assertFails(setDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), req('customer1')));
    });

    test('the driver answers once; the customer can withdraw; the parties read it', async () => {
      await seedPost();
      await seed((db) => setDoc(doc(db, 'truck_requests', 'P1_customer1'), { ...req('customer1'), createdAt: Timestamp.now() }));
      await assertFails(updateDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), { status: 'accepted' }), 'customer cannot accept');
      await assertFails(updateDoc(doc(as('driver2'), 'truck_requests', 'P1_customer1'), { status: 'accepted', answeredAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('driver1'), 'truck_requests', 'P1_customer1'), { status: 'accepted', weight: 1, answeredAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('driver1'), 'truck_requests', 'P1_customer1'), { status: 'withdrawn', answeredAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(doc(as('driver1'), 'truck_requests', 'P1_customer1'), { status: 'accepted', answeredAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('driver1'), 'truck_requests', 'P1_customer1'), { status: 'declined', answeredAt: serverTimestamp() }), 'already answered');
      await assertFails(updateDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), { status: 'withdrawn' }), 'already answered');
      await assertSucceeds(getDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1')));
      await assertSucceeds(getDoc(doc(as('driver1'), 'truck_requests', 'P1_customer1')));
      await assertFails(getDoc(doc(as('customer2'), 'truck_requests', 'P1_customer1')));
      await seed((db) => setDoc(doc(db, 'truck_requests', 'P1_customer1'), { ...req('customer1'), createdAt: Timestamp.now() }));
      await assertSucceeds(updateDoc(doc(as('customer1'), 'truck_requests', 'P1_customer1'), { status: 'withdrawn' }));
    });

    test('a load may name the invited driver', async () => {
      const load = (over) => addDoc(collection(as('customer1'), 'loads'), { ...LOAD, ...over });
      await assertSucceeds(load({ invitedDriverId: 'driver1' }));
      await assertFails(load({ invitedDriverId: '' }));
      await assertFails(load({ invitedDriverId: 7 }));
    });
  });
});

describe('fleet owners', () => {
  const asPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
  const DRIVER_PHONE = '+919876543210';
  const invite = (over = {}) => ({ ownerId: 'owner1', ownerName: 'Sunil', phone: DRIVER_PHONE, status: 'pending', createdAt: serverTimestamp(), ...over });
  const seedUsers = () =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', 'owner1'), { role: 'fleet', selectedRole: 'fleet' });
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verified: true });
      await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', selectedRole: 'customer' });
    });

  test('fleet is a role that is set once like the others', async () => {
    await assertSucceeds(setDoc(doc(as('f1'), 'users', 'f1'), { role: 'fleet', selectedRole: 'fleet' }));
    await assertFails(setDoc(doc(as('f2'), 'users', 'f2'), { role: 'owner' }));
  });

  test('only a fleet owner invites, for a valid phone, under their own id', async () => {
    await seedUsers();
    const id = 'owner1_919876543210';
    await assertSucceeds(setDoc(doc(as('owner1'), 'fleet_invites', id), invite()));
    await assertFails(setDoc(doc(as('customer1'), 'fleet_invites', 'customer1_919876543210'), invite({ ownerId: 'customer1' })));
    await assertFails(setDoc(doc(as('owner1'), 'fleet_invites', 'owner1_919876543211'), invite()), 'id must match the phone');
    await assertFails(setDoc(doc(as('owner1'), 'fleet_invites', 'owner1_12345'), invite({ phone: '12345' })));
    await assertFails(setDoc(doc(as('owner1'), 'fleet_invites', id), invite({ status: 'accepted' })));
  });

  test('the invited phone accepts or declines once; the owner cancels; strangers read nothing', async () => {
    await seedUsers();
    const id = 'owner1_919876543210';
    await seed((db) => setDoc(doc(db, 'fleet_invites', id), invite({ createdAt: Timestamp.now() })));
    await assertFails(getDoc(doc(as('customer1'), 'fleet_invites', id)));
    await assertSucceeds(getDoc(doc(asPhone('driver1', DRIVER_PHONE), 'fleet_invites', id)));
    await assertSucceeds(getDoc(doc(as('owner1'), 'fleet_invites', id)));
    await assertFails(updateDoc(doc(asPhone('driver2', '+919000000000'), 'fleet_invites', id), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('owner1'), 'fleet_invites', id), { status: 'accepted', answeredAt: serverTimestamp() }), 'owner cannot accept for the driver');
    await assertSucceeds(updateDoc(doc(asPhone('driver1', DRIVER_PHONE), 'fleet_invites', id), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asPhone('driver1', DRIVER_PHONE), 'fleet_invites', id), { status: 'declined', answeredAt: serverTimestamp() }), 'already answered');
    await assertFails(updateDoc(doc(as('owner1'), 'fleet_invites', id), { status: 'cancelled', answeredAt: serverTimestamp() }), 'already answered');
  });

  const member = (over = {}) => ({
    ownerId: 'owner1', ownerName: 'Sunil', driverId: 'driver1', driverName: 'Ramesh', driverPhone: DRIVER_PHONE, active: true, createdAt: serverTimestamp(), ...over,
  });

  test('a driver joins only after the owner\'s invite to their phone is accepted', async () => {
    await seedUsers();
    const inviteId = 'owner1_919876543210';
    await seed((db) => setDoc(doc(db, 'fleet_invites', inviteId), invite({ createdAt: Timestamp.now() })));
    const d = () => asPhone('driver1', DRIVER_PHONE);
    // still pending: no membership
    await assertFails(setDoc(doc(d(), 'fleet_members', 'owner1_driver1'), member()));
    await seed((db) => updateDoc(doc(db, 'fleet_invites', inviteId), { status: 'accepted' }));
    await assertFails(setDoc(doc(d(), 'fleet_members', 'owner1_driver1'), member({ active: false })));
    await assertFails(setDoc(doc(d(), 'fleet_members', 'owner1_driver1'), member({ driverPhone: '+919000000000' })));
    await assertFails(setDoc(doc(asPhone('customer1', DRIVER_PHONE), 'fleet_members', 'owner1_customer1'), member({ driverId: 'customer1' })), 'customers cannot join');
    await assertSucceeds(setDoc(doc(d(), 'fleet_members', 'owner1_driver1'), member()));
    await assertSucceeds(getDoc(doc(as('owner1'), 'fleet_members', 'owner1_driver1')));
    await assertFails(getDoc(doc(as('customer1'), 'fleet_members', 'owner1_driver1')));
  });

  test('either side ends a membership; nothing else changes', async () => {
    await seedUsers();
    await seed((db) => setDoc(doc(db, 'fleet_members', 'owner1_driver1'), member({ createdAt: Timestamp.now() })));
    await assertFails(updateDoc(doc(as('driver1'), 'fleet_members', 'owner1_driver1'), { driverName: 'X' }));
    await assertFails(updateDoc(doc(as('customer1'), 'fleet_members', 'owner1_driver1'), { active: false, endedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'fleet_members', 'owner1_driver1'), { active: false, endedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('owner1'), 'fleet_members', 'owner1_driver1'), { active: true }), 'no re-activation');
  });

  describe('vehicles and bookings', () => {
    const seedFleet = () =>
      seed(async (db) => {
        await setDoc(doc(db, 'users', 'owner1'), { role: 'fleet', selectedRole: 'fleet' });
        await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verified: true });
        await setDoc(doc(db, 'fleet_members', 'owner1_driver1'), member({ createdAt: Timestamp.now() }));
        await setDoc(doc(db, 'fleet_members', 'owner1_driver2'), member({ driverId: 'driver2', createdAt: Timestamp.now(), active: false }));
        await setDoc(doc(db, 'vehicles', 'fv1'), { ...VEHICLE, ownerId: 'owner1' });
        await setDoc(doc(db, 'vehicle_numbers', VEHICLE.number), { ownerId: 'owner1', vehicleId: 'fv1' });
        await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, status: 'open' });
      });

    test('the owner assigns a vehicle to an active member only', async () => {
      await seedFleet();
      const ref = () => doc(as('owner1'), 'vehicles', 'fv1');
      await assertSucceeds(updateDoc(ref(), { assignedDriverId: 'driver1' }));
      await assertFails(updateDoc(ref(), { assignedDriverId: 'driver2' }), 'ended member');
      await assertFails(updateDoc(ref(), { assignedDriverId: 'stranger' }));
      await assertSucceeds(updateDoc(ref(), { assignedDriverId: deleteField() }));
    });

    test('the assigned driver flips availability but edits nothing else', async () => {
      await seedFleet();
      await seed((db) => updateDoc(doc(db, 'vehicles', 'fv1'), { assignedDriverId: 'driver1' }));
      await assertSucceeds(updateDoc(doc(as('driver1'), 'vehicles', 'fv1'), { availability: 'on_trip' }));
      await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'fv1'), { availability: 'maintenance' }));
      await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'fv1'), { capacity: 99 }));
      await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'fv1'), { assignedDriverId: 'driver1x' }));
      await assertFails(updateDoc(doc(as('driver3'), 'vehicles', 'fv1'), { availability: 'on_trip' }));
    });

    test('the assigned driver takes a load with the fleet vehicle; the booking names the owner', async () => {
      await seedFleet();
      await seed((db) => updateDoc(doc(db, 'vehicles', 'fv1'), { assignedDriverId: 'driver1' }));
      const over = { vehicleId: 'fv1' };
      await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', over), 'owner id missing');
      await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { ...over, fleetOwnerId: 'someoneElse' }));
      await assertFails(acceptBatch(as('driver2'), 'L1', 'driver2', { ...over, fleetOwnerId: 'owner1' }), 'not assigned');
      await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { ...over, fleetOwnerId: 'owner1' }));
      await assertSucceeds(getDoc(doc(as('owner1'), 'bookings', 'L1')));
      await assertFails(getDoc(doc(as('driver3'), 'bookings', 'L1')));
    });

    test('the owner drives their own vehicle without a fleetOwnerId', async () => {
      await seedFleet();
      await assertFails(acceptBatch(as('owner1'), 'L1', 'owner1', { vehicleId: 'fv1', fleetOwnerId: 'owner1' }));
      await assertSucceeds(acceptBatch(as('owner1'), 'L1', 'owner1', { vehicleId: 'fv1' }));
    });
  });
});

describe('business accounts', () => {
  const asPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
  const PHONE = '+919876543210';
  const invite = (over = {}) => ({ ownerId: 'owner1', ownerName: 'Acme Ltd', phone: PHONE, status: 'pending', createdAt: serverTimestamp(), ...over });
  const member = (over = {}) => ({
    ownerId: 'owner1', ownerName: 'Acme Ltd', memberId: 'booker1', memberName: 'Bina', memberPhone: PHONE, role: 'booker', active: true, createdAt: serverTimestamp(), ...over,
  });
  const seedUsers = () =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', 'owner1'), { role: 'customer', selectedRole: 'customer' });
      await setDoc(doc(db, 'users', 'booker1'), { role: 'customer', selectedRole: 'customer' });
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' });
    });

  test('a customer owner invites; drivers and wrong ids cannot', async () => {
    await seedUsers();
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919876543210'), invite()));
    await assertFails(setDoc(doc(as('driver1'), 'business_invites', 'driver1_919876543210'), invite({ ownerId: 'driver1' })));
    await assertFails(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919000000000'), invite()));
    await assertFails(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919876543210'), invite({ ownerName: 'x'.repeat(101) })));
  });

  test('the invited phone answers once; the owner may cancel a pending invite', async () => {
    await seedUsers();
    const id = 'owner1_919876543210';
    await seed((db) => setDoc(doc(db, 'business_invites', id), invite({ createdAt: Timestamp.now() })));
    await assertFails(getDoc(doc(as('customer9'), 'business_invites', id)));
    await assertFails(updateDoc(doc(as('owner1'), 'business_invites', id), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asPhone('booker1', PHONE), 'business_invites', id), { status: 'accepted', answeredAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asPhone('booker1', PHONE), 'business_invites', id), { status: 'declined', answeredAt: serverTimestamp() }));
  });

  test('membership needs an accepted invite and a customer account', async () => {
    await seedUsers();
    const id = 'owner1_919876543210';
    await seed((db) => setDoc(doc(db, 'business_invites', id), invite({ createdAt: Timestamp.now() })));
    const b = () => asPhone('booker1', PHONE);
    await assertFails(setDoc(doc(b(), 'business_members', 'owner1_booker1'), member()), 'invite still pending');
    await seed((db) => updateDoc(doc(db, 'business_invites', id), { status: 'accepted' }));
    await assertFails(setDoc(doc(b(), 'business_members', 'owner1_booker1'), member({ role: 'owner' })));
    await assertFails(setDoc(doc(b(), 'business_members', 'owner1_booker1'), member({ memberPhone: '+919000000000' })));
    await assertFails(setDoc(doc(asPhone('driver1', PHONE), 'business_members', 'owner1_driver1'), member({ memberId: 'driver1' })), 'drivers cannot');
    await assertSucceeds(setDoc(doc(b(), 'business_members', 'owner1_booker1'), member()));
    await assertSucceeds(getDoc(doc(as('owner1'), 'business_members', 'owner1_booker1')));
    await assertFails(getDoc(doc(as('customer9'), 'business_members', 'owner1_booker1')));
    await assertSucceeds(updateDoc(doc(as('owner1'), 'business_members', 'owner1_booker1'), { active: false, endedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('owner1'), 'business_members', 'owner1_booker1'), { active: true }));
  });

  describe('loads, bookings and statements', () => {
    const seedTeam = () =>
      seed(async (db) => {
        await setDoc(doc(db, 'users', 'owner1'), { role: 'customer', selectedRole: 'customer' });
        await setDoc(doc(db, 'business_members', 'owner1_booker1'), member({ createdAt: Timestamp.now() }));
        await setDoc(doc(db, 'business_members', 'owner1_old'), member({ memberId: 'old', createdAt: Timestamp.now(), active: false }));
        await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
      });
    const postLoad = (uid, over) => addDoc(collection(as(uid), 'loads'), { ...LOAD, shipperId: uid, createdAt: serverTimestamp(), ...over });

    test('only the owner or an active booker may tag a load with the company; cost centre is length-limited', async () => {
      await seedTeam();
      await assertSucceeds(postLoad('booker1', { businessId: 'owner1', costCenter: 'Plant 2' }));
      await assertSucceeds(postLoad('owner1', { businessId: 'owner1' }));
      await assertFails(postLoad('old', { businessId: 'owner1' }), 'ended member');
      await assertFails(postLoad('customer9', { businessId: 'owner1' }), 'stranger');
      await assertFails(postLoad('booker1', { businessId: 'owner1', costCenter: 'x'.repeat(31) }));
      await assertFails(postLoad('booker1', { businessId: 'owner1', costCenter: '' }));
      await assertSucceeds(postLoad('customer9', { costCenter: 'mine' }));
    });

    test('the owner reads the company\'s loads and bookings', async () => {
      await seedTeam();
      await seed(async (db) => {
        await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, shipperId: 'booker1', status: 'matched', driverId: 'driver1', businessId: 'owner1', costCenter: 'P2' });
        await setDoc(doc(db, 'bookings', 'L1'), { ...bookingFor('L1', { customerId: 'booker1' }), timeline: {}, businessId: 'owner1', costCenter: 'P2' });
      });
      await assertSucceeds(getDocs(query(collection(as('owner1'), 'bookings'), where('businessId', '==', 'owner1'))));
      await assertSucceeds(getDoc(doc(as('owner1'), 'loads', 'L1')));
      await assertFails(getDoc(doc(as('customer9'), 'bookings', 'L1')));
    });

    test('the booking must copy the load\'s company id and cost centre', async () => {
      await seedTeam();
      await seed((db) => setDoc(doc(db, 'loads', 'L1'), { ...LOAD, shipperId: 'booker1', businessId: 'owner1', costCenter: 'P2' }));
      const over = { customerId: 'booker1' };
      await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', over), 'tags missing');
      await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { ...over, businessId: 'owner1', costCenter: 'other' }));
      await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { ...over, businessId: 'owner1', costCenter: 'P2' }));
    });

    test('statement records: the owner writes their own month, nobody else reads it', async () => {
      const st = (over = {}) => ({ ownerId: 'owner1', month: '2026-09', trips: 3, totalPaise: 425050, byCostCenter: { 'Plant 2': 350050, '-': 75000 }, createdAt: serverTimestamp(), ...over });
      await assertSucceeds(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09'), st()));
      await assertSucceeds(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09'), st({ trips: 4 })), 'replace');
      await assertFails(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-10'), st()), 'id must match month');
      await assertFails(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-13'), st({ month: '2026-13' })));
      await assertFails(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09'), st({ totalPaise: 10.5 })));
      await assertFails(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09'), st({ totalPaise: -1 })));
      await assertFails(setDoc(doc(as('owner2'), 'business_statements', 'owner1_2026-09'), st()));
      await assertSucceeds(getDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09')));
      await assertFails(getDoc(doc(as('owner2'), 'business_statements', 'owner1_2026-09')));
      await assertFails(deleteDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09')));
    });
  });
});

describe('admin verification', () => {
  const seedDriver = () => seed((db) => setDoc(doc(db, 'users', 'd1'), { driverName: 'R', verified: false, verificationStatus: 'pending' }));

  test('admin reads drivers and approves/rejects; others cannot', async () => {
    await seedDriver();
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'users'), where('verificationStatus', '==', 'pending'))));
    await assertFails(getDocs(query(collection(as('u2'), 'users'), where('verificationStatus', '==', 'pending'))));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'approved', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: false, verificationStatus: 'rejected', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('u2'), 'users', 'd1'), { verified: true, verificationStatus: 'approved' }));
  });

  test('admin can only touch verification fields, consistently', async () => {
    await seedDriver();
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { driverName: 'X' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'rejected' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'bogus' }));
  });
});

describe('vehicles', () => {
  test('owner creates/updates; any signed-in user reads', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1'));
    await assertSucceeds(getDoc(doc(as('customer1'), 'vehicles', 'v1')));
    await assertFails(getDoc(doc(anon(), 'vehicles', 'v1')));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { status: 'inactive' }));
    await assertFails(updateDoc(doc(as('driver2'), 'vehicles', 'v1'), { status: 'active' }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { ownerId: 'driver2' }));
    await assertFails(deleteDoc(doc(as('driver2'), 'vehicles', 'v1')));
  });

  test('rcImageUrl must point at Firebase Storage', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1', {
      ...VEHICLE,
      rcImageUrl: 'https://firebasestorage.googleapis.com/v0/b/loadgo-defc2.appspot.com/o/vehicles%2Fdriver1%2Fv1%2Frc.jpg',
    }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { rcImageUrl: 'https://evil.example.com/x.jpg' }));
  });

  test('cannot create for someone else or with invalid data', async () => {
    await assertFails(addVehicle(as('driver2'), 'v9'));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, status: 'flying' }));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, capacity: 0 }));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, availability: 'suspended' }));
    await assertFails(setDoc(doc(as('driver1'), 'vehicles', 'v9'), VEHICLE), 'needs a number reservation');
  });

  test('the same number cannot be registered twice, even by another account', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1'));
    await assertFails(addVehicle(as('driver2'), 'v2', { ...VEHICLE, ownerId: 'driver2' }));
    await assertFails(addVehicle(as('driver1'), 'v3'));
    // Reservation can't be stolen or pointed at someone else's vehicle.
    await assertFails(setDoc(doc(as('driver2'), 'vehicle_numbers', VEHICLE.number), { ownerId: 'driver2', vehicleId: 'v1' }));
    await assertFails(deleteDoc(doc(as('driver2'), 'vehicle_numbers', VEHICLE.number)));
  });

  test('renumbering moves the reservation; deleting frees it', async () => {
    await addVehicle(as('driver1'), 'v1');
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { number: 'DL01ZZ0001' }), 'new number must be reserved');
    const b = writeBatch(db);
    b.set(doc(db, 'vehicle_numbers', 'DL01ZZ0001'), { ownerId: 'driver1', vehicleId: 'v1' });
    b.delete(doc(db, 'vehicle_numbers', VEHICLE.number));
    b.update(doc(db, 'vehicles', 'v1'), { number: 'DL01ZZ0001' });
    await assertSucceeds(b.commit());
    await assertSucceeds(addVehicle(as('driver2'), 'v2', { ...VEHICLE, ownerId: 'driver2' }));
    const d = writeBatch(db);
    d.delete(doc(db, 'vehicles', 'v1'));
    d.delete(doc(db, 'vehicle_numbers', 'DL01ZZ0001'));
    await assertSucceeds(d.commit());
  });

  test('documents, service date and availability', async () => {
    await addVehicle(as('driver1'), 'v1');
    const db = as('driver1');
    await assertSucceeds(updateDoc(doc(db, 'vehicles', 'v1'), {
      docs: { insurance: { number: 'POL1', expiry: Timestamp.fromDate(new Date('2027-01-01')) } },
      nextServiceDate: Timestamp.fromDate(new Date('2026-11-01')),
    }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { docs: { passport: { number: 'X' } } }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { nextServiceDate: 'soon' }));
    await assertSucceeds(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'maintenance' }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'suspended' }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'parked' }));
    await assertFails(updateDoc(doc(as('driver2'), 'vehicles', 'v1'), { availability: 'available' }));
  });

  test('only admins suspend or lift a suspension', async () => {
    await addVehicle(as('driver1'), 'v1');
    await assertSucceeds(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { availability: 'suspended' }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { availability: 'available' }));
    await assertFails(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { capacity: 50 }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { availability: 'available' }));
  });
});

describe('loads', () => {
  test('shipper posts an open load; drivers read open loads', async () => {
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertSucceeds(getDocs(query(collection(as('driver1'), 'loads'), where('status', '==', 'open'))));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'loads'), where('shipperId', '==', 'customer1'))));
    await assertFails(getDocs(collection(as('driver1'), 'loads')));
    await assertFails(getDoc(doc(anon(), 'loads', 'L1')));
  });

  test('load create is validated', async () => {
    await assertFails(setDoc(doc(as('customer2'), 'loads', 'L1'), LOAD));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, status: 'matched' }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, weight: -1 }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, driverId: 'driver1' }));
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, budget: null }));
  });

  test('shipper edits/cancels only while open; drivers cannot edit', async () => {
    await seedOpenLoad();
    await assertSucceeds(updateDoc(doc(as('customer1'), 'loads', 'L1'), { notes: 'fragile' }));
    await assertFails(updateDoc(doc(as('driver1'), 'loads', 'L1'), { budget: 1 }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'matched' }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { cancelled: true }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed' }));
    // A cancellation must bump cancelCount in the same batch.
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed', cancelled: true, cancelledAt: serverTimestamp() }));
    const cdb = as('customer1');
    const b = writeBatch(cdb);
    b.update(doc(cdb, 'loads', 'L1'), { status: 'closed', cancelled: true, cancelledAt: serverTimestamp() });
    b.set(doc(cdb, 'users', 'customer1'), { cancelCount: increment(1) }, { merge: true });
    await assertSucceeds(b.commit());
    // Once cancelled it cannot be reopened.
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'open', cancelled: false }));
  });

  test('shipper cannot cancel a matched load', async () => {
    await seedOpenLoad();
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed', cancelled: true }));
  });
});

describe('accepting a load', () => {
  test('driver accepts with booking + load update together', async () => {
    await seedOpenLoad();
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });

  test('matching without a booking, or a booking without matching, fails', async () => {
    await seedOpenLoad();
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'L1' }));
    await assertFails(setDoc(doc(db, 'bookings', 'L1'), bookingFor('L1')));
  });

  test('cannot accept with a tampered budget or someone else\'s vehicle', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { budget: 99999 }));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { vehicleId: 'v2' }));
  });

  test('the booking must repeat the load\'s type, helpers and rental hours', async () => {
    await seed((db) => setDoc(doc(db, 'loads', 'L1'), { ...LOAD, bookingType: 'rental', rentalHours: 8, helpers: 2 }));
    await seed((db) => setDoc(doc(db, 'vehicles', 'v1'), VEHICLE));
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { bookingType: 'rental', rentalHours: 8, helpers: 0 }));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { bookingType: 'rental', rentalHours: 4, helpers: 2 }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { bookingType: 'rental', rentalHours: 8, helpers: 2 }));
  });

  test('cannot accept own load or an already matched load', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('customer1'), 'L1', 'customer1', { customerId: 'customer1' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver2'), 'L1', 'driver2', { vehicleId: 'v2' }));
    // Matched load is hidden from other drivers but visible to the parties.
    await assertFails(getDoc(doc(as('driver2'), 'loads', 'L1')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'loads', 'L1')));
  });
});

describe('bookings', () => {
  test('only the driver and customer can read', async () => {
    await seedBooking();
    await assertSucceeds(getDoc(doc(as('driver1'), 'bookings', 'L1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'bookings', 'L1')));
    await assertSucceeds(getDocs(query(collection(as('driver1'), 'bookings'), where('driverId', '==', 'driver1'))));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'bookings'), where('customerId', '==', 'customer1'))));
    await assertFails(getDoc(doc(as('driver2'), 'bookings', 'L1')));
    await assertFails(getDocs(collection(as('driver2'), 'bookings')));
  });

  test('driver advances one step at a time; nobody else can', async () => {
    await seedBooking();
    const step = (db, status, extra = {}) =>
      updateDoc(doc(db, 'bookings', 'L1'), { status, [`timeline.${status}`]: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
    await assertFails(step(as('driver1'), 'delivered'));
    await assertFails(step(as('driver1'), 'loading'), 'no skipping');
    await assertFails(step(as('customer1'), 'driver_arriving'));
    await assertFails(step(as('driver2'), 'driver_arriving'));
    await assertSucceeds(step(as('driver1'), 'driver_arriving'));
    await assertFails(step(as('driver1'), 'accepted'));
    await assertSucceeds(step(as('driver1'), 'loading'));
    await seed((db) => setDoc(doc(db, 'bookings', 'L1', 'secrets', 'otp'), OTPS));
    await assertFails(step(as('driver1'), 'picked_up'), 'needs OTP');
    await assertSucceeds(step(as('driver1'), 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP }));
    await assertSucceeds(step(as('driver1'), 'in_transit'));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { budget: 1 }));
    await assertFails(deleteDoc(doc(as('driver1'), 'bookings', 'L1')));
  });

  test('driver shares live location only while in transit', async () => {
    const loc = () => ({ lastKnownLocation: new GeoPoint(28.6, 77.2), locationUpdatedAt: serverTimestamp() });
    await seedBooking('picked_up');
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'in_transit' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('driver2'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { ...loc(), budget: 1 }));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { lastKnownLocation: 'x', locationUpdatedAt: serverTimestamp() }));
  });

  test('delivering closes the load; closing early fails', async () => {
    await seedBooking('unloading');
    await seed((s) => setDoc(doc(s, 'bookings', 'L1', 'secrets', 'otp'), OTPS));
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() }));
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'L1'), {
      status: 'delivered', 'timeline.delivered': serverTimestamp(), updatedAt: serverTimestamp(),
      deliveryOtp: OTPS.deliveryOtp, deliveryProof: DELIVERY,
    });
    b.update(doc(db, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'open' }));
  });
});

describe('ratings', () => {
  const rating = (rater, rated, extra = {}) => ({ bookingId: 'L1', raterId: rater, ratedId: rated, stars: 5, comment: 'Great', createdAt: serverTimestamp(), ...extra });

  test('parties rate each other once after delivery', async () => {
    await seedBooking('delivered');
    await assertSucceeds(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1')));
    await assertSucceeds(setDoc(doc(as('driver1'), 'ratings', 'L1_driver1'), rating('driver1', 'customer1', { stars: 4 })));
    // No second rating / edits.
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 1 })));
    await assertFails(deleteDoc(doc(as('customer1'), 'ratings', 'L1_customer1')));
    await assertSucceeds(getDocs(query(collection(as('driver2'), 'ratings'), where('ratedId', '==', 'driver1'))));
  });

  test('rejects early, outsider, mismatched or invalid ratings', async () => {
    await seedBooking('in_transit');
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1')));
    await seedBooking('delivered');
    await assertFails(setDoc(doc(as('driver2'), 'ratings', 'L1_driver2'), rating('driver2', 'driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'customer1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'other_id'), rating('customer1', 'driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 6 })));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 4.5 })));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { comment: 'x'.repeat(501) })));
  });
});

describe('notifications', () => {
  const notif = (userId, extra = {}) => ({ userId, type: 'status_changed', message: 'Delhi → Mumbai', relatedId: 'L1', status: 'picked_up', read: false, createdAt: serverTimestamp(), ...extra });

  test('a booking party notifies the other party', async () => {
    await seedBooking();
    await assertSucceeds(addDoc(collection(as('driver1'), 'notifications'), notif('customer1')));
    await assertSucceeds(addDoc(collection(as('customer1'), 'notifications'), notif('driver1', { type: 'rating_received', status: null })));
  });

  test('outsiders, self-notifications and bad data are rejected', async () => {
    await seedBooking();
    await assertFails(addDoc(collection(as('driver2'), 'notifications'), notif('customer1')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('driver2')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('driver1')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { read: true })));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { type: 'spam' })));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { relatedId: 'nope' })));
  });

  test('only the recipient reads and marks read', async () => {
    await seedBooking();
    await seed((db) => setDoc(doc(db, 'notifications', 'n1'), notif('customer1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'notifications', 'n1')));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'notifications'), where('userId', '==', 'customer1'))));
    await assertFails(getDoc(doc(as('driver1'), 'notifications', 'n1')));
    await assertFails(updateDoc(doc(as('customer1'), 'notifications', 'n1'), { message: 'changed' }));
    await assertFails(updateDoc(doc(as('driver1'), 'notifications', 'n1'), { read: true }));
    await assertSucceeds(updateDoc(doc(as('customer1'), 'notifications', 'n1'), { read: true }));
  });

  test('accept transaction can include the customer notification', async () => {
    await seedOpenLoad();
    const db = as('driver1');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'L1'), bookingFor('L1'));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'L1', matchedAt: serverTimestamp() });
    b.set(doc(db, 'notifications', 'n2'), notif('customer1', { type: 'load_accepted', status: null }));
    await assertSucceeds(b.commit());
  });
});

describe('driver cancels before pickup', () => {
  /** Same writes as BookingService.cancelByDriver. */
  function cancelBatch(db, bookingId = 'L1', cancellation = { by: 'driver', chargePaise: 0 }) {
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', bookingId), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation, updatedAt: serverTimestamp() });
    b.update(doc(db, 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField(), matchedAt: deleteField(), reopenedAt: serverTimestamp() });
    b.set(doc(db, 'users', 'driver1'), { cancelCount: increment(1) }, { merge: true });
    return b.commit();
  }

  test('cancel reopens the load and another driver can accept with a new booking', async () => {
    await seedBooking();
    await assertSucceeds(cancelBatch(as('driver1')));
    await assertSucceeds(getDoc(doc(as('driver2'), 'loads', 'L1')));
    // New booking id for the second driver.
    const db = as('driver2');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B2'), bookingFor('L1', { driverId: 'driver2', vehicleId: 'v2' }));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver2', bookingId: 'B2', matchedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
    // The old driver can no longer touch the load or the old booking.
    await assertFails(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { status: 'picked_up' }));
  });

  test('the recorded cancellation charge must be a sane driver record', async () => {
    await seedBooking();
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'customer', chargePaise: 0 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: -1 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 12.5 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 100, paid: true }));
    await assertSucceeds(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 5000 }));
  });

  test('cannot cancel after pickup, as someone else, or without reopening', async () => {
    await seedBooking();
    await assertFails(cancelBatch(as('driver2')));
    await assertFails(cancelBatch(as('customer1')));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { status: 'cancelled', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField() }));
    await seedBooking('picked_up');
    await assertFails(cancelBatch(as('driver1')));
  });

  test('cannot point a load at a booking for a different load', async () => {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'loads', 'L2'), LOAD));
    const db = as('driver1');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B9'), bookingFor('L2'));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'B9' });
    await assertFails(b.commit());
  });
});

describe('config', () => {
  const TYPES = { types: [{ id: 'Mini', name: 'Mini truck', minTons: 0.75, maxTons: 2, category: 'lcv', active: true }] };

  test('signed-in users read config, anonymous users cannot', async () => {
    await seed((db) => setDoc(doc(db, 'config', 'vehicle_types'), TYPES));
    await assertSucceeds(getDoc(doc(as('driver1'), 'config', 'vehicle_types')));
    await assertFails(getDoc(doc(anon(), 'config', 'vehicle_types')));
  });

  test('only admins write config, with a valid shape', async () => {
    await assertFails(setDoc(doc(as('driver1'), 'config', 'vehicle_types'), TYPES));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), TYPES));
    await assertFails(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), { types: [] }));
    await assertFails(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), { ...TYPES, extra: 1 }));
    await assertFails(deleteDoc(doc(asAdmin(), 'config', 'vehicle_types')));
  });
});

describe('vehicle availability and bookings', () => {
  test('a vehicle in maintenance, suspended or on another trip cannot be booked', async () => {
    await seedOpenLoad();
    for (const availability of ['maintenance', 'suspended', 'on_trip']) {
      await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { availability }));
      await assertFails(acceptBatch(as('driver1'), 'L1'), availability);
    }
    await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'available', status: 'inactive' }));
    await assertFails(acceptBatch(as('driver1'), 'L1'), 'inactive');
    await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { status: 'active' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });
});

describe('fare estimate', () => {
  const EST = { total: 412000, tripFare: 380000, distanceKm: 120, platformFee: 19000, gst: 13000, distanceSource: 'cities' };

  test('loads may carry a well-formed estimate in integer paise', async () => {
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, estimate: EST }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L2'), { ...LOAD, estimate: { ...EST, total: 4120.5 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L3'), { ...LOAD, estimate: { ...EST, tripFare: 500000 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L4'), { ...LOAD, estimate: { ...EST, distanceKm: 99999 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L5'), { ...LOAD, estimate: 'cheap' }));
  });

  test('the booking must copy the load estimate total', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, estimate: EST });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { fareEstimate: 1 }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { fareEstimate: EST.total }));
  });
});

describe('load posting upgrade', () => {
  test('extra stops: at most 2 per side, non-empty strings', async () => {
    const db = as('customer1');
    await assertSucceeds(setDoc(doc(db, 'loads', 'A'), { ...LOAD, extraPickups: ['Gurugram', 'Noida'], extraDrops: ['Ajmer'] }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, extraPickups: ['a1', 'b2', 'c3'] }));
    await assertFails(setDoc(doc(db, 'loads', 'C'), { ...LOAD, extraDrops: [''] }));
    await assertFails(setDoc(doc(db, 'loads', 'D'), { ...LOAD, extraDrops: 'Ajmer' }));
  });

  test('pickup slot must be a known value', async () => {
    const db = as('customer1');
    await assertSucceeds(setDoc(doc(db, 'loads', 'A'), { ...LOAD, pickupSlot: 'evening' }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, pickupSlot: 'midnight' }));
  });

  test('prohibited goods are refused even if the app check is bypassed', async () => {
    const db = as('customer1');
    await assertFails(setDoc(doc(db, 'loads', 'A'), { ...LOAD, notes: 'Two boxes of Explosives' }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, notes: 'ganja' }));
    await assertFails(setDoc(doc(db, 'loads', 'C'), { ...LOAD, cargoType: 'Fireworks' }));
    await assertSucceeds(setDoc(doc(db, 'loads', 'D'), { ...LOAD, notes: 'gunny bags, handle with care' }));
    await seed((s) => setDoc(doc(s, 'loads', 'E'), LOAD));
    await assertFails(updateDoc(doc(db, 'loads', 'E'), { notes: 'actually ammunition' }));
  });

  test('bookings must copy the stops of the load', async () => {
    await seed(async (s) => {
      await setDoc(doc(s, 'loads', 'L1'), { ...LOAD, extraDrops: ['Ajmer'] });
      await setDoc(doc(s, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { extraDrops: ['Ajmer'] }));
  });

  test('saved places: owner only, validated', async () => {
    const mine = doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p1');
    await assertSucceeds(setDoc(mine, { label: 'warehouse', name: 'Bhiwandi', address: 'Thane' }));
    await assertSucceeds(getDoc(mine));
    await assertFails(getDoc(doc(as('driver1'), 'users', 'customer1', 'saved_places', 'p1')));
    await assertFails(setDoc(doc(as('driver1'), 'users', 'customer1', 'saved_places', 'p2'), { label: 'home', name: 'x', address: 'yy' }));
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p3'), { label: 'castle', name: 'x', address: 'yy' }));
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p4'), { label: 'home', name: 'x', address: 'yy', extra: 1 }));
    await assertSucceeds(deleteDoc(mine));
  });
});

describe('offers', () => {
  const OFFER = {
    loadId: 'L1', driverId: 'driver1', customerId: 'customer1', vehicleId: 'v1', vehicleNumber: VEHICLE.number,
    vehicleType: '20ft', driverName: 'Ramesh', pricePaise: 2400000, originalPaise: 2400000, status: 'pending',
  };
  const ref = (db, id = 'L1_driver1') => doc(db, 'offers', id);

  async function seedOffer(overrides = {}) {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'offers', 'L1_driver1'), { ...OFFER, ...overrides }));
  }

  /** Same writes as OfferService.confirm -> BookingService.accept with an offer. */
  function confirmBatch(db, overrides = {}) {
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B1'), bookingFor('L1', { offerId: 'L1_driver1', agreedFarePaise: OFFER.pricePaise, ...overrides }));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'B1', matchedAt: serverTimestamp() });
    b.update(doc(db, 'vehicles', 'v1'), { availability: 'on_trip' });
    b.update(doc(db, 'offers', 'L1_driver1'), { status: 'confirmed', bookingId: 'B1', updatedAt: serverTimestamp() });
    return b.commit();
  }

  test('driver offers on an open load with their own vehicle; parties read it', async () => {
    await seedOpenLoad();
    await assertSucceeds(setDoc(ref(as('driver1')), OFFER));
    await assertSucceeds(getDoc(ref(as('customer1'))));
    await assertFails(getDoc(ref(as('driver2'))));
    // Wrong id, someone else's vehicle, bad price, own load.
    await assertFails(setDoc(ref(as('driver1'), 'L1_x'), OFFER));
    await assertFails(setDoc(ref(as('driver2'), 'L1_driver2'), { ...OFFER, driverId: 'driver2' }));
    await assertFails(setDoc(ref(as('driver2'), 'L1_driver2'), { ...OFFER, driverId: 'driver2', vehicleId: 'v2', pricePaise: 10.5, originalPaise: 10.5 }));
    await assertFails(setDoc(ref(as('customer1'), 'L1_customer1'), { ...OFFER, driverId: 'customer1' }));
  });

  test('customer counters once, driver accepts the counter at that price', async () => {
    await seedOffer();
    await assertFails(updateDoc(ref(as('driver1')), { status: 'countered', counterPaise: 1 }));
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'countered', counterPaise: 2000000 }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'pending', pricePaise: 2100000 }));
    await assertSucceeds(updateDoc(ref(as('driver1')), { status: 'pending', pricePaise: 2000000 }));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'countered', counterPaise: 1500000 }), 'only one counter');
  });

  test('select, then the driver confirms by creating the booking at the agreed price', async () => {
    await seedOffer();
    await assertFails(confirmBatch(as('driver1')), 'not selected yet');
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'selected' }));
    await assertFails(confirmBatch(as('driver1'), { agreedFarePaise: 1 }));
    await assertSucceeds(confirmBatch(as('driver1')));
  });

  test('a booking cannot claim an agreed fare without a confirmed offer', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { agreedFarePaise: 1 }));
  });

  test('withdraw and reject; terminal offers stay terminal', async () => {
    await seedOffer();
    await assertFails(updateDoc(ref(as('customer1')), { status: 'withdrawn' }));
    await assertSucceeds(updateDoc(ref(as('driver1')), { status: 'withdrawn' }));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'selected' }));
    await seedOffer({ status: 'selected' });
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'rejected' }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'pending' }));
    await assertFails(deleteDoc(ref(as('driver1'))));
  });
});

describe('trip OTPs, proof of delivery and e-way bill', () => {
  const otpRef = (db) => doc(db, 'bookings', 'L1', 'secrets', 'otp');
  const step = (db, status, extra = {}) =>
    updateDoc(doc(db, 'bookings', 'L1'), { status, [`timeline.${status}`]: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });

  test('only the customer creates and reads the OTPs; nobody changes them', async () => {
    await seedBooking();
    await assertFails(setDoc(otpRef(as('driver1')), OTPS));
    await assertFails(setDoc(otpRef(as('customer1')), { pickupOtp: '12345', deliveryOtp: '123456' }));
    await assertFails(setDoc(doc(as('customer1'), 'bookings', 'L1', 'secrets', 'other'), OTPS));
    await assertSucceeds(setDoc(otpRef(as('customer1')), OTPS));
    await assertSucceeds(getDoc(otpRef(as('customer1'))));
    await assertFails(getDoc(otpRef(as('driver1'))));
    await assertFails(setDoc(otpRef(as('customer1')), { pickupOtp: '000000', deliveryOtp: '000000' }));
    await assertFails(deleteDoc(otpRef(as('customer1'))));
  });

  test('pickup needs the right OTP and valid cargo details', async () => {
    await seedBooking('loading');
    await seed((s) => setDoc(otpRef(s), OTPS));
    const d = as('driver1');
    await assertFails(step(d, 'picked_up', { pickupOtp: '000000', pickupProof: PICKUP }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.deliveryOtp, pickupProof: PICKUP }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: { ...PICKUP, packages: 0 } }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: { ...PICKUP, extra: 1 } }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP, budget: 1 }));
    await assertSucceeds(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP }));
  });

  test('delivery needs the delivery OTP and a receiver name', async () => {
    await seedBooking('unloading');
    await seed((s) => setDoc(otpRef(s), OTPS));
    const d = as('driver1');
    const close = (extra) => {
      const b = writeBatch(d);
      b.update(doc(d, 'bookings', 'L1'), { status: 'delivered', 'timeline.delivered': serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
      b.update(doc(d, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() });
      return b.commit();
    };
    await assertFails(close({ deliveryOtp: OTPS.pickupOtp, deliveryProof: DELIVERY }));
    await assertFails(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: { ...DELIVERY, receiverName: '' } }));
    await assertFails(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: { ...DELIVERY, receiverPhone: 'abc' } }));
    await assertSucceeds(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: DELIVERY }));
  });

  test('without the customer secret nobody can pick up', async () => {
    await seedBooking('loading');
    await assertFails(step(as('driver1'), 'picked_up', { pickupOtp: '123456', pickupProof: PICKUP }));
  });

  test('driver may cancel while arriving but not once loading', async () => {
    await seedBooking('driver_arriving');
    const cancel = (db) => {
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'L1'), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation: { by: 'driver', chargePaise: 0 }, updatedAt: serverTimestamp() });
      b.update(doc(db, 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField(), matchedAt: deleteField(), reopenedAt: serverTimestamp() });
      b.set(doc(db, 'users', 'driver1'), { cancelCount: increment(1) }, { merge: true });
      return b.commit();
    };
    await assertSucceeds(cancel(as('driver1')));
    await seedBooking('loading');
    await assertFails(cancel(as('driver1')));
  });

  test('either party records a 12-digit e-way bill number', async () => {
    await seedBooking('in_transit');
    await assertSucceeds(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: '123456789012', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { ewayBillNo: '', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: 'EWB-1' }));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: '123456789012', status: 'delivered' }));
    await assertFails(updateDoc(doc(as('driver2'), 'bookings', 'L1'), { ewayBillNo: '123456789012' }));
  });
});

describe('booking chat', () => {
  const msg = (sender, text = 'Namaste', extra = {}) => ({ senderId: sender, text, flagged: false, createdAt: serverTimestamp(), ...extra });
  const msgs = (db) => collection(db, 'bookings', 'L1', 'messages');

  test('both parties send and read; outsiders cannot', async () => {
    await seedBooking();
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')));
    await assertSucceeds(addDoc(msgs(as('driver1')), msg('driver1', 'On my way', { flagged: true })));
    await assertSucceeds(getDocs(msgs(as('driver1'))));
    await assertFails(getDocs(msgs(as('driver2'))));
    await assertFails(addDoc(msgs(as('driver2')), msg('driver2')));
  });

  test('length, sender, server time and immutability are enforced', async () => {
    await seedBooking();
    const db = as('customer1');
    await assertFails(addDoc(msgs(db), msg('customer1', '')));
    await assertFails(addDoc(msgs(db), msg('customer1', 'x'.repeat(501))));
    await assertFails(addDoc(msgs(db), msg('driver1')));
    await assertFails(addDoc(msgs(db), msg('customer1', 'hi', { createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
    await assertFails(addDoc(msgs(db), msg('customer1', 'hi', { extra: 1 })));
    await seed((s) => setDoc(doc(s, 'bookings', 'L1', 'messages', 'm1'), msg('customer1')));
    await assertFails(updateDoc(doc(db, 'bookings', 'L1', 'messages', 'm1'), { text: 'edited' }));
    await assertFails(deleteDoc(doc(db, 'bookings', 'L1', 'messages', 'm1')));
  });

  test('a blocked sender cannot message the person who blocked them', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('customer1'), 'users', 'customer1', 'blocked', 'driver1'), { createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('driver1'), 'users', 'customer1', 'blocked', 'driver1')));
    await assertFails(addDoc(msgs(as('driver1')), msg('driver1')));
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')));
    await assertSucceeds(deleteDoc(doc(as('customer1'), 'users', 'customer1', 'blocked', 'driver1')));
    await assertSucceeds(addDoc(msgs(as('driver1')), msg('driver1')));
  });

  test('read marks are personal', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('driver1'), 'bookings', 'L1', 'chat_reads', 'driver1'), { lastReadAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver1'), 'bookings', 'L1', 'chat_reads', 'customer1'), { lastReadAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver2'), 'bookings', 'L1', 'chat_reads', 'driver2'), { lastReadAt: serverTimestamp() }));
  });

  test('reports: only about the other booking party; admins review', async () => {
    await seedBooking();
    const rep = (by, about, extra = {}) => ({ reporterId: by, reportedId: about, bookingId: 'L1', reason: 'off_platform', details: '', status: 'open', createdAt: serverTimestamp(), ...extra });
    await assertSucceeds(setDoc(doc(as('customer1'), 'reports', 'r1'), rep('customer1', 'driver1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'reports', 'r1')));
    await assertFails(getDoc(doc(as('driver1'), 'reports', 'r1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'reports', 'r1')));
    await assertFails(setDoc(doc(as('driver2'), 'reports', 'r2'), rep('driver2', 'customer1')));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r3'), rep('customer1', 'driver2')));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r4'), rep('customer1', 'driver1', { reason: 'meh' })));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r5'), rep('customer1', 'driver1', { status: 'resolved' })));
    await assertFails(updateDoc(doc(as('customer1'), 'reports', 'r1'), { status: 'resolved' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'reports', 'r1'), { status: 'resolved', resolvedBy: 'admin1' }));
  });
});

describe('support tickets', () => {
  const T = (uid, extra = {}) => ({
    userId: uid, category: 'booking_issue', priority: 'normal', status: 'open', subject: 'Driver late',
    description: '', escalationLevel: 0, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
  });
  const reply = (uid, extra = {}) => ({ authorId: uid, text: 'Any update?', fromAdmin: false, createdAt: serverTimestamp(), ...extra });

  test('users open their own tickets; disputes must name their booking', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('customer1'), 'tickets', 't1'), T('customer1')));
    await assertSucceeds(setDoc(doc(as('customer1'), 'tickets', 't2'), T('customer1', { category: 'dispute', bookingId: 'L1' })));
    await assertFails(setDoc(doc(as('customer1'), 'tickets', 't3'), T('customer1', { category: 'dispute' })));
    await assertFails(setDoc(doc(as('driver2'), 'tickets', 't4'), T('driver2', { bookingId: 'L1' })));
    await assertFails(setDoc(doc(as('customer1'), 'tickets', 't5'), T('driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'tickets', 't6'), T('customer1', { status: 'resolved' })));
    await assertFails(setDoc(doc(as('customer1'), 'tickets', 't7'), T('customer1', { escalationLevel: 2 })));
    await assertFails(getDoc(doc(as('driver1'), 'tickets', 't1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'tickets', 't1')));
  });

  test('escalate one level at a time up to 3, then close; admins manage status', async () => {
    await seed((db) => setDoc(doc(db, 'tickets', 't1'), T('customer1')));
    const db = as('customer1');
    await assertFails(updateDoc(doc(db, 'tickets', 't1'), { escalationLevel: 2 }));
    for (const level of [1, 2, 3]) await assertSucceeds(updateDoc(doc(db, 'tickets', 't1'), { escalationLevel: level }));
    await assertFails(updateDoc(doc(db, 'tickets', 't1'), { escalationLevel: 4 }));
    await assertFails(updateDoc(doc(db, 'tickets', 't1'), { status: 'resolved' }));
    await assertFails(updateDoc(doc(db, 'tickets', 't1'), { priority: 'urgent' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'tickets', 't1'), { status: 'in_progress', priority: 'high' }));
    await assertSucceeds(updateDoc(doc(db, 'tickets', 't1'), { status: 'closed' }));
  });

  test('replies: owner while open, admin as support', async () => {
    await seed((db) => setDoc(doc(db, 'tickets', 't1'), T('customer1')));
    const replies = (db) => collection(db, 'tickets', 't1', 'replies');
    await assertSucceeds(addDoc(replies(as('customer1')), reply('customer1')));
    await assertFails(addDoc(replies(as('customer1')), reply('customer1', { fromAdmin: true })));
    await assertFails(addDoc(replies(as('driver1')), reply('driver1')));
    await assertSucceeds(addDoc(replies(asAdmin()), reply('admin1', { fromAdmin: true })));
    await assertSucceeds(getDocs(replies(as('customer1'))));
    await seed((db) => updateDoc(doc(db, 'tickets', 't1'), { status: 'closed' }));
    await assertFails(addDoc(replies(as('customer1')), reply('customer1')));
  });
});

describe('safety', () => {
  const sos = (uid, extra = {}) => ({ userId: uid, status: 'open', location: new GeoPoint(28.6, 77.2), createdAt: serverTimestamp(), ...extra });

  test('SOS alerts: own, optionally tied to own booking; admins handle them', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('driver1'), 'sos_alerts', 's1'), sos('driver1', { bookingId: 'L1' })));
    await assertSucceeds(setDoc(doc(as('driver2'), 'sos_alerts', 's2'), sos('driver2', { location: null })));
    await assertFails(setDoc(doc(as('driver2'), 'sos_alerts', 's3'), sos('driver2', { bookingId: 'L1' })));
    await assertFails(setDoc(doc(as('driver2'), 'sos_alerts', 's4'), sos('driver1')));
    await assertFails(getDoc(doc(as('customer1'), 'sos_alerts', 's1')));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'sos_alerts', 's1'), { status: 'acknowledged', handledBy: 'admin1' }));
    await assertFails(updateDoc(doc(as('driver1'), 'sos_alerts', 's1'), { status: 'resolved' }));
  });

  test('emergency contacts: at most three', async () => {
    const c = (n) => Array.from({ length: n }, (_, i) => ({ name: `C${i}`, phone: '+919800000000' }));
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', emergencyContacts: c(3) }));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { emergencyContacts: c(4) }));
  });

  test('breakdown: once, by the driver of an active trip, and the customer is notified', async () => {
    await seedBooking('in_transit');
    const d = as('driver1');
    const report = (db, extra = {}) => {
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'L1'), { breakdown: { note: 'tyre burst', replacementRequested: true, reportedAt: serverTimestamp() }, updatedAt: serverTimestamp(), ...extra });
      b.set(doc(db, 'notifications', 'n1'), { userId: 'customer1', type: 'breakdown_reported', message: 'Delhi → Mumbai', relatedId: 'L1', read: false, createdAt: serverTimestamp() });
      return b.commit();
    };
    await assertFails(report(as('customer1')));
    await assertFails(report(d, { status: 'delivered' }));
    await assertSucceeds(report(d));
    await assertFails(updateDoc(doc(d, 'bookings', 'L1'), { breakdown: { note: 'again', replacementRequested: false, reportedAt: serverTimestamp() } }));
  });
});

describe('payment records and ledger', () => {
  const mark = (db, amount = 2500000, extra = {}) =>
    updateDoc(doc(db, 'bookings', 'L1'), { paymentStatus: 'customer_marked_paid', paidAmountPaise: amount, paymentMarkedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
  const confirm = (db, earning = 2500000, commission = -125000) => {
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'L1'), { paymentStatus: 'driver_confirmed', paymentConfirmedAt: serverTimestamp(), updatedAt: serverTimestamp() });
    b.set(doc(db, 'ledger', 'L1_trip_earning'), { driverId: 'driver1', bookingId: 'L1', type: 'trip_earning', amountPaise: earning, createdAt: serverTimestamp() });
    b.set(doc(db, 'ledger', 'L1_platform_commission'), { driverId: 'driver1', bookingId: 'L1', type: 'platform_commission', amountPaise: commission, createdAt: serverTimestamp() });
    return b.commit();
  };

  test('customer marks paid once; driver cannot mark for them', async () => {
    await seedBooking('delivered');
    await assertFails(mark(as('driver1')));
    await assertFails(mark(as('customer1'), 0));
    await assertFails(mark(as('customer1'), 99.5));
    await assertSucceeds(mark(as('customer1')));
    await assertFails(mark(as('customer1'), 100), 'already marked');
  });

  test('driver confirms with matching ledger lines; ledger is append-only', async () => {
    await seedBooking('delivered');
    await assertFails(confirm(as('driver1')), 'customer has not marked paid');
    await mark(as('customer1'));
    await assertFails(confirm(as('driver1'), 9999999), 'earning must equal the paid amount');
    await assertFails(confirm(as('driver1'), 2500000, 125000), 'commission is negative');
    await assertFails(confirm(as('driver1'), 2500000, -2000000), 'commission at most half');
    await assertFails(confirm(as('customer1')));
    await assertSucceeds(confirm(as('driver1')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'ledger', 'L1_trip_earning')));
    await assertFails(getDoc(doc(as('customer1'), 'ledger', 'L1_trip_earning')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'ledger', 'L1_trip_earning')));
    await assertFails(updateDoc(doc(as('driver1'), 'ledger', 'L1_trip_earning'), { amountPaise: 1 }));
    await assertFails(deleteDoc(doc(as('driver1'), 'ledger', 'L1_platform_commission')));
  });

  test('loads carry a payment mode the booking must copy', async () => {
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'X'), { ...LOAD, paymentMode: 'bitcoin' }));
    await seed(async (s) => {
      await setDoc(doc(s, 'loads', 'L1'), { ...LOAD, paymentMode: 'upi_direct' });
      await setDoc(doc(s, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { paymentMode: 'upi_direct', paymentStatus: 'driver_confirmed' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { paymentMode: 'upi_direct', paymentStatus: 'pending' }));
  });
});

describe('anti-fraud', () => {
  const setTier = (db, uid, tier) => updateDoc(doc(db, 'users', uid), { riskTier: tier, riskReason: 'x', riskUpdatedAt: serverTimestamp() });
  const event = (type, extra = {}) => ({ type, actorId: 'u1', data: {}, createdAt: serverTimestamp(), ...extra });

  test('only admins write riskTier; users cannot touch it or their risk fields', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91' }));
    await assertSucceeds(setTier(asAdmin(), 'u1', 'restricted'));
    await assertSucceeds(setTier(asAdmin(), 'u1', 'normal'));
    await assertFails(setTier(asAdmin(), 'u1', 'banned'));
    await assertFails(setTier(as('u1'), 'u1', 'normal'));
    await assertFails(setTier(as('u2'), 'u1', 'normal'));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { riskReason: 'fine' }));
    await assertFails(setDoc(doc(as('u9'), 'users', 'u9'), { phone: '+91', riskTier: 'normal' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { riskTier: 'review', riskReason: 'x', riskUpdatedAt: serverTimestamp(), phone: '1' }));
  });

  test('cancelCount can only go up by one', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91', cancelCount: 2 }));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { cancelCount: 0 }));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { cancelCount: 5 }));
    await assertSucceeds(updateDoc(doc(as('u1'), 'users', 'u1'), { cancelCount: increment(1) }));
  });

  test('restricted and suspended users cannot post, offer or accept', async () => {
    await seedOpenLoad();
    for (const tier of ['restricted', 'suspended']) {
      await seed((db) => setDoc(doc(db, 'users', 'customer2'), { riskTier: tier }));
      await assertFails(setDoc(doc(as('customer2'), 'loads', 'L9'), { ...LOAD, shipperId: 'customer2' }));
      await seed((db) => setDoc(doc(db, 'users', 'driver1'), { riskTier: tier }));
      await assertFails(acceptBatch(as('driver1'), 'L1'));
    }
    await seed((db) => setDoc(doc(db, 'users', 'customer2'), { riskTier: 'review' }));
    await assertSucceeds(setDoc(doc(as('customer2'), 'loads', 'L9'), { ...LOAD, shipperId: 'customer2' }));
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { riskTier: 'normal' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });

  test('a restricted driver cannot send an offer', async () => {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { riskTier: 'restricted' }));
    await assertFails(setDoc(doc(as('driver1'), 'offers', 'L1_driver1'), {
      loadId: 'L1', driverId: 'driver1', customerId: 'customer1', vehicleId: 'v1', vehicleNumber: VEHICLE.number, vehicleType: '20ft',
      driverName: 'R', pricePaise: 100000, originalPaise: 100000, status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }));
  });

  test('audit_events are append-only, self-attributed, admin-read', async () => {
    await assertSucceeds(addDoc(collection(as('u1'), 'audit_events'), event('accept')));
    await assertSucceeds(addDoc(collection(as('u1'), 'audit_events'), event('cancel', { bookingId: 'B1' })));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('accept', { actorId: 'u2' })));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('bogus')));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('accept', { extra: 1 })));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('accept', { createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
    // Verification and risk changes only come from admins.
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('verification')));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), event('risk_change')));
    await assertSucceeds(addDoc(collection(asAdmin(), 'audit_events'), event('risk_change', { actorId: 'admin1', targetId: 'u1' })));
    await assertFails(addDoc(collection(anon(), 'audit_events'), event('accept')));

    let id;
    await seed(async (db) => { id = (await addDoc(collection(db, 'audit_events'), event('accept'))).id; });
    await assertSucceeds(getDoc(doc(asAdmin(), 'audit_events', id)));
    await assertFails(getDoc(doc(as('u1'), 'audit_events', id)));
    await assertFails(updateDoc(doc(asAdmin(), 'audit_events', id), { type: 'cancel' }));
    await assertFails(deleteDoc(doc(asAdmin(), 'audit_events', id)));
  });

  test('admin can list flagged users and open reports', async () => {
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'users'), where('riskTier', 'in', ['review', 'restricted', 'suspended']))));
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'users'), where('cancelCount', '>=', 3))));
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'reports'), where('status', '==', 'open'))));
    await assertFails(getDocs(query(collection(as('u1'), 'users'), where('cancelCount', '>=', 3))));
  });
});

describe('admin allowlist and powers', () => {
  const reassign = (db, extra = {}) => {
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'L1'), { driverId: 'driver2', vehicleId: 'v2', vehicleNumber: 'KA01CD5678', vehicleType: '20ft', driverName: 'Suresh', driverPhone: '+91', reassignedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
    b.update(doc(db, 'loads', 'L1'), { driverId: 'driver2' });
    return b.commit();
  };

  test('admins/{uid}: own read only, nobody writes; an admin claim alone is not enough', async () => {
    await assertSucceeds(getDoc(doc(as('admin1'), 'admins', 'admin1')));
    await assertFails(getDoc(doc(as('u1'), 'admins', 'admin1')));
    await assertFails(setDoc(doc(as('u1'), 'admins', 'u1'), { x: 1 }));
    await assertFails(setDoc(doc(asAdmin(), 'admins', 'u1'), { x: 1 }));
    await assertFails(getDoc(doc(env.authenticatedContext('u1', { admin: true }).firestore(), 'users', 'admin1')));
  });

  test('admins read all loads and bookings; others cannot', async () => {
    await seedBooking();
    await assertSucceeds(getDoc(doc(asAdmin(), 'loads', 'L1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'bookings', 'L1')));
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'bookings'), where('status', '==', 'accepted'))));
    await assertFails(getDoc(doc(as('u1'), 'bookings', 'L1')));
    await assertFails(updateDoc(doc(asAdmin(), 'bookings', 'L1'), { status: 'delivered' }));
    await assertFails(updateDoc(doc(asAdmin(), 'loads', 'L1'), { budget: 1 }));
  });

  test('admin reassigns a booking before pickup, with the load and the new vehicle', async () => {
    await seedBooking();
    await assertFails(reassign(as('u1')));
    await assertFails(reassign(asAdmin(), { vehicleId: 'v1' })); // v1 belongs to driver1
    await assertFails(reassign(asAdmin(), { status: 'delivered' }));
    await assertSucceeds(reassign(asAdmin()));
    await seedBooking('picked_up');
    await assertFails(reassign(asAdmin()));
  });

  test('admin audit event for reassign; users cannot forge it', async () => {
    await assertSucceeds(addDoc(collection(asAdmin(), 'audit_events'), { type: 'reassign', actorId: 'admin1', data: {}, createdAt: serverTimestamp() }));
    await assertFails(addDoc(collection(as('u1'), 'audit_events'), { type: 'reassign', actorId: 'u1', data: {}, createdAt: serverTimestamp() }));
  });

  test('admin edits pricing and vehicle_types config; users cannot', async () => {
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'pricing'), { platformFeePercent: 5, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('u1'), 'config', 'pricing'), { platformFeePercent: 0 }));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), { types: [{ id: 'x' }], updatedAt: serverTimestamp() }));
  });
});

describe('favourite routes', () => {
  const route = (extra = {}) => ({ pickup: 'Mumbai', drop: 'Delhi', createdAt: serverTimestamp(), ...extra });
  test('only the owner reads and writes valid routes', async () => {
    await assertSucceeds(setDoc(doc(as('driver1'), 'users', 'driver1', 'favourite_routes', 'r1'), route()));
    await assertSucceeds(getDoc(doc(as('driver1'), 'users', 'driver1', 'favourite_routes', 'r1')));
    await assertFails(getDoc(doc(as('driver2'), 'users', 'driver1', 'favourite_routes', 'r1')));
    await assertFails(setDoc(doc(as('driver2'), 'users', 'driver1', 'favourite_routes', 'r2'), route()));
    await assertFails(setDoc(doc(as('driver1'), 'users', 'driver1', 'favourite_routes', 'r3'), route({ pickup: 'M' })));
    await assertFails(setDoc(doc(as('driver1'), 'users', 'driver1', 'favourite_routes', 'r4'), route({ extra: 1 })));
    await assertSucceeds(deleteDoc(doc(as('driver1'), 'users', 'driver1', 'favourite_routes', 'r1')));
  });
});

describe('settings, consents and deletion requests', () => {
  test('notificationPrefs and consents must be boolean maps with known keys', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91' }));
    const u = doc(as('u1'), 'users', 'u1');
    await assertSucceeds(updateDoc(u, { notificationPrefs: { bookingUpdates: true, ratings: false, promotions: true } }));
    await assertSucceeds(updateDoc(u, { consents: { location: true, analytics: false, marketing: false }, consentsUpdatedAt: serverTimestamp() }));
    await assertFails(updateDoc(u, { notificationPrefs: { bookingUpdates: 'yes', ratings: false, promotions: true } }));
    await assertFails(updateDoc(u, { notificationPrefs: { bookingUpdates: true, ratings: true, promotions: true, spam: true } }));
    await assertFails(updateDoc(u, { consents: 'all' }));
  });

  test('one deletion request per user; admin marks it done', async () => {
    const req = (extra = {}) => ({ userId: 'u1', status: 'pending', reason: 'leaving', createdAt: serverTimestamp(), ...extra });
    await assertFails(setDoc(doc(as('u2'), 'deletion_requests', 'u1'), req()));
    await assertFails(setDoc(doc(as('u1'), 'deletion_requests', 'u1'), req({ status: 'done' })));
    await assertSucceeds(setDoc(doc(as('u1'), 'deletion_requests', 'u1'), req()));
    await assertSucceeds(getDoc(doc(as('u1'), 'deletion_requests', 'u1')));
    await assertFails(getDoc(doc(as('u2'), 'deletion_requests', 'u1')));
    // Cannot re-request or edit while pending.
    await assertFails(setDoc(doc(as('u1'), 'deletion_requests', 'u1'), req({ reason: 'again' })));
    await assertFails(updateDoc(doc(as('u1'), 'deletion_requests', 'u1'), { status: 'done' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'deletion_requests', 'u1'), { status: 'done', handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertSucceeds(getDocs(collection(asAdmin(), 'deletion_requests')));
    await assertFails(getDocs(collection(as('u1'), 'deletion_requests')));
    await assertFails(deleteDoc(doc(asAdmin(), 'deletion_requests', 'u1')));
  });
});

describe('enterprise lite and import/export', () => {
  const GSTIN = '27AAPFU0939F1ZV';
  const shipment = (extra = {}) => ({
    ownerId: 'customer1', kind: 'export', origin: 'Pune', hub: 'JNPT, Navi Mumbai', destination: 'Mumbai',
    containerNumber: 'CSQU3054383', sealNumber: 'SL-1', leg1LoadId: 'a', leg2LoadId: 'b', createdAt: serverTimestamp(), ...extra,
  });

  test('business profile needs a GSTIN in the official format', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91' }));
    const u = doc(as('u1'), 'users', 'u1');
    await assertSucceeds(updateDoc(u, { business: { legalName: 'Acme', gstin: GSTIN, address: 'Pune' } }));
    await assertSucceeds(updateDoc(u, { business: { legalName: 'Acme', gstin: '', address: '' } }));
    await assertFails(updateDoc(u, { business: { legalName: 'Acme', gstin: '27AAPFU0939F1XV', address: '' } }));
    await assertFails(updateDoc(u, { business: { legalName: 'Acme', gstin: 'abc', address: '' } }));
    await assertFails(updateDoc(u, { business: { legalName: 'Acme', gstin: GSTIN, address: '', verified: true } }));
    await assertFails(updateDoc(u, { business: 'Acme' }));
  });

  test('branches: owner only, valid type and name', async () => {
    const b = (extra = {}) => ({ type: 'warehouse', name: 'Bhiwandi WH', address: 'Plot 4', city: 'Bhiwandi', createdAt: serverTimestamp(), ...extra });
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1', 'branches', 'b1'), b()));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u1', 'branches', 'b2'), b()));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'branches', 'b3'), b({ type: 'moon' })));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'branches', 'b4'), b({ name: '' })));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'branches', 'b5'), b({ extra: 1 })));
    await assertFails(getDoc(doc(as('u2'), 'users', 'u1', 'branches', 'b1')));
    await assertSucceeds(deleteDoc(doc(as('u1'), 'users', 'u1', 'branches', 'b1')));
  });

  test('loads accept container, seal and shipment fields only in valid shape', async () => {
    const withExtra = (extra) => setDoc(doc(as('customer1'), 'loads', 'T' + Math.random().toString(36).slice(2)), { ...LOAD, ...extra });
    await assertSucceeds(withExtra({ containerNumber: 'CSQU3054383', sealNumber: 'SL-9', branchId: 'b1', shipmentId: 's1', shipmentLeg: 1 }));
    await assertFails(withExtra({ containerNumber: 'csqu3054383' }));
    await assertFails(withExtra({ containerNumber: 'CSQU305438' }));
    await assertFails(withExtra({ sealNumber: 'bad seal!' }));
    await assertFails(withExtra({ shipmentLeg: 3 }));
    await assertFails(withExtra({ branchId: '' }));
  });

  test('the booking must carry the load container and seal numbers unchanged', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, containerNumber: 'CSQU3054383', sealNumber: 'SL-9' });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { containerNumber: 'MSKU9070322', sealNumber: 'SL-9' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { containerNumber: 'CSQU3054383', sealNumber: 'SL-9' }));
  });

  test('shipments: owner creates once, immutable, owner/admin read', async () => {
    await assertSucceeds(setDoc(doc(as('customer1'), 'shipments', 's1'), shipment()));
    await assertFails(setDoc(doc(as('customer2'), 'shipments', 's2'), shipment()));
    await assertFails(setDoc(doc(as('customer1'), 'shipments', 's3'), shipment({ kind: 'transit' })));
    await assertFails(setDoc(doc(as('customer1'), 'shipments', 's4'), shipment({ containerNumber: 'bad' })));
    await assertFails(setDoc(doc(as('customer1'), 'shipments', 's5'), shipment({ extra: 1 })));
    await assertSucceeds(getDoc(doc(as('customer1'), 'shipments', 's1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'shipments', 's1')));
    await assertFails(getDoc(doc(as('customer2'), 'shipments', 's1')));
    await assertFails(updateDoc(doc(as('customer1'), 'shipments', 's1'), { hub: 'x' }));
    await assertFails(deleteDoc(doc(as('customer1'), 'shipments', 's1')));
    await seed((db) => setDoc(doc(db, 'users', 'customer1'), { riskTier: 'restricted' }));
    await assertFails(setDoc(doc(as('customer1'), 'shipments', 's6'), shipment()));
  });
});

describe('hardening', () => {
  test('unknown collections are closed', async () => {
    await assertFails(setDoc(doc(as('u1'), 'surprise', 'x'), { a: 1 }));
    await assertFails(getDoc(doc(as('u1'), 'surprise', 'x')));
    await assertFails(setDoc(doc(asAdmin(), 'surprise', 'x'), { a: 1 }));
  });

  test('a booking cannot be created with extra fields or a pre-filled timeline', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { pickupOtpVerified: true }));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { deliveryProof: { receiverName: 'x' } }));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { timeline: { accepted: serverTimestamp(), delivered: serverTimestamp() } }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });
});
