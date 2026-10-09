// Security rules tests. Run with: npm test  (starts the Firestore emulator)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe as realDescribe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { GeoPoint, Timestamp, addDoc as rawAddDoc, deleteField, doc, getDoc, getDocs, collection, query, where, orderBy, limit, setDoc as rawSetDoc, updateDoc, deleteDoc, writeBatch as rawWriteBatch, serverTimestamp, increment, terminate } from 'firebase/firestore';

let env;

// The suite is large and a long run was cut off (SIGTERM after about a minute)
// in a small codespace. `npm test` runs it in RULES_PARTS slices, one
// emulator session each (RULES_PART=1..N). Without RULES_PART everything runs.
const PARTS = Number(process.env.RULES_PARTS || 4);
// Only top-level suites are dealt out to slices; a nested describe always goes
// with its parent. (Counting nested ones as well made the numbering depend on
// which slice ran, so some suites ran in several slices and some in none.)
let describeIndex = 0;
let depth = 0;
const describe = (...args) => {
  if (depth > 0) return realDescribe(...args);
  const part = Number(process.env.RULES_PART || 0);
  const mine = !part || describeIndex++ % PARTS === part - 1;
  if (!mine) return undefined;
  const at = args.findIndex((a) => typeof a === 'function');
  const body = args[at];
  args[at] = (...a) => {
    depth++;
    try {
      return body(...a);
    } finally {
      depth--;
    }
  };
  return realDescribe(...args);
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
  trackClients();
});
after(() => env.cleanup());

// Every as()/anon() call opens a client. Close them after each test: a run of
// several hundred tests otherwise grows until a small machine kills the process.
const opened = new Set();
function trackClients() {
  for (const m of ['authenticatedContext', 'unauthenticatedContext']) {
    const orig = env[m].bind(env);
    env[m] = (...args) => {
      const ctx = orig(...args);
      const f = ctx.firestore.bind(ctx);
      ctx.firestore = (...a) => {
        const d = f(...a);
        opened.add(d);
        return d;
      };
      return ctx;
    };
  }
}
afterEach(async () => {
  const list = [...opened];
  opened.clear();
  await Promise.all(list.map((d) => terminate(d._delegate ?? d).catch(() => {})));
});
// admins/{uid} allowlist: admin1 is an admin (created by hand in the Console in real life).
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'admins', 'admin1'), { createdBy: 'console' }));
});

const as = (uid) => {
  const db = env.authenticatedContext(uid).firestore();
  db.__uid = uid;
  if (db._delegate) db._delegate.__uid = uid; // doc(db, ...).firestore is the delegate
  return db;
};

// Loads, offers and chat messages must bump the user's hourly counter in the
// same batch (rate_limits). These wrappers do that for every test, so the
// existing suites keep testing what they test; the rate-limit suite below uses
// the raw functions. The counter is seeded as an expired window, so a bump is
// always "first in a new hour".
const COUNTED_PATH = /^(loads|offers|calls|tickets)\/[^/]+$|^(bookings|driver_links|driver_groups)\/[^/]+\/messages\/[^/]+$/;
const kindOf = (path) => (path.startsWith('loads/') ? 'load' : path.startsWith('offers/') ? 'offer' : path.startsWith('calls/') ? 'call' : path.startsWith('tickets/') ? 'ticket' : 'message');
const expiredCounter = (uid, kind) =>
  env.withSecurityRulesDisabled((ctx) =>
    rawSetDoc(doc(ctx.firestore(), 'rate_limits', `${uid}_${kind}`), { count: 1, windowStart: Timestamp.fromMillis(Date.now() - 7200000), last: 'seed' }));
const counted = (ref, db) => !!db.__uid && COUNTED_PATH.test(ref.path);

const setDoc = async (ref, data, opts) => {
  const db = ref.firestore;
  if (opts !== undefined || !counted(ref, db)) return opts === undefined ? rawSetDoc(ref, data) : rawSetDoc(ref, data, opts);
  const kind = kindOf(ref.path);
  await expiredCounter(db.__uid, kind);
  const b = rawWriteBatch(db);
  b.set(ref, data);
  b.set(doc(db, 'rate_limits', `${db.__uid}_${kind}`), { count: 1, windowStart: serverTimestamp(), last: ref.id });
  return b.commit();
};

const addDoc = (col, data) => (COUNTED_PATH.test(`${col.path}/x`) && col.firestore.__uid ? setDoc(doc(col), data) : rawAddDoc(col, data));

const writeBatch = (db) => {
  const real = rawWriteBatch(db);
  let paid = null;
  const batch = {
    set(ref, data, opts) {
      if (opts === undefined && paid === null && counted(ref, db)) paid = ref;
      if (opts === undefined) real.set(ref, data);
      else real.set(ref, data, opts);
      return batch;
    },
    update(...args) {
      real.update(...args);
      return batch;
    },
    delete(ref) {
      real.delete(ref);
      return batch;
    },
    async commit() {
      if (paid) {
        const kind = kindOf(paid.path);
        await expiredCounter(db.__uid, kind);
        real.set(doc(db, 'rate_limits', `${db.__uid}_${kind}`), { count: 1, windowStart: serverTimestamp(), last: paid.id });
      }
      return real.commit();
    },
  };
  return batch;
};
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
    driverPhone: '',
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

describe('expireAt on short-lived logs (MASTER-5 Task 7)', () => {
  const err = (extra = {}) => ({ message: 'boom', screen: 'Home', kind: 'flutter', appVersion: '1.0', createdAt: serverTimestamp(), ...extra });
  const days = (n) => Timestamp.fromMillis(Date.now() + n * 86400000);
  test('app_errors accept expireAt within about 4 months, never far in the future or a wrong type', async () => {
    await assertSucceeds(addDoc(collection(as('u1'), 'app_errors'), err()));
    await assertSucceeds(addDoc(collection(as('u1'), 'app_errors'), err({ expireAt: days(90) })));
    await assertSucceeds(addDoc(collection(as('u1'), 'app_errors'), err({ expireAt: days(-3) })));
    await assertFails(addDoc(collection(as('u1'), 'app_errors'), err({ expireAt: days(900) })));
    await assertFails(addDoc(collection(as('u1'), 'app_errors'), err({ expireAt: 'never' })));
  });
});

describe('role lock and identity index for every role (MASTER-5 Task 3)', () => {
  const ROLES = ['customer', 'driver', 'fleet'];
  const HASH = (n) => String(n).repeat(64).slice(0, 64);
  for (const role of ROLES) {
    test(`${role}: the role cannot be switched to any other role`, async () => {
      await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91', role, selectedRole: role }));
      const ref = doc(as('u1'), 'users', 'u1');
      for (const other of ROLES.filter((r) => r !== role)) {
        await assertFails(updateDoc(ref, { role: other }));
        await assertFails(updateDoc(ref, { selectedRole: other }));
        await assertFails(updateDoc(ref, { role: other, selectedRole: other }));
      }
      await assertSucceeds(updateDoc(ref, { name: 'Same Role' }));
    });
    test(`${role}: an identity entry must carry that role and the owner's uid`, async () => {
      await seed((db) => setDoc(doc(db, 'users', 'u1'), { role, selectedRole: role }));
      const entry = (r, uid = 'u1') => ({ uid, role: r, type: 'gst', createdAt: serverTimestamp() });
      const create = (r, uid, hash) => {
        const db = as('u1');
        const b = writeBatch(db);
        b.set(doc(db, 'identity_index', hash), entry(r, uid));
        return b.commit();
      };
      for (const other of ROLES.filter((r) => r !== role)) await assertFails(create(other, 'u1', HASH(5)));
      await assertFails(create(role, 'someone-else', HASH(5)));
      await assertFails(setDoc(doc(as('u1'), 'identity_index', 'short'), entry(role)));
    });
  }
  test('nobody can list the identity index, not even the owner', async () => {
    await seed((db) => setDoc(doc(db, 'identity_index', HASH(7)), { uid: 'u1', role: 'driver', type: 'dl' }));
    for (const uid of ['u1', 'u2']) await assertFails(getDocs(collection(as(uid), 'identity_index')));
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

function seedUsersForSwitch() {
  return seed(async (db) => {
    await setDoc(doc(db, 'users', 'referrer'), { role: 'customer', createdAt: Timestamp.fromDate(new Date(Date.now() - 9 * 86400000)), referralCode: 'FRIEND' });
    await setDoc(doc(db, 'referral_codes', 'FRIEND'), { uid: 'referrer' });
    await setDoc(doc(db, 'users', 'newbie'), { role: 'customer', createdAt: Timestamp.now() });
  });
}
function referralBatch(uid) {
  const db = as(uid);
  const b = writeBatch(db);
  b.set(doc(db, 'referrals', uid), { referrerUid: 'referrer', code: 'FRIEND', createdAt: serverTimestamp() });
  b.set(doc(db, 'users', uid, 'credits', 'referral_in'), { amountPaise: 10000, kind: 'referral', createdAt: serverTimestamp() });
  b.set(doc(db, 'users', 'referrer', 'credits', `referral_from_${uid}`), { amountPaise: 10000, kind: 'referral', createdAt: serverTimestamp() });
  return b.commit();
}

describe('customer offers', () => {
  const future = Timestamp.fromDate(new Date('2035-01-01'));
  const past = Timestamp.fromDate(new Date('2020-01-01'));
  const promoDoc = (over = {}) => ({
    code: 'SAVE10', type: 'percent', value: 10, maxDiscountPaise: 0, minOrderPaise: 0, expiresAt: future,
    usageLimit: 3, perUserLimit: 1, active: true, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
  });
  const seedPromo = (over = {}) => seed((db) => setDoc(doc(db, 'promos', over.code ?? 'SAVE10'), promoDoc({ ...over, createdAt: Timestamp.now(), updatedAt: Timestamp.now() })));
  const EST = { total: 50000, tripFare: 45000, distanceKm: 10 };
  const ALL_ON = { promoEnabled: true, creditsEnabled: true, referralEnabled: true };
  // The offers are OFF until an admin switches them on; most tests need them on.
  beforeEach(() => seed((db) => setDoc(doc(db, 'config', 'offers'), ALL_ON)));

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

  test('switches: with config/offers missing or a flag off, promo, credits and referral are refused', async () => {
    await seedPromo();
    await seedUsersForSwitch();
    await seed((db) => setDoc(doc(db, 'config', 'offers'), { promoEnabled: false, creditsEnabled: false, referralEnabled: false }));
    await assertFails(postOffer('customer1', { promo: { code: 'SAVE10', discountPaise: 5000 } }));
    await assertFails(postOffer('customer1', { id: 'L2', credits: 1000 }));
    await assertFails(referralBatch('newbie'));
    await assertSucceeds(postOffer('customer1', { id: 'L3' }), 'a plain load needs no switch');
    await seed((db) => setDoc(doc(db, 'config', 'offers'), { promoEnabled: true }));
    await assertSucceeds(postOffer('customer1', { id: 'L4', promo: { code: 'SAVE10', discountPaise: 5000 } }));
    await assertFails(postOffer('customer1', { id: 'L5', credits: 1000 }), 'credits still off');
    await assertFails(referralBatch('newbie'), 'referral still off');
    await seed((db) => setDoc(doc(db, 'config', 'offers'), { creditsEnabled: true, referralEnabled: true }));
    await assertSucceeds(postOffer('customer1', { id: 'L6', credits: 1000 }));
    await assertSucceeds(referralBatch('newbie'));
    await seed((db) => deleteDoc(doc(db, 'config', 'offers')));
    await assertFails(postOffer('customer1', { id: 'L7', credits: 1000 }), 'no config doc = off');
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
      await seed((db) => setDoc(doc(db, 'config', 'offers'), { ...ALL_ON, referralBonusPaise: 25000 }));
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

  test('a driver shares the licence date with their fleet; nothing else, nobody else', async () => {
    await seedUsers();
    await seed((db) => setDoc(doc(db, 'fleet_members', 'owner1_driver1'), member({ createdAt: Timestamp.now() })));
    const d = () => as('driver1');
    const exp = Timestamp.fromDate(new Date('2027-01-01'));
    await assertSucceeds(updateDoc(doc(d(), 'fleet_members', 'owner1_driver1'), { licenceExpiry: exp }));
    await assertFails(updateDoc(doc(as('owner1'), 'fleet_members', 'owner1_driver1'), { licenceExpiry: exp }), 'the transporter cannot write it');
    await assertFails(updateDoc(doc(as('driver2'), 'fleet_members', 'owner1_driver1'), { licenceExpiry: exp }));
    await assertFails(updateDoc(doc(d(), 'fleet_members', 'owner1_driver1'), { licenceExpiry: 'soon' }));
    await assertFails(updateDoc(doc(d(), 'fleet_members', 'owner1_driver1'), { licenceExpiry: exp, driverName: 'X' }));
    await assertFails(updateDoc(doc(d(), 'fleet_members', 'owner1_driver1'), { active: true, licenceExpiry: exp, endedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(as('owner1'), 'fleet_members', 'owner1_driver1')), 'the transporter reads it');
    await seed((db) => updateDoc(doc(db, 'fleet_members', 'owner1_driver1'), { active: false }));
    await assertFails(updateDoc(doc(d(), 'fleet_members', 'owner1_driver1'), { licenceExpiry: exp }), 'after leaving the fleet nothing is shared');
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
      await assertFails(acceptBatch(as('owner1'), 'L1', 'owner1', { vehicleId: 'fv1', fleetOwnerId: 'someoneElse' }));
      await assertSucceeds(acceptBatch(as('owner1'), 'L1', 'owner1', { vehicleId: 'fv1' }));
    });
  });
});

describe('transporter (Task 67)', () => {
  const asPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
  const member = (over = {}) => ({ ownerId: 'tr1', ownerName: 'Sunil', driverId: 'driver1', driverName: 'Ramesh', driverPhone: '+919876543210', active: true, createdAt: Timestamp.now(), ...over });
  const COMPANY_OFFER = { loadId: 'L1', driverId: 'tr1', customerId: 'customer1', vehicleId: 'tv1', vehicleNumber: 'MH12AB1234', vehicleType: '20ft', driverName: 'Sharma Roadlines', pricePaise: 2400000, originalPaise: 2400000, status: 'pending', fleetOwnerId: 'tr1' };

  const seedAll = () =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', 'tr1'), { role: 'fleet', selectedRole: 'fleet' });
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver' });
      await setDoc(doc(db, 'users', 'driver2'), { role: 'driver', selectedRole: 'driver' });
      await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', selectedRole: 'customer' });
      await setDoc(doc(db, 'fleet_members', 'tr1_driver1'), member());
      await setDoc(doc(db, 'vehicles', 'tv1'), { ...VEHICLE, ownerId: 'tr1' });
      await setDoc(doc(db, 'vehicles', 'dv1'), { ...VEHICLE, ownerId: 'driver1', number: 'KA01CD5678' });
      await setDoc(doc(db, 'vehicles', 'dv2'), { ...VEHICLE, ownerId: 'driver2', number: 'KA01CD9999' });
      await setDoc(doc(db, 'loads', 'L1'), LOAD);
    });

  test('profile: the owner writes office city, routes, vehicle types and count; junk is refused', async () => {
    await seedAll();
    const ref = doc(as('tr1'), 'users', 'tr1');
    await assertSucceeds(updateDoc(ref, { fleet: { pan: 'ABCDE1234F', officeCity: 'Indore', routes: ['Indore-Pune'], vehicleTypes: ['20ft'], vehicleCount: 12 } }));
    await assertFails(updateDoc(ref, { fleet: { pan: 'ABCDE1234F', vehicleCount: -1 } }));
    await assertFails(updateDoc(ref, { fleet: { pan: 'ABCDE1234F', vehicleCount: 1.5 } }));
    await assertFails(updateDoc(ref, { fleet: { pan: 'ABCDE1234F', verified: true } }));
    await assertFails(updateDoc(ref, { fleet: { pan: 'ABCDE1234F', routes: Array(11).fill('a-b') } }));
    // The badge is admin only.
    await assertFails(updateDoc(ref, { verified: true, verificationStatus: 'approved' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'tr1'), { verified: true, verificationStatus: 'approved' }));
  });

  test('attach: a member attaches their own vehicle; a stranger or a non-member cannot', async () => {
    await seedAll();
    await assertSucceeds(updateDoc(doc(as('driver1'), 'vehicles', 'dv1'), { attachedTo: 'tr1' }));
    await assertFails(updateDoc(doc(as('driver2'), 'vehicles', 'dv2'), { attachedTo: 'tr1' }), 'driver2 never joined');
    await assertFails(updateDoc(doc(as('tr1'), 'vehicles', 'dv1'), { attachedTo: 'tr1' }), 'the transporter cannot attach for the driver');
    await assertSucceeds(updateDoc(doc(as('tr1'), 'vehicles', 'dv1'), { availability: 'on_trip' }));
    await assertFails(updateDoc(doc(as('tr1'), 'vehicles', 'dv1'), { capacity: 99 }));
    await assertFails(updateDoc(doc(as('tr1'), 'vehicles', 'dv1'), { number: 'XX00XX0000' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'vehicles', 'dv1'), { attachedTo: deleteField() }));
    await assertFails(updateDoc(doc(as('tr1'), 'vehicles', 'dv1'), { availability: 'available' }), 'detached');
  });

  test('company bid: a transporter offers with an own vehicle and fleetOwnerId; others cannot fake it', async () => {
    await seedAll();
    const ref = (db) => doc(db, 'offers', 'L1_tr1');
    await assertSucceeds(setDoc(ref(as('tr1')), COMPANY_OFFER));
    await assertFails(setDoc(doc(as('driver1'), 'offers', 'L1_driver1'), { ...COMPANY_OFFER, driverId: 'driver1', fleetOwnerId: 'driver1', vehicleId: 'dv1', vehicleNumber: 'KA01CD5678' }), 'a driver is not a transporter');
    await assertFails(setDoc(ref(as('tr1')), { ...COMPANY_OFFER, fleetOwnerId: 'someoneElse' }));
    await assertFails(setDoc(ref(as('tr1')), { ...COMPANY_OFFER, vehicleId: 'dv2', vehicleNumber: 'KA01CD9999' }), 'not attached');
  });

  test('the Verified mark on a bid is true only for an admin-approved transporter', async () => {
    await seedAll();
    const ref = (db) => doc(db, 'offers', 'L1_tr1');
    await assertFails(setDoc(ref(as('tr1')), { ...COMPANY_OFFER, companyVerified: true }), 'not approved yet');
    await seed((db) => updateDoc(doc(db, 'users', 'tr1'), { verified: true, verificationStatus: 'approved' }));
    await assertFails(setDoc(ref(as('tr1')), { ...COMPANY_OFFER, companyVerified: false }), 'only true is allowed');
    await assertSucceeds(setDoc(ref(as('tr1')), { ...COMPANY_OFFER, companyVerified: true }));
    // A plain driver offer cannot carry the mark.
    const plain = { loadId: 'L1', driverId: 'driver1', customerId: 'customer1', vehicleId: 'dv1', vehicleNumber: 'KA01CD5678', vehicleType: '20ft', driverName: 'Ramesh', pricePaise: 2400000, originalPaise: 2400000, status: 'pending' };
    await assertSucceeds(setDoc(doc(as('driver1'), 'offers', 'L1_driver1'), plain));
    await assertFails(setDoc(doc(as('driver2'), 'offers', 'L1_driver2'), { ...plain, driverId: 'driver2', vehicleId: 'dv2', vehicleNumber: 'KA01CD9999', companyVerified: true }));
  });

  test('company bid with an attached vehicle works while the owner is a member', async () => {
    await seedAll();
    await seed((db) => updateDoc(doc(db, 'vehicles', 'dv1'), { attachedTo: 'tr1' }));
    const offer = { ...COMPANY_OFFER, vehicleId: 'dv1', vehicleNumber: 'KA01CD5678' };
    await assertSucceeds(setDoc(doc(as('tr1'), 'offers', 'L1_tr1'), offer));
    await seed((db) => updateDoc(doc(db, 'fleet_members', 'tr1_driver1'), { active: false }));
    await assertFails(setDoc(doc(as('tr1'), 'offers', 'L1_tr1'), offer), 'member left: the attachment is dead');
  });

  const confirmCompany = (db, over = {}, vehicle = 'tv1') => {
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B1'), bookingFor('L1', { driverId: 'tr1', vehicleId: vehicle, vehicleNumber: vehicle === 'tv1' ? 'MH12AB1234' : 'KA01CD5678', fleetOwnerId: 'tr1', offerId: 'L1_tr1', agreedFarePaise: COMPANY_OFFER.pricePaise, ...over }));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'tr1', bookingId: 'B1', matchedAt: serverTimestamp() });
    b.update(doc(db, 'vehicles', vehicle), { availability: 'on_trip' });
    b.update(doc(db, 'offers', 'L1_tr1'), { status: 'confirmed', bookingId: 'B1', updatedAt: serverTimestamp() });
    return b.commit();
  };

  async function seedWonBid() {
    await seedAll();
    await seed((db) => setDoc(doc(db, 'offers', 'L1_tr1'), { ...COMPANY_OFFER, status: 'selected' }));
  }

  test('the selected company bid becomes a booking with fleetOwnerId = the transporter', async () => {
    await seedWonBid();
    await assertFails(confirmCompany(as('tr1'), { fleetOwnerId: 'other' }));
    await assertSucceeds(confirmCompany(as('tr1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'bookings', 'B1')));
    await assertSucceeds(getDoc(doc(as('tr1'), 'bookings', 'B1')));
  });

  async function seedBookingHeld() {
    await seedWonBid();
    await confirmCompany(as('tr1'));
  }

  const assignData = (over = {}) => ({ assignedDriverId: 'driver1', assignedDriverName: 'Ramesh', assignedVehicleId: 'tv1', assignedVehicleNumber: 'MH12AB1234', assignedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });

  test('assign and reassign: only to an active member, with an own or attached vehicle, before pickup', async () => {
    await seedBookingHeld();
    const ref = (db) => doc(db, 'bookings', 'B1');
    await assertFails(updateDoc(ref(as('driver2')), assignData({ assignedDriverId: 'driver2' })), 'a stranger');
    await assertFails(updateDoc(ref(as('tr1')), assignData({ assignedDriverId: 'driver2' })), 'not a member');
    await assertFails(updateDoc(ref(as('tr1')), assignData({ assignedVehicleId: 'dv2', assignedVehicleNumber: 'KA01CD9999' })), 'not the fleet vehicle');
    await assertFails(updateDoc(ref(as('tr1')), assignData({ assignedVehicleNumber: 'WRONG' })));
    await assertFails(updateDoc(ref(as('tr1')), { ...assignData(), status: 'delivered' }), 'nothing else changes');
    await assertSucceeds(updateDoc(ref(as('tr1')), assignData()));
    // The audit line the app writes next to it.
    await assertSucceeds(addDoc(collection(as('tr1'), 'audit_events'), { type: 'assign', actorId: 'tr1', bookingId: 'B1', targetId: 'driver1', data: { vehicleId: 'tv1' }, createdAt: serverTimestamp() }));
    await assertFails(addDoc(collection(as('driver2'), 'audit_events'), { type: 'assign', actorId: 'driver2', bookingId: 'B1', data: {}, createdAt: serverTimestamp() }));
    // Reassign is the same write; after pickup it is refused.
    await seed((db) => setDoc(doc(db, 'fleet_members', 'tr1_driver3'), member({ driverId: 'driver3' })));
    await assertSucceeds(updateDoc(ref(as('tr1')), assignData({ assignedDriverId: 'driver3', assignedDriverName: 'Imran' })));
    await seed((db) => updateDoc(doc(db, 'bookings', 'B1'), { status: 'picked_up' }));
    await assertFails(updateDoc(ref(as('tr1')), assignData()));
  });

  test('the assigned driver reads the booking, chats and moves the trip; nobody else', async () => {
    await seedBookingHeld();
    await seed((db) => updateDoc(doc(db, 'bookings', 'B1'), { assignedDriverId: 'driver1', assignedDriverName: 'Ramesh', assignedVehicleId: 'tv1', assignedVehicleNumber: 'MH12AB1234' }));
    await assertSucceeds(getDoc(doc(as('driver1'), 'bookings', 'B1')));
    await assertFails(getDoc(doc(as('driver2'), 'bookings', 'B1')));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'B1'), { status: 'driver_arriving', 'timeline.driver_arriving': serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'B1'), { assignedDriverId: 'driver1', assignedAt: serverTimestamp(), updatedAt: serverTimestamp() }), 'the driver cannot reassign');
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'B1'), { paymentStatus: 'driver_confirmed' }));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'B1'), { status: 'cancelled' }));
    await assertSucceeds(addDoc(collection(as('driver1'), 'bookings', 'B1', 'messages'), { senderId: 'driver1', text: 'Namaste', flagged: false, createdAt: serverTimestamp() }));
  });

  test('the assigned driver runs the whole trip including delivery with the customer\'s OTP; the load closes', async () => {
    await seedBookingHeld();
    await seed(async (db) => {
      await updateDoc(doc(db, 'bookings', 'B1'), { assignedDriverId: 'driver1', assignedDriverName: 'Ramesh', assignedVehicleId: 'tv1', assignedVehicleNumber: 'MH12AB1234', status: 'unloading' });
      await setDoc(doc(db, 'bookings', 'B1', 'secrets', 'otp'), { pickupOtp: '482913', deliveryOtp: '771204' });
    });
    const d = as('driver1');
    const close = (db, extra) => {
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'B1'), { status: 'delivered', 'timeline.delivered': serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
      b.update(doc(db, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() });
      b.set(doc(db, 'notifications', 'n1'), { userId: 'customer1', type: 'status_changed', message: 'A -> B', relatedId: 'B1', status: 'delivered', read: false, createdAt: serverTimestamp() });
      return b.commit();
    };
    const proof = { receiverName: 'Anil', receiverPhone: '+919811111111', damageNote: '' };
    await assertFails(close(as('driver2'), { deliveryOtp: '771204', deliveryProof: proof }), 'not on this trip');
    await assertFails(close(d, { deliveryOtp: '000000', deliveryProof: proof }), 'wrong OTP');
    await assertSucceeds(close(d, { deliveryOtp: '771204', deliveryProof: proof }));
    // The transporter then frees the vehicle (it is theirs).
    await assertSucceeds(updateDoc(doc(as('tr1'), 'vehicles', 'tv1'), { availability: 'available' }));
  });

  test('the assigned driver cannot touch money, papers or cancel; the holder still can', async () => {
    await seedBookingHeld();
    await seed((db) => updateDoc(doc(db, 'bookings', 'B1'), { assignedDriverId: 'driver1', assignedDriverName: 'Ramesh', assignedVehicleId: 'tv1', assignedVehicleNumber: 'MH12AB1234' }));
    const d = as('driver1');
    await assertFails(updateDoc(doc(d, 'bookings', 'B1'), { ewayBillNo: '123456789012', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(d, 'bookings', 'B1'), { paymentStatus: 'driver_confirmed', paymentConfirmedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(d, 'bookings', 'B1'), { advancePaise: 1000, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(d, 'bookings', 'B1'), { driverId: 'driver1' }));
    await assertFails(updateDoc(doc(d, 'bookings', 'B1'), { vehicleId: 'dv1' }));
    await assertSucceeds(updateDoc(doc(as('tr1'), 'bookings', 'B1'), { ewayBillNo: '123456789012', updatedAt: serverTimestamp() }));
  });

  test('assigning tells the driver; the assigned driver tells the holder; only those two kinds of notice', async () => {
    await seedBookingHeld();
    const note = (type, userId) => ({ userId, type, message: 'Delhi -> Jaipur', relatedId: 'B1', read: false, createdAt: serverTimestamp() });
    // The notice rides with the assignment (the rules read the booking after the write).
    const t = as('tr1');
    const b = writeBatch(t);
    b.update(doc(t, 'bookings', 'B1'), assignData());
    b.set(doc(t, 'notifications', 'n1'), note('trip_assigned', 'driver1'));
    await assertSucceeds(b.commit());
    await assertFails(setDoc(doc(as('tr1'), 'notifications', 'n2'), note('trip_assigned', 'driver2')), 'not on this booking');
    await assertFails(setDoc(doc(as('driver2'), 'notifications', 'n3'), note('trip_assigned', 'driver1')), 'outsider');
    await assertSucceeds(setDoc(doc(as('driver1'), 'notifications', 'n4'), { ...note('status_changed', 'tr1'), status: 'driver_arriving' }));
    await assertSucceeds(setDoc(doc(as('customer1'), 'notifications', 'n5'), note('missed_call', 'driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'notifications', 'n6'), note('made_up_type', 'driver1')));
  });

  test('the books: only the transporter, only for their own booking, integer paise', async () => {
    await seedBookingHeld();
    const line = (over = {}) => ({ ownerId: 'tr1', bookingId: 'B1', partyId: 'customer1', partyName: 'Acme', revenuePaise: 2400000, driverPayPaise: 1800000, otherCostPaise: 100000, receivedPaise: 0, updatedAt: serverTimestamp(), ...over });
    const ref = (db) => doc(db, 'transporter_accounts', 'B1');
    await assertFails(setDoc(ref(as('driver1')), line({ ownerId: 'driver1' })));
    await assertFails(setDoc(ref(as('tr1')), line({ revenuePaise: 10.5 })));
    await assertFails(setDoc(ref(as('tr1')), line({ driverPayPaise: -1 })));
    await assertFails(setDoc(ref(as('tr1')), line({ partyId: 'someone' })));
    await assertSucceeds(setDoc(ref(as('tr1')), line()));
    await assertSucceeds(getDoc(ref(as('tr1'))));
    await assertFails(getDoc(ref(as('customer1'))));
    await assertFails(getDoc(ref(as('driver1'))));
    await assertFails(getDoc(ref(asAdmin())), 'private books');
    await assertSucceeds(updateDoc(ref(as('tr1')), { receivedPaise: 500000, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(as('tr1')), { ownerId: 'x', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(as('tr1')), { bookingId: 'B2', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(as('customer1'))));
    await assertFails(deleteDoc(ref(as('tr2'))));
    await assertSucceeds(deleteDoc(ref(as('tr1'))), 'the owner may delete their books');
  });

  test('a transporter posts a load with the "posted by transporter" tag; others cannot use it', async () => {
    await seedAll();
    const load = (uid, over = {}) => ({ ...LOAD, shipperId: uid, ...over });
    await assertSucceeds(setDoc(doc(as('tr1'), 'loads', 'T1'), load('tr1', { postedByRole: 'fleet' })));
    await assertSucceeds(setDoc(doc(as('tr1'), 'loads', 'T2'), load('tr1')));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'T3'), load('customer1', { postedByRole: 'fleet' })));
    await assertFails(setDoc(doc(as('tr1'), 'loads', 'T4'), load('tr1', { postedByRole: 'admin' })));
  });
});

describe('transporter security (Phase 2)', () => {
  const asPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
  const member = (over = {}) => ({ ownerId: 'tr1', ownerName: 'Sunil', driverId: 'driver1', driverName: 'Ramesh', driverPhone: '+919876543210', active: true, createdAt: Timestamp.now(), ...over });
  const BOOKING = { fleetOwnerId: 'tr1', driverId: 'tr1', vehicleId: 'tv1', vehicleNumber: 'MH12AB1234', driverName: 'Sharma Roadlines', driverPhone: '' };

  const seedAll = () =>
    seed(async (db) => {
      for (const [uid, role] of [['tr1', 'fleet'], ['tr2', 'fleet'], ['driver1', 'driver'], ['customer1', 'customer']]) {
        await setDoc(doc(db, 'users', uid), { role, selectedRole: role, name: uid, phone: '+91990000000' + uid.length, riskTier: 'normal' });
      }
      await setDoc(doc(db, 'fleet_members', 'tr1_driver1'), member());
      await setDoc(doc(db, 'fleet_invites', 'tr1_919876543210'), { ownerId: 'tr1', ownerName: 'Sunil', phone: '+919876543210', status: 'accepted', createdAt: Timestamp.now() });
      await setDoc(doc(db, 'vehicles', 'tv1'), { ...VEHICLE, ownerId: 'tr1' });
      await setDoc(doc(db, 'vehicles', 'tv2'), { ...VEHICLE, ownerId: 'tr2', number: 'KA01CD5678' });
      await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, status: 'matched', driverId: 'tr1', bookingId: 'B1' });
      await setDoc(doc(db, 'bookings', 'B1'), { ...bookingFor('L1'), ...BOOKING, status: 'accepted', timeline: {} });
      await setDoc(doc(db, 'transporter_accounts', 'B1'), { ownerId: 'tr1', bookingId: 'B1', partyId: 'customer1', partyName: 'Acme', revenuePaise: 1, driverPayPaise: 0, otherCostPaise: 0, receivedPaise: 0, updatedAt: Timestamp.now() });
    });

  test('a transporter cannot read or write the admins collection or make themselves admin', async () => {
    await seedAll();
    const t = as('tr1');
    await assertFails(getDoc(doc(t, 'admins', 'admin1')));
    await assertFails(getDocs(collection(t, 'admins')));
    await assertFails(setDoc(doc(t, 'admins', 'tr1'), { createdBy: 'me' }));
    await assertFails(updateDoc(doc(t, 'admins', 'admin1'), { role: 'support' }));
    await assertFails(deleteDoc(doc(t, 'admins', 'admin1')));
    // Admin-only actions stay refused.
    await assertFails(updateDoc(doc(t, 'users', 'driver1'), { verified: true, verificationStatus: 'approved' }));
    await assertFails(updateDoc(doc(t, 'users', 'tr1'), { isAdmin: true, verified: true }));
    await assertFails(setDoc(doc(t, 'config', 'features'), { pilotMode: false, flags: {} }));
    await assertFails(addDoc(collection(t, 'audit_events'), { type: 'verification', actorId: 'tr1', data: {}, createdAt: serverTimestamp() }));
    await assertFails(getDocs(collection(t, 'audit_events')));
    await assertSucceeds(getDoc(doc(as('admin1'), 'admins', 'admin1')));
  });

  test('admin comes only from admins/{uid}: a user field or a custom claim name changes nothing', async () => {
    await seedAll();
    const fake = env.authenticatedContext('tr1', { admin: true, role: 'admin' }).firestore();
    await assertFails(getDocs(collection(fake, 'audit_events')));
    await assertFails(updateDoc(doc(fake, 'users', 'driver1'), { verified: true, verificationStatus: 'approved' }));
    await assertSucceeds(getDocs(collection(asAdmin(), 'audit_events')));
  });

  test('another transporter cannot read the books, members, invites or bookings of tr1', async () => {
    await seedAll();
    const t2 = as('tr2');
    await assertFails(getDoc(doc(t2, 'transporter_accounts', 'B1')));
    await assertFails(getDocs(query(collection(t2, 'transporter_accounts'), where('ownerId', '==', 'tr1'))));
    await assertFails(getDoc(doc(t2, 'fleet_members', 'tr1_driver1')));
    await assertFails(getDocs(query(collection(t2, 'fleet_members'), where('ownerId', '==', 'tr1'))));
    await assertFails(getDoc(doc(t2, 'fleet_invites', 'tr1_919876543210')));
    await assertFails(getDoc(doc(t2, 'bookings', 'B1')));
    await assertFails(getDocs(query(collection(t2, 'bookings'), where('fleetOwnerId', '==', 'tr1'))));
    await assertSucceeds(getDoc(doc(as('tr1'), 'bookings', 'B1')));
  });

  test('another transporter cannot write on tr1\'s booking, vehicles or fleet', async () => {
    await seedAll();
    const t2 = as('tr2');
    const assign = { assignedDriverId: 'driver1', assignedDriverName: 'Ramesh', assignedVehicleId: 'tv2', assignedVehicleNumber: 'KA01CD5678', assignedAt: serverTimestamp(), updatedAt: serverTimestamp() };
    await assertFails(updateDoc(doc(t2, 'bookings', 'B1'), assign));
    await assertFails(updateDoc(doc(t2, 'bookings', 'B1'), { fleetOwnerId: 'tr2' }));
    await assertFails(updateDoc(doc(t2, 'vehicles', 'tv1'), { assignedDriverId: 'driver1' }));
    await assertFails(updateDoc(doc(t2, 'vehicles', 'tv1'), { availability: 'on_trip' }));
    await assertFails(updateDoc(doc(t2, 'vehicles', 'tv1'), { attachedTo: 'tr2' }));
    await assertFails(updateDoc(doc(t2, 'fleet_members', 'tr1_driver1'), { active: false, endedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(t2, 'transporter_accounts', 'B1'), { ownerId: 'tr2', bookingId: 'B1', partyId: 'customer1', partyName: 'x', revenuePaise: 1, driverPayPaise: 0, otherCostPaise: 0, receivedPaise: 0, updatedAt: serverTimestamp() }));
    // Not even the owner of tr1's books can be impersonated through the audit trail.
    await assertFails(addDoc(collection(t2, 'audit_events'), { type: 'assign', actorId: 'tr2', bookingId: 'B1', data: {}, createdAt: serverTimestamp() }));
  });

  test('a transporter cannot read customer or driver profiles, the books of others, or list users', async () => {
    await seedAll();
    const t = as('tr1');
    await assertFails(getDoc(doc(t, 'users', 'customer1')));
    await assertFails(getDoc(doc(t, 'users', 'driver1')));
    await assertFails(getDoc(doc(t, 'users', 'tr2')));
    await assertFails(getDocs(collection(t, 'users')));
    await assertFails(getDocs(query(collection(t, 'users'), where('role', '==', 'driver'))));
    await assertSucceeds(getDoc(doc(t, 'users', 'tr1')));
    // The customer's and driver's private lists.
    await seed((db) => setDoc(doc(db, 'users', 'customer1', 'saved_places', 'p1'), { label: 'home', name: 'Home', address: 'Delhi' }));
    await assertFails(getDoc(doc(t, 'users', 'customer1', 'saved_places', 'p1')));
  });

  test('customer and driver cannot read the transporter\'s books, invites or members', async () => {
    await seedAll();
    for (const who of ['customer1', 'driver2']) {
      await assertFails(getDoc(doc(as(who), 'transporter_accounts', 'B1')));
      await assertFails(getDoc(doc(as(who), 'fleet_members', 'tr1_driver1')));
    }
    await assertFails(getDoc(doc(as('customer1'), 'fleet_invites', 'tr1_919876543210')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'fleet_members', 'tr1_driver1')), 'the member sees their own membership');
  });

  test('role, fleetOwnerId, riskTier, plan, wallet and verification cannot be changed by the transporter', async () => {
    await seedAll();
    const ref = () => doc(as('tr1'), 'users', 'tr1');
    await assertFails(updateDoc(ref(), { role: 'customer' }));
    await assertFails(updateDoc(ref(), { role: 'driver', selectedRole: 'driver' }));
    await assertFails(updateDoc(ref(), { selectedRole: 'customer' }));
    await assertFails(updateDoc(ref(), { riskTier: 'restricted' }));
    await assertFails(updateDoc(ref(), { plan: 'pro', planUntil: Timestamp.fromDate(new Date('2030-01-01')) }));
    await assertFails(updateDoc(ref(), { verified: true, verificationStatus: 'approved' }));
    await assertFails(updateDoc(ref(), { reviewFlag: { kind: 'other', note: 'x', by: 'tr1', at: serverTimestamp() } }));
    await assertFails(updateDoc(ref(), { cancelCount: 5 }));
    await assertFails(updateDoc(ref(), { docOverrideUntil: Timestamp.fromDate(new Date('2030-01-01')) }));
    // Allowed: a normal profile edit.
    await assertSucceeds(updateDoc(ref(), { name: 'New Name' }));
  });

  test('the booking\'s fleetOwnerId cannot be changed or forged', async () => {
    await seedAll();
    const t = as('tr1');
    await assertFails(updateDoc(doc(t, 'bookings', 'B1'), { fleetOwnerId: 'tr2' }));
    await assertFails(updateDoc(doc(t, 'bookings', 'B1'), { fleetOwnerId: deleteField() }));
    await assertFails(updateDoc(doc(t, 'bookings', 'B1'), { driverId: 'tr2' }));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'B1'), { fleetOwnerId: 'customer1' }));
    // A plain driver cannot claim a fleetOwnerId on their own vehicle, nor a customer-role user.
    await seed(async (db) => {
      await setDoc(doc(db, 'loads', 'L2'), { ...LOAD });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L2', 'driver1', { vehicleId: 'v1', fleetOwnerId: 'driver1' }));
    await assertFails(acceptBatch(as('driver1'), 'L2', 'driver1', { vehicleId: 'v1', fleetOwnerId: 'tr1' }));
  });

  test('the wallet: a transporter cannot write ledger lines for a trip they do not hold or that is not paid', async () => {
    await seedAll();
    const line = (type, amountPaise, over = {}) => ({ driverId: 'tr1', bookingId: 'B1', type, amountPaise, createdAt: serverTimestamp(), ...over });
    await assertFails(setDoc(doc(as('tr1'), 'ledger', 'B1_trip_earning'), line('trip_earning', 999999)), 'not paid yet');
    await assertFails(setDoc(doc(as('tr2'), 'ledger', 'B1_trip_earning'), line('trip_earning', 100, { driverId: 'tr2' })), 'not their booking');
    await assertFails(getDoc(doc(as('tr2'), 'ledger', 'B1_trip_earning')));
  });

  test('the company profile cannot carry extra or oversize fields', async () => {
    await seedAll();
    const ref = () => doc(as('tr1'), 'users', 'tr1');
    await assertFails(updateDoc(ref(), { fleet: { pan: 'ABCDE1234F', walletPaise: 1000000 } }));
    await assertFails(updateDoc(ref(), { fleet: { pan: 'ABCDE1234F', officeCity: 'x'.repeat(61) } }));
    await assertFails(updateDoc(ref(), { fleet: { pan: 'ABCDE1234F', vehicleTypes: Array(13).fill('20ft') } }));
    await assertFails(updateDoc(ref(), { fleet: 'ABCDE1234F' }));
    await assertSucceeds(updateDoc(ref(), { fleet: { pan: 'ABCDE1234F', officeCity: 'Indore', vehicleCount: 5 } }));
  });

  test('an attached vehicle cannot be bid with by a transporter the owner never joined', async () => {
    await seedAll();
    await seed((db) => setDoc(doc(db, 'vehicles', 'dv1'), { ...VEHICLE, ownerId: 'driver1', number: 'KA01CD0001', attachedTo: 'tr2' }));
    const offer = { loadId: 'L9', driverId: 'tr2', customerId: 'customer1', vehicleId: 'dv1', vehicleNumber: 'KA01CD0001', vehicleType: '20ft', driverName: 'Co', pricePaise: 2400000, originalPaise: 2400000, status: 'pending', fleetOwnerId: 'tr2' };
    await seed((db) => setDoc(doc(db, 'loads', 'L9'), LOAD));
    await assertFails(setDoc(doc(as('tr2'), 'offers', 'L9_tr2'), offer), 'driver1 is not a member of tr2');
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

  test('driver shares live location only while on the way to the pickup or in transit', async () => {
    const loc = () => ({ lastKnownLocation: new GeoPoint(28.6, 77.2), locationUpdatedAt: serverTimestamp() });
    await seedBooking('loading');
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'driver_arriving' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { ...loc(), status: 'in_transit' }));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'picked_up' }));
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

  test('support hides an abusive comment (MASTER-5 Task 33): the stars stay, nothing else changes', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
      await setDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
      await setDoc(doc(db, 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 1, comment: 'rude words' }));
    });
    const hide = (db, extra = {}) => updateDoc(doc(db, 'ratings', 'L1_customer1'), { comment: '', moderated: true, moderatedAt: serverTimestamp(), ...extra });
    const staff = (uid) => env.authenticatedContext(uid).firestore();
    await assertFails(hide(as('customer1')));
    await assertFails(hide(as('driver1')));
    await assertFails(hide(staff('ops1')));
    await assertFails(hide(staff('sup1'), { stars: 5 }));
    await assertFails(hide(staff('sup1'), { comment: 'edited instead' }));
    await assertFails(hide(staff('sup1'), { moderated: false }));
    await assertFails(deleteDoc(doc(staff('sup1'), 'ratings', 'L1_customer1')));
    await assertSucceeds(hide(staff('sup1')));
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

describe('config/app (force update, maintenance, flags)', () => {
  const APP = { minVersionCode: 5, maintenance: false, maintenanceMessage: '', flags: { surge: true } };

  test('everyone signed in reads it, only a super admin writes it', async () => {
    await seed((db) => setDoc(doc(db, 'config', 'app'), APP));
    await assertSucceeds(getDoc(doc(as('driver1'), 'config', 'app')));
    await assertFails(getDoc(doc(anon(), 'config', 'app')));
    await assertFails(setDoc(doc(as('driver1'), 'config', 'app'), APP));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'app'), { ...APP, minVersionCode: 6 }));
    await assertFails(deleteDoc(doc(asAdmin(), 'config', 'app')));
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

describe('private chat and call (Task 68)', () => {
  const msg = (sender, text = 'Namaste', extra = {}) => ({ senderId: sender, text, flagged: false, createdAt: serverTimestamp(), ...extra });
  const msgs = (db) => collection(db, 'bookings', 'L1', 'messages');
  const hours = (h) => Timestamp.fromMillis(Date.now() + h * 3600000);
  const seedUsers = (extra = {}) =>
    seed(async (db) => {
      await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', selectedRole: 'customer', ...extra.customer1 });
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', ...extra.driver1 });
    });

  test('a message with a mobile number, a UPI id or any "@" is refused even from a modified app', async () => {
    await seedBooking();
    const t = (text) => addDoc(msgs(as('customer1')), msg('customer1', text));
    await assertSucceeds(t('Load is 12000 kg, 20 ft'));
    await assertSucceeds(t('Invoice 1234567890123 ready'));
    await assertSucceeds(t('Vehicle MH12AB1234 at gate 4'));
    await assertFails(t('call 9876543210'));
    await assertFails(t('+91 9876543210 pe baat karo'));
    await assertFails(t('+919876543210'));
    await assertFails(t('09876543210'));
    await assertFails(t('mera upi ramesh@ybl'));
    await assertFails(t('mail a@b.com'));
    await assertFails(t('line one\n9876543210\nline three'));
  });

  test('a suspended sender cannot send; the other party can; the block ends by itself', async () => {
    await seedBooking();
    await seedUsers({ customer1: { chatBlockedUntil: hours(5) } });
    await assertFails(addDoc(msgs(as('customer1')), msg('customer1')));
    await assertSucceeds(addDoc(msgs(as('driver1')), msg('driver1')));
    await seedUsers({ customer1: { chatBlockedUntil: hours(-1) } });
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')));
  });

  // The two writes the app makes when it blocks a message (CommGuard.recordViolation).
  const violation = (uid, seq, over = {}) => ({ userId: uid, bookingId: 'L1', kind: 'phone', excerpt: 'call 98xxx', createdAt: serverTimestamp(), ...over });
  const strike = (db, uid, strikes, seq, userOver = {}, vOver = {}) => {
    const b = writeBatch(db);
    b.set(doc(db, 'violations', `${uid}_${seq}`), violation(uid, seq, vOver));
    b.update(doc(db, 'users', uid), { chatStrikes: strikes, chatSeq: seq, chatStrikeAt: serverTimestamp(), updatedAt: serverTimestamp(), ...userOver });
    return b.commit();
  };

  test('strike 1 and 2 warn only: violation + strikes in one batch, nothing else changes', async () => {
    await seedBooking();
    await seedUsers();
    await assertSucceeds(strike(as('customer1'), 'customer1', 1, 1));
    await assertSucceeds(strike(as('customer1'), 'customer1', 2, 2));
    const u = (await getDoc(doc(asAdmin(), 'users', 'customer1'))).data();
    assert.equal(u.chatStrikes, 2);
    assert.equal(u.chatBlockedUntil, undefined);
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')), 'still allowed to chat');
  });

  test('the strike is all-or-nothing and goes up by exactly one', async () => {
    await seedBooking();
    await seedUsers();
    const c = as('customer1');
    await assertFails(strike(c, 'customer1', 2, 1), 'two strikes at once');
    await assertFails(strike(c, 'customer1', 1, 2), 'wrong sequence');
    await assertFails(strike(c, 'customer1', 1, 1, {}, { userId: 'driver1' }));
    await assertFails(strike(c, 'customer1', 1, 1, {}, { kind: 'rude' }));
    await assertFails(strike(c, 'customer1', 1, 1, {}, { bookingId: 'nope' }));
    await assertFails(strike(c, 'customer1', 1, 1, {}, { excerpt: 'x'.repeat(121) }));
    // A violation alone, or the user counter alone, is refused.
    await assertFails(setDoc(doc(c, 'violations', 'customer1_1'), violation('customer1', 1)));
    await assertFails(updateDoc(doc(c, 'users', 'customer1'), { chatStrikes: 1, chatSeq: 1, chatStrikeAt: serverTimestamp() }));
    // Nobody can strike someone else.
    await assertFails(strike(as('driver1'), 'customer1', 1, 1));
    await assertFails(updateDoc(doc(as('driver1'), 'users', 'customer1'), { chatStrikes: 1 }));
    await assertSucceeds(strike(c, 'customer1', 1, 1));
    await assertFails(strike(c, 'customer1', 2, 1), 'the same violation id twice');
  });

  test('strike 3 blocks for 24 hours, 4 for 3 days, 5 for 7 days with an admin review', async () => {
    await seedBooking();
    await seedUsers({ customer1: { chatStrikes: 2, chatSeq: 2, chatStrikeAt: Timestamp.now() } });
    const c = as('customer1');
    await assertFails(strike(c, 'customer1', 3, 3), 'no block written');
    await assertFails(strike(c, 'customer1', 3, 3, { chatBlockedUntil: hours(2) }), 'block too short');
    await assertSucceeds(strike(c, 'customer1', 3, 3, { chatBlockedUntil: hours(24) }));
    await assertFails(addDoc(msgs(c), msg('customer1')), 'now blocked');
    await assertSucceeds(strike(c, 'customer1', 4, 4, { chatBlockedUntil: hours(72) }));
    await assertFails(strike(c, 'customer1', 5, 5, { chatBlockedUntil: hours(168) }), 'strike 5 needs the review flag');
    await assertFails(strike(c, 'customer1', 5, 5, { chatBlockedUntil: hours(72), chatReview: true }), 'strike 5 needs 7 days');
    await assertSucceeds(strike(c, 'customer1', 5, 5, { chatBlockedUntil: hours(168), chatReview: true }));
    const u = (await getDoc(doc(asAdmin(), 'users', 'customer1'))).data();
    assert.equal(u.chatReview, true);
  });

  test('a suspended person cannot lift the block, lower the count or skip the clock', async () => {
    await seedBooking();
    await seedUsers({ customer1: { chatStrikes: 3, chatSeq: 3, chatStrikeAt: Timestamp.now(), chatBlockedUntil: hours(20) } });
    const ref = () => doc(as('customer1'), 'users', 'customer1');
    await assertFails(updateDoc(ref(), { chatBlockedUntil: deleteField() }));
    await assertFails(updateDoc(ref(), { chatBlockedUntil: hours(-1) }));
    await assertFails(updateDoc(ref(), { chatBlockedUntil: hours(1) }));
    await assertFails(updateDoc(ref(), { chatStrikes: 0 }), 'no decay before 30 clean days');
    await assertFails(updateDoc(ref(), { chatStrikes: 0, chatStrikeAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(), { chatReview: false }));
    await assertSucceeds(updateDoc(ref(), { name: 'New' }), 'other profile edits are fine');
  });

  test('30 clean days take one strike off, once per 30 days', async () => {
    await seedBooking();
    const old = Timestamp.fromMillis(Date.now() - 31 * 86400000);
    await seedUsers({ customer1: { chatStrikes: 2, chatSeq: 2, chatStrikeAt: old }, driver1: { chatStrikes: 2, chatSeq: 2, chatStrikeAt: Timestamp.now() } });
    await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { chatStrikes: 1, chatStrikeAt: serverTimestamp() }), 'not 30 days yet');
    await assertFails(updateDoc(doc(as('customer1'), 'users', 'customer1'), { chatStrikes: 0, chatStrikeAt: serverTimestamp() }), 'one at a time');
    await assertFails(updateDoc(doc(as('customer1'), 'users', 'customer1'), { chatStrikes: 1 }), 'the clock must restart');
    await assertSucceeds(updateDoc(doc(as('customer1'), 'users', 'customer1'), { chatStrikes: 1, chatStrikeAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('customer1'), 'users', 'customer1'), { chatStrikes: 0, chatStrikeAt: serverTimestamp() }), 'next one only after another 30 days');
  });

  test('violations are read by their owner and admins; never changed', async () => {
    await seedBooking();
    await seedUsers();
    await strike(as('customer1'), 'customer1', 1, 1);
    await assertSucceeds(getDoc(doc(as('customer1'), 'violations', 'customer1_1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'violations', 'customer1_1')));
    await assertFails(getDoc(doc(as('driver1'), 'violations', 'customer1_1')));
    await assertFails(updateDoc(doc(as('customer1'), 'violations', 'customer1_1'), { excerpt: 'clean' }));
    await assertFails(deleteDoc(doc(as('customer1'), 'violations', 'customer1_1')));
    await assertFails(updateDoc(doc(asAdmin(), 'violations', 'customer1_1'), { excerpt: 'clean' }));
  });

  test('admins extend or lift a suspension; users cannot', async () => {
    await seedBooking();
    await seedUsers({ customer1: { chatStrikes: 3, chatSeq: 3, chatStrikeAt: Timestamp.now(), chatBlockedUntil: hours(20) } });
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'customer1'), { chatBlockedUntil: hours(24 * 30), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'customer1'), { chatBlockedUntil: deleteField(), chatStrikes: 0, chatReview: false, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'customer1'), { chatBlockedUntil: hours(24 * 400) }), 'too long');
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'customer1'), { chatStrikes: 1, role: 'driver' }));
    await assertFails(updateDoc(doc(as('driver1'), 'users', 'customer1'), { chatBlockedUntil: deleteField() }));
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')), 'chat works again');
  });

  test('a new account cannot start with chat fields set', async () => {
    await assertFails(setDoc(doc(as('n1'), 'users', 'n1'), { role: 'customer', selectedRole: 'customer', chatStrikes: 0 }));
    await assertFails(setDoc(doc(as('n2'), 'users', 'n2'), { role: 'customer', selectedRole: 'customer', chatBlockedUntil: hours(-5) }));
    await assertSucceeds(setDoc(doc(as('n3'), 'users', 'n3'), { role: 'customer', selectedRole: 'customer' }));
  });

  test('reports: "asked for my number" and "sent a number" are accepted reasons', async () => {
    await seedBooking();
    const rep = (reason) => ({ reporterId: 'customer1', reportedId: 'driver1', bookingId: 'L1', reason, details: '', status: 'open', createdAt: serverTimestamp() });
    await assertSucceeds(setDoc(doc(as('customer1'), 'reports', 'r1'), rep('asked_number')));
    await assertSucceeds(setDoc(doc(as('customer1'), 'reports', 'r2'), rep('sent_number')));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r3'), rep('rude')));
  });

  describe('calls', () => {
    const SDP = 'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
    const call = (over = {}) => ({
      bookingId: 'L1', callerId: 'customer1', calleeId: 'driver1', callerName: 'Anil', vehicleNumber: 'MH12AB1234', status: 'ringing',
      offer: { type: 'offer', sdp: SDP }, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over,
    });
    const ring = (db = as('customer1'), id = 'c1', over = {}) => setDoc(doc(db, 'calls', id), call(over));

    test('only the two people of a confirmed booking can ring each other', async () => {
      await seedBooking();
      await assertSucceeds(ring());
      await assertFails(ring(as('driver2'), 'c2', { callerId: 'driver2' }), 'not a party');
      await assertFails(ring(as('customer1'), 'c3', { calleeId: 'driver2' }), 'callee not a party');
      await assertFails(ring(as('customer1'), 'c4', { calleeId: 'customer1' }), 'a call to yourself');
      await assertFails(ring(as('customer1'), 'c5', { callerId: 'driver1' }), 'not your call');
      await assertFails(ring(as('customer1'), 'c6', { status: 'accepted' }));
      await assertFails(ring(as('customer1'), 'c7', { offer: { type: 'offer', sdp: 'x' } }), 'tiny sdp');
      await assertFails(ring(as('customer1'), 'c8', { offer: { type: 'offer', sdp: SDP.padEnd(13000, 'a') } }), 'huge sdp');
      await assertFails(ring(as('customer1'), 'c9', { phone: '+919876543210' }), 'no extra fields, no phone number');
      await assertFails(ring(as('customer1'), 'c10', { callerName: 'x'.repeat(61) }));
    });

    test('the call record carries an expireAt for the clean-up policy (MASTER-5 Task 7), within a year and a bit', async () => {
      await seedBooking();
      const days = (n) => Timestamp.fromMillis(Date.now() + n * 86400000);
      await assertSucceeds(ring(as('customer1'), 'e1', { expireAt: days(365) }));
      await assertFails(ring(as('customer1'), 'e2', { expireAt: days(2000) }), 'too far ahead');
      await assertFails(ring(as('customer1'), 'e3', { expireAt: 'never' }), 'not a time');
    });

    test('no call on a finished or cancelled booking, nor while suspended', async () => {
      await seedBooking('delivered');
      await assertFails(ring());
      await seedBooking('cancelled');
      await assertFails(ring());
      await seedBooking('in_transit');
      await assertSucceeds(ring());
      await seedUsers({ customer1: { chatBlockedUntil: hours(10) } });
      await assertFails(ring(as('customer1'), 'c2'));
      await assertSucceeds(ring(as('driver1'), 'c3', { callerId: 'driver1', calleeId: 'customer1' }), 'the other person is not suspended');
    });

    test('answer, decline, cancel and end follow the order; outsiders read nothing', async () => {
      await seedBooking();
      await ring();
      const ans = { status: 'accepted', answer: { type: 'answer', sdp: SDP }, updatedAt: serverTimestamp() };
      await assertFails(updateDoc(doc(as('customer1'), 'calls', 'c1'), ans), 'the caller cannot answer');
      await assertFails(updateDoc(doc(as('driver2'), 'calls', 'c1'), ans), 'outsider');
      await assertFails(getDoc(doc(as('driver2'), 'calls', 'c1')));
      await assertFails(updateDoc(doc(as('driver1'), 'calls', 'c1'), { ...ans, answer: { type: 'offer', sdp: SDP } }));
      await assertFails(updateDoc(doc(as('driver1'), 'calls', 'c1'), { ...ans, extra: 1 }));
      await assertSucceeds(updateDoc(doc(as('driver1'), 'calls', 'c1'), ans));
      await assertFails(updateDoc(doc(as('driver1'), 'calls', 'c1'), { status: 'declined', updatedAt: serverTimestamp() }), 'already answered');
      await assertSucceeds(updateDoc(doc(as('customer1'), 'calls', 'c1'), { status: 'ended', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('customer1'), 'calls', 'c1'), { status: 'accepted', updatedAt: serverTimestamp() }), 'ended stays ended');
      await assertFails(deleteDoc(doc(as('customer1'), 'calls', 'c1')));
      // decline and cancel
      await ring(as('customer1'), 'c2');
      await assertSucceeds(updateDoc(doc(as('driver1'), 'calls', 'c2'), { status: 'declined', updatedAt: serverTimestamp() }));
      await ring(as('customer1'), 'c3');
      await assertFails(updateDoc(doc(as('driver1'), 'calls', 'c3'), { status: 'cancelled', updatedAt: serverTimestamp() }), 'only the caller cancels');
      await assertSucceeds(updateDoc(doc(as('customer1'), 'calls', 'c3'), { status: 'cancelled', updatedAt: serverTimestamp() }));
    });

    test('at most 20 calls an hour per person; a call needs its bump', async () => {
      await seedBooking('in_transit');
      const ringRaw = (id, bump) => {
        const db = as('customer1');
        const b = rawWriteBatch(db);
        b.set(doc(db, 'calls', id), call());
        if (bump) b.set(doc(db, 'rate_limits', 'customer1_call'), bump);
        return b.commit();
      };
      await assertFails(ringRaw('c1', null), 'no bump');
      await assertSucceeds(ringRaw('c1', { count: 1, windowStart: serverTimestamp(), last: 'c1' }));
      await seed((db) => rawSetDoc(doc(db, 'rate_limits', 'customer1_call'), { count: 20, windowStart: Timestamp.fromMillis(Date.now() - 600000), last: 'x' }));
      const start = (await getDoc(doc(as('customer1'), 'rate_limits', 'customer1_call'))).data().windowStart;
      await assertFails(ringRaw('c2', { count: 21, windowStart: start, last: 'c2' }), 'the 21st call');
    });

    test('network candidates: only the two people, only while the call is live, small', async () => {
      await seedBooking();
      await ring();
      const cand = (uid, over = {}) => ({ from: uid, candidate: 'candidate:1 1 UDP 2122 10.0.0.1 5000 typ host', sdpMid: '0', sdpMLineIndex: 0, createdAt: serverTimestamp(), ...over });
      const col = (db) => collection(db, 'calls', 'c1', 'candidates');
      await assertSucceeds(addDoc(col(as('customer1')), cand('customer1')));
      await assertSucceeds(addDoc(col(as('driver1')), cand('driver1')));
      await assertFails(addDoc(col(as('driver1')), cand('customer1')), 'from must be you');
      await assertFails(addDoc(col(as('driver2')), cand('driver2')));
      await assertFails(addDoc(col(as('customer1')), cand('customer1', { candidate: 'x'.repeat(1001) })));
      await assertFails(getDocs(col(as('driver2'))));
      await assertSucceeds(getDocs(col(as('driver1'))));
      await seed((db) => updateDoc(doc(db, 'calls', 'c1'), { status: 'ended' }));
      await assertFails(addDoc(col(as('customer1')), cand('customer1')), 'call is over');
    });

    test('the queries of "Download my data" are allowed for the owner', async () => {
      await seedBooking('in_transit');
      await seed(async (db) => {
        await setDoc(doc(db, 'calls', 'c1'), { ...call(), createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
        await setDoc(doc(db, 'violations', 'customer1_1'), { userId: 'customer1', bookingId: 'L1', kind: 'phone', excerpt: 'x', createdAt: Timestamp.now() });
        await setDoc(doc(db, 'bookings', 'A1'), { ...bookingFor('L1'), assignedDriverId: 'driver1', fleetOwnerId: 'driver1' });
      });
      const c = as('customer1');
      await assertSucceeds(getDocs(query(collection(c, 'calls'), where('callerId', '==', 'customer1'))));
      await assertSucceeds(getDocs(query(collection(as('driver1'), 'calls'), where('calleeId', '==', 'driver1'))));
      await assertSucceeds(getDocs(query(collection(c, 'violations'), where('userId', '==', 'customer1'))));
      await assertSucceeds(getDocs(query(collection(as('driver1'), 'bookings'), where('assignedDriverId', '==', 'driver1'))));
      await assertSucceeds(getDocs(query(collection(as('driver1'), 'fleet_members'), where('driverId', '==', 'driver1'))));
      // The incoming-call listener and the admin lists.
      await assertSucceeds(getDocs(query(collection(as('driver1'), 'calls'), where('calleeId', '==', 'driver1'), where('status', '==', 'ringing'))));
      await assertSucceeds(getDocs(query(collection(asAdmin(), 'violations'), orderBy('createdAt', 'desc'), limit(100))));
      await assertSucceeds(getDocs(query(collection(as('driver1'), 'bookings'), where('fleetOwnerId', '==', 'driver1'))));
      await assertFails(getDocs(query(collection(c, 'calls'), where('callerId', '==', 'driver1'))), 'not someone else\'s');
      await assertFails(getDocs(collection(c, 'violations')), 'not the whole list');
    });

    test('admins read call metadata; other people do not', async () => {
      await seedBooking();
      await ring();
      await assertSucceeds(getDoc(doc(asAdmin(), 'calls', 'c1')));
      await assertFails(getDoc(doc(as('customer2'), 'calls', 'c1')));
    });
  });

  describe('admin review of a chat and number views', () => {
    test('an admin reads a chat only after opening a review that rests on a report or a dispute', async () => {
      await seedBooking();
      await seed((db) => setDoc(doc(db, 'bookings', 'L1', 'messages', 'm1'), msg('customer1', 'Namaste', { createdAt: Timestamp.now() })));
      await assertFails(getDocs(msgs(asAdmin())), 'no review yet');
      const review = (extra) => ({ by: 'admin1', createdAt: serverTimestamp(), ...extra });
      await assertFails(setDoc(doc(asAdmin(), 'chat_reviews', 'L1'), review({ reportId: 'nope' })));
      await assertFails(setDoc(doc(as('customer1'), 'chat_reviews', 'L1'), review({ by: 'customer1', reportId: 'r1' })), 'not an admin');
      await seed(async (db) => {
        await setDoc(doc(db, 'reports', 'r1'), { reporterId: 'customer1', reportedId: 'driver1', bookingId: 'L1', reason: 'abuse', details: '', status: 'open', createdAt: Timestamp.now() });
        await setDoc(doc(db, 'reports', 'r2'), { reporterId: 'customer1', reportedId: 'driver1', bookingId: 'OTHER', reason: 'abuse', details: '', status: 'open', createdAt: Timestamp.now() });
      });
      await assertFails(setDoc(doc(asAdmin(), 'chat_reviews', 'L1'), review({ reportId: 'r2' })), 'a report about another booking');
      await assertSucceeds(setDoc(doc(asAdmin(), 'chat_reviews', 'L1'), review({ reportId: 'r1' })));
      await assertSucceeds(getDocs(msgs(asAdmin())));
      await assertFails(updateDoc(doc(asAdmin(), 'chat_reviews', 'L1'), { by: 'x' }));
      await assertFails(addDoc(msgs(asAdmin()), msg('admin1')), 'admins read, they do not write');
    });

    test('a dispute ticket also opens a review; a plain ticket does not', async () => {
      await seedBooking();
      await seed(async (db) => {
        await setDoc(doc(db, 'tickets', 't1'), { userId: 'customer1', category: 'dispute', bookingId: 'L1', subject: 'abc', status: 'open' });
        await setDoc(doc(db, 'tickets', 't2'), { userId: 'customer1', category: 'payment', bookingId: 'L1', subject: 'abc', status: 'open' });
      });
      await assertFails(setDoc(doc(asAdmin(), 'chat_reviews', 'L1'), { by: 'admin1', ticketId: 't2', createdAt: serverTimestamp() }));
      await assertSucceeds(setDoc(doc(asAdmin(), 'chat_reviews', 'L1'), { by: 'admin1', ticketId: 't1', createdAt: serverTimestamp() }));
    });

    test('contact_view and chat_view audit lines are admin only', async () => {
      const line = (type, actorId) => ({ type, actorId, targetId: 'driver1', bookingId: 'L1', data: { fields: ['phone'] }, createdAt: serverTimestamp() });
      await assertSucceeds(addDoc(collection(asAdmin(), 'audit_events'), line('contact_view', 'admin1')));
      await assertSucceeds(addDoc(collection(asAdmin(), 'audit_events'), line('chat_view', 'admin1')));
      await assertFails(addDoc(collection(as('customer1'), 'audit_events'), line('contact_view', 'customer1')));
      await assertFails(addDoc(collection(as('driver1'), 'audit_events'), line('chat_view', 'driver1')));
    });
  });

  test('a booking cannot store the driver\'s phone number', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { driverPhone: '+919800000000' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { driverPhone: '' }));
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
    await assertSucceeds(setTier(asAdmin(), 'u1', 'banned'));
    await assertFails(setTier(asAdmin(), 'u1', 'bogus'));
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
    b.update(doc(db, 'bookings', 'L1'), { driverId: 'driver2', vehicleId: 'v2', vehicleNumber: 'KA01CD5678', vehicleType: '20ft', driverName: 'Suresh', driverPhone: '', reassignedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
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
    await assertFails(reassign(asAdmin(), { driverPhone: '+919800000009' })); // numbers stay private (Task 4)
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

describe('admin user management', () => {
  const event = (extra = {}) => ({ type: 'user_action', actorId: 'admin1', targetId: 'u1', data: { action: 'ban', reason: 'x' }, createdAt: serverTimestamp(), ...extra });
  beforeEach(() => seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91', name: 'U' })));

  test('only admins ban, and banned is a valid tier; users cannot set it', async () => {
    const admin = asAdmin();
    const b = writeBatch(admin);
    b.update(doc(admin, 'users', 'u1'), { riskTier: 'banned', riskReason: 'fraud', riskUpdatedAt: serverTimestamp() });
    b.set(doc(admin, 'audit_events', 'e1'), event());
    await assertSucceeds(b.commit());
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { riskTier: 'evil', riskReason: 'x', riskUpdatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { riskTier: 'normal', riskReason: '', riskUpdatedAt: serverTimestamp() }));
  });
  test('user_action audit events are admin-only and append-only', async () => {
    await assertSucceeds(setDoc(doc(asAdmin(), 'audit_events', 'e1'), event()));
    await assertFails(setDoc(doc(as('u1'), 'audit_events', 'e2'), event({ actorId: 'u1' })));
    await assertFails(setDoc(doc(asAdmin(), 'audit_events', 'e3'), event({ actorId: 'someoneelse' })));
    await assertFails(updateDoc(doc(asAdmin(), 'audit_events', 'e1'), { data: {} }));
    await assertFails(deleteDoc(doc(asAdmin(), 'audit_events', 'e1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'audit_events', 'e1')));
    await assertFails(getDoc(doc(as('u1'), 'audit_events', 'e1')));
  });
  test('force re-verify: admin sets pending with itself as reviewer', async () => {
    await seed((db) => setDoc(doc(db, 'users', 'u1'), { phone: '+91', driverName: 'D', verified: true, verificationStatus: 'approved' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'u1'), {
      verified: false, verificationStatus: 'pending', updatedAt: serverTimestamp(),
      verificationMeta: { source: 'manual_review', by: 'admin1', status: 'pending', at: serverTimestamp() },
    }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), {
      verified: false, verificationStatus: 'pending', updatedAt: serverTimestamp(),
      verificationMeta: { source: 'manual_review', by: 'other', status: 'pending', at: serverTimestamp() },
    }));
  });
  test('internal notes: admins read and append; nobody else sees them; no edits', async () => {
    const note = (extra = {}) => ({ by: 'admin1', text: 'called him', createdAt: serverTimestamp(), ...extra });
    const ref = (db, id) => doc(db, 'users', 'u1', 'admin_notes', id);
    await assertSucceeds(setDoc(ref(asAdmin(), 'n1'), note()));
    await assertFails(setDoc(ref(asAdmin(), 'n2'), note({ by: 'x' })));
    await assertFails(setDoc(ref(asAdmin(), 'n3'), note({ text: '' })));
    await assertFails(setDoc(ref(asAdmin(), 'n4'), note({ text: 'x'.repeat(1001) })));
    await assertFails(setDoc(ref(as('u1'), 'n5'), note({ by: 'u1' })));
    await assertFails(getDoc(ref(as('u1'), 'n1')));
    await assertSucceeds(getDoc(ref(asAdmin(), 'n1')));
    await assertFails(updateDoc(ref(asAdmin(), 'n1'), { text: 'edited' }));
    await assertFails(deleteDoc(ref(asAdmin(), 'n1')));
  });
});

describe('hourly abuse limits', () => {
  const counter = (uid, kind) => doc(as(uid), 'rate_limits', `${uid}_${kind}`);
  const seedCounter = (uid, kind, count, minutesAgo) =>
    seed((db) => rawSetDoc(doc(db, 'rate_limits', `${uid}_${kind}`), { count, windowStart: Timestamp.fromMillis(Date.now() - minutesAgo * 60000), last: 'seed' }));
  const fresh = () => ({ count: 1, windowStart: serverTimestamp() });
  // one raw batch: the load plus the counter write
  const postLoad = (id, bump, uid = 'customer1') => {
    const db = as(uid);
    const b = rawWriteBatch(db);
    b.set(doc(db, 'loads', id), { ...LOAD, shipperId: uid, createdAt: serverTimestamp() });
    if (bump) b.set(doc(db, 'rate_limits', `${uid}_load`), bump);
    return b.commit();
  };

  test('a load needs a bump that names it; the first one starts a window at 1', async () => {
    await assertFails(postLoad('L1', null));
    await assertFails(postLoad('L1', { ...fresh(), last: 'other' }));
    await assertFails(postLoad('L1', { count: 2, windowStart: serverTimestamp(), last: 'L1' }));
    await assertSucceeds(postLoad('L1', { ...fresh(), last: 'L1' }));
  });
  test('inside a window the counter goes up by exactly one and keeps its start', async () => {
    await seedCounter('customer1', 'load', 5, 10);
    const start = (await getDoc(counter('customer1', 'load'))).data().windowStart;
    await assertFails(postLoad('L1', null));
    await assertFails(postLoad('L1', { count: 5, windowStart: start, last: 'L1' }));
    await assertFails(postLoad('L1', { count: 9, windowStart: start, last: 'L1' }));
    await assertFails(postLoad('L1', { count: 1, windowStart: serverTimestamp(), last: 'L1' }), 'window is still open: no reset');
    await assertFails(postLoad('L1', { count: 6, windowStart: serverTimestamp(), last: 'L1' }));
    await assertSucceeds(postLoad('L1', { count: 6, windowStart: start, last: 'L1' }));
  });
  test('one bump pays for one document only', async () => {
    const db = as('customer1');
    const b = rawWriteBatch(db);
    b.set(doc(db, 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp() });
    b.set(doc(db, 'loads', 'L2'), { ...LOAD, createdAt: serverTimestamp() });
    b.set(doc(db, 'rate_limits', 'customer1_load'), { ...fresh(), last: 'L1' });
    await assertFails(b.commit());
  });
  test('the 31st load in an hour is refused; a new hour starts again', async () => {
    await seedCounter('customer1', 'load', 29, 5);
    const start = (await getDoc(counter('customer1', 'load'))).data().windowStart;
    await assertSucceeds(postLoad('L30', { count: 30, windowStart: start, last: 'L30' }));
    await assertFails(postLoad('L31', { count: 31, windowStart: start, last: 'L31' }));
    await assertFails(postLoad('L31', { ...fresh(), last: 'L31' }));
    await seedCounter('customer1', 'load', 30, 61);
    await assertSucceeds(postLoad('L32', { ...fresh(), last: 'L32' }));
  });
  test('offers (60) and chat messages (120) have their own counters and limits', async () => {
    await seedOpenLoad();
    const offer = (bump, uid = 'driver1') => {
      const db = as(uid);
      const b = rawWriteBatch(db);
      b.set(doc(db, 'offers', `L1_${uid}`), {
        loadId: 'L1', driverId: uid, customerId: 'customer1', vehicleId: 'v1', vehicleNumber: VEHICLE.number, vehicleType: '20ft', driverName: 'R',
        pricePaise: 100000, originalPaise: 100000, status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      });
      if (bump) b.set(doc(db, 'rate_limits', `${uid}_offer`), bump);
      return b.commit();
    };
    await assertFails(offer(null));
    await seedCounter('driver1', 'offer', 60, 3);
    await assertFails(offer({ count: 61, windowStart: (await getDoc(counter('driver1', 'offer'))).data().windowStart, last: 'L1_driver1' }));
    await seedCounter('driver1', 'offer', 59, 3);
    await assertSucceeds(offer({ count: 60, windowStart: (await getDoc(counter('driver1', 'offer'))).data().windowStart, last: 'L1_driver1' }));

    await seedBooking('accepted');
    const say = (bump, id = 'm1') => {
      const db = as('customer1');
      const b = rawWriteBatch(db);
      b.set(doc(db, 'bookings', 'L1', 'messages', id), { senderId: 'customer1', text: 'hi', flagged: false, createdAt: serverTimestamp() });
      if (bump) b.set(doc(db, 'rate_limits', 'customer1_message'), bump);
      return b.commit();
    };
    await assertFails(say(null));
    await seedCounter('customer1', 'message', 120, 3);
    const w = (await getDoc(counter('customer1', 'message'))).data().windowStart;
    await assertFails(say({ count: 121, windowStart: w, last: 'm1' }));
    await seedCounter('customer1', 'message', 119, 3);
    const w2 = (await getDoc(counter('customer1', 'message'))).data().windowStart;
    await assertSucceeds(say({ count: 120, windowStart: w2, last: 'm1' }));
    await assertFails(say({ ...fresh(), last: 'm2' }, 'm2'));
  });
  test('a support ticket needs a bump that names it; ten an hour', async () => {
    const open = (bump, id = 't1') => {
      const db = as('customer1');
      const b = rawWriteBatch(db);
      b.set(doc(db, 'tickets', id), { userId: 'customer1', category: 'other', priority: 'normal', status: 'open', subject: 'Help me', description: '', escalationLevel: 0, createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      if (bump) b.set(doc(db, 'rate_limits', 'customer1_ticket'), bump);
      return b.commit();
    };
    await assertFails(open(null));
    await assertSucceeds(open({ ...fresh(), last: 't1' }));
    await seedCounter('customer1', 'ticket', 10, 3);
    const w = (await getDoc(counter('customer1', 'ticket'))).data().windowStart;
    await assertFails(open({ count: 11, windowStart: w, last: 't2' }, 't2'));
    await seedCounter('customer1', 'ticket', 9, 3);
    const w2 = (await getDoc(counter('customer1', 'ticket'))).data().windowStart;
    await assertSucceeds(open({ count: 10, windowStart: w2, last: 't2' }, 't2'));
  });
  test('counters are private, only your own, only the three kinds, never deleted', async () => {
    await assertFails(rawSetDoc(doc(as('customer2'), 'rate_limits', 'customer1_load'), { ...fresh(), last: 'x' }));
    await assertFails(rawSetDoc(doc(as('customer1'), 'rate_limits', 'customer1_widget'), { ...fresh(), last: 'x' }));
    await assertSucceeds(rawSetDoc(doc(as('customer1'), 'rate_limits', 'customer1_load'), { ...fresh(), last: 'x' }));
    await assertSucceeds(getDoc(counter('customer1', 'load')));
    await assertFails(getDoc(doc(as('customer2'), 'rate_limits', 'customer1_load')));
    await assertFails(deleteDoc(counter('customer1', 'load')));
    await assertFails(rawSetDoc(counter('customer1', 'load'), { count: 1, windowStart: serverTimestamp(), last: 'y', extra: 1 }));
  });
});

describe('input length limits', () => {
  const post = (extra) => setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp(), ...extra });
  test('load text and numbers are capped', async () => {
    await assertFails(post({ pickup: 'x'.repeat(201) }));
    await assertFails(post({ drop: 'x'.repeat(201) }));
    await assertFails(post({ cargoType: 'x'.repeat(61) }));
    await assertFails(post({ vehicleType: 'x'.repeat(41) }));
    await assertFails(post({ notes: 'x'.repeat(501) }));
    await assertFails(post({ weight: 1001 }));
    await assertFails(post({ budget: 2000000000 }));
    await assertSucceeds(post({ pickup: 'x'.repeat(200), notes: 'n'.repeat(500), weight: 1000 }));
  });
  test('profile text is capped', async () => {
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', name: 'x'.repeat(81) }));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', email: 'x'.repeat(101) }));
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', name: 'x'.repeat(80), companyName: 'c'.repeat(100) }));
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { driverName: 'x'.repeat(81) }));
  });
  test('vehicle type and rc number are capped', async () => {
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, number: 'MH12AB9999', type: 'x'.repeat(41) }));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, number: 'MH12AB9999', rcNumber: 'x'.repeat(31) }));
    await assertSucceeds(addVehicle(as('driver1'), 'v9', { ...VEHICLE, number: 'MH12AB9999' }));
  });
});

describe('notification category switches', () => {
  const prefs = (extra = {}) => ({ bookingUpdates: true, ratings: false, promotions: true, payments: true, reminders: false, ...extra });
  test('five boolean switches are accepted, on create and update', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', notificationPrefs: prefs() }));
    await assertSucceeds(updateDoc(doc(as('u1'), 'users', 'u1'), { notificationPrefs: prefs({ payments: false }) }));
    await assertSucceeds(updateDoc(doc(as('u1'), 'users', 'u1'), { notificationPrefs: { ratings: false } }));
  });
  test('unknown keys and non-booleans are refused', async () => {
    await assertFails(setDoc(doc(as('u2'), 'users', 'u2'), { phone: '+91', notificationPrefs: prefs({ spam: true }) }));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u2'), { phone: '+91', notificationPrefs: prefs({ payments: 'yes' }) }));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u2'), { phone: '+91', notificationPrefs: prefs({ reminders: 0 }) }));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u2'), { phone: '+91', notificationPrefs: 'off' }));
  });
});

describe('saved searches', () => {
  const search = (extra = {}) => ({ kind: 'loads', name: 'Heavy to Delhi', filter: { drop: 'Delhi', minWeight: 6 }, createdAt: serverTimestamp(), ...extra });
  const ref = (uid, id) => doc(as(uid), 'users', 'customer1', 'saved_searches', id);
  test('private to the owner and validated', async () => {
    await assertSucceeds(setDoc(ref('customer1', 's1'), search()));
    await assertSucceeds(setDoc(ref('customer1', 's2'), search({ kind: 'trucks', filter: { from: 'Pune', minCapacity: 10 } })));
    await assertSucceeds(getDoc(ref('customer1', 's1')));
    await assertFails(getDoc(ref('customer2', 's1')));
    await assertFails(setDoc(ref('customer2', 's3'), search()));
    await assertFails(setDoc(ref('customer1', 's4'), search({ kind: 'bogus' })));
    await assertFails(setDoc(ref('customer1', 's5'), search({ name: '' })));
    await assertFails(setDoc(ref('customer1', 's6'), search({ filter: {} })));
    await assertFails(setDoc(ref('customer1', 's7'), search({ filter: { evil: 1 } })));
    await assertFails(setDoc(ref('customer1', 's8'), search({ extra: 1 })));
    await assertSucceeds(deleteDoc(ref('customer1', 's1')));
    await assertFails(deleteDoc(ref('customer2', 's2')));
  });
});

describe('document expiry', () => {
  const day = 86400000;
  const past = (d) => Timestamp.fromDate(new Date(Date.now() - d * day));
  const future = (d) => Timestamp.fromDate(new Date(Date.now() + d * day));
  const accept = (db) => acceptBatch(db, 'L1');
  const setVehicle = (extra) => seed((db) => setDoc(doc(db, 'vehicles', 'v1'), { ...VEHICLE, ...extra }));
  beforeEach(seedOpenLoad);

  test('an expired insurance, permit or fitness paper blocks accepting; PUC and valid papers do not', async () => {
    await setVehicle({ docs: { insurance: { number: 'P', expiry: past(3) } } });
    await assertFails(accept(as('driver1')));
    await setVehicle({ docs: { permit: { number: 'P', expiry: past(3) } } });
    await assertFails(accept(as('driver1')));
    await setVehicle({ docs: { fitness: { number: 'P', expiry: past(3) } } });
    await assertFails(accept(as('driver1')));
    await setVehicle({ docs: { puc: { number: 'P', expiry: past(30) }, insurance: { number: 'P', expiry: future(30) } } });
    await assertSucceeds(accept(as('driver1')));
  });
  test('an admin override lets the vehicle work until it ends', async () => {
    await setVehicle({ docs: { insurance: { number: 'P', expiry: past(3) } }, docOverrideUntil: future(2) });
    await assertSucceeds(accept(as('driver1')));
  });
  test('an expired override does not help', async () => {
    await setVehicle({ docs: { insurance: { number: 'P', expiry: past(3) } }, docOverrideUntil: past(1) });
    await assertFails(accept(as('driver1')));
  });
  test('the owner may suspend for documents, but only lift it with clear papers or an override', async () => {
    await setVehicle({ docs: { insurance: { number: 'P', expiry: past(3) } } });
    const ref = (db) => doc(db, 'vehicles', 'v1');
    await assertSucceeds(updateDoc(ref(as('driver1')), { availability: 'doc_expired' }));
    await assertFails(updateDoc(ref(as('driver1')), { availability: 'available' }));
    await assertFails(updateDoc(ref(as('driver1')), { availability: 'available', docOverrideUntil: future(5) }));
    await assertSucceeds(updateDoc(ref(as('driver1')), { availability: 'available', docs: { insurance: { number: 'P', expiry: future(300) } } }));
  });
  test('only admins write docOverrideUntil, on vehicles and on users', async () => {
    const ref = (db) => doc(db, 'vehicles', 'v1');
    await assertFails(updateDoc(ref(as('driver1')), { docOverrideUntil: future(5) }));
    await assertSucceeds(updateDoc(ref(asAdmin()), { availability: 'available', docOverrideUntil: future(5), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(asAdmin()), { docOverrideUntil: 'tomorrow' }));
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { phone: '+91' }));
    await assertFails(updateDoc(doc(as('driver1'), 'users', 'driver1'), { docOverrideUntil: future(5) }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'driver1'), { docOverrideUntil: future(5), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver9'), 'users', 'driver9'), { phone: '+91', docOverrideUntil: future(5) }));
  });
  test('an expired licence blocks accepting unless an admin override is on the profile', async () => {
    const kyc = { dlNumber: 'DL1420110012345', dlExpiry: past(3), rcNumber: 'RC123', aadhaarLast4: '1234', pan: 'ABCDE1234F' };
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { phone: '+91', driverKyc: kyc }));
    await assertFails(accept(as('driver1')));
    await seed((db) => updateDoc(doc(db, 'users', 'driver1'), { docOverrideUntil: future(3) }));
    await assertSucceeds(accept(as('driver1')));
  });
  test('a valid licence accepts', async () => {
    const kyc = { dlNumber: 'DL1420110012345', dlExpiry: future(300), rcNumber: 'RC123', aadhaarLast4: '1234', pan: 'ABCDE1234F' };
    await seed((db) => setDoc(doc(db, 'users', 'driver1'), { phone: '+91', driverKyc: kyc }));
    await assertSucceeds(accept(as('driver1')));
  });
});

describe('invoices and the number series', () => {
  const FY = '2026-27';
  const inv = (extra = {}) => ({
    bookingId: 'L1', issuerId: 'driver1', customerId: 'customer1', driverId: 'driver1', seq: 1, fy: FY, number: `LG/${FY}/00001`,
    gstPercent: 18, taxablePaise: 2118644, cgstPaise: 190678, sgstPaise: 190678, totalPaise: 2500000, sellerName: 'Ramesh Transport',
    hsn: '996511', issuedAt: serverTimestamp(), ...extra,
  });
  const issue = (db, invoice = inv(), next = 2) => {
    const b = writeBatch(db);
    b.set(doc(db, 'invoices', 'L1'), invoice);
    b.set(doc(db, 'invoice_series', `driver1_${FY}`), { next, updatedAt: serverTimestamp() });
    return b.commit();
  };
  beforeEach(async () => {
    await seedBooking('delivered');
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { agreedFarePaise: 2500000 }));
  });
  test('the driver of a delivered trip issues number 1 and bumps the counter', async () => {
    await assertSucceeds(issue(as('driver1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'invoices', 'L1')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'invoice_series', `driver1_${FY}`)));
    await assertFails(getDoc(doc(as('driver2'), 'invoices', 'L1')));
    await assertFails(getDoc(doc(as('driver2'), 'invoice_series', `driver1_${FY}`)));
    await assertSucceeds(getDoc(doc(asAdmin(), 'invoices', 'L1')));
  });
  test('wrong issuer, wrong status, wrong number, or a missing counter bump fail', async () => {
    await assertFails(issue(as('customer1'), inv({ issuerId: 'customer1' })));
    await assertFails(issue(as('driver2'), inv({ issuerId: 'driver2' })));
    await assertFails(issue(as('driver1'), inv({ seq: 2, number: `LG/${FY}/00002` }), 3));
    await assertFails(issue(as('driver1'), inv(), 5));
    await assertFails(setDoc(doc(as('driver1'), 'invoices', 'L1'), inv()));
    await assertFails(issue(as('driver1'), inv({ number: 'INV-1' })));
    await assertFails(issue(as('driver1'), inv({ number: 'LG/2025-26/00001' })));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'in_transit' }));
    await assertFails(issue(as('driver1')));
  });
  test('amounts must add up and match the booking; fields are validated', async () => {
    await assertFails(issue(as('driver1'), inv({ totalPaise: 2500001 })));
    await assertFails(issue(as('driver1'), inv({ totalPaise: 3000000, taxablePaise: 2542372, cgstPaise: 228814, sgstPaise: 228814 })));
    await assertFails(issue(as('driver1'), inv({ sellerGstin: 'short' })));
    await assertFails(issue(as('driver1'), inv({ ewayBillNo: '12345' })));
    await assertFails(issue(as('driver1'), inv({ hsn: 'x' })));
    await assertFails(issue(as('driver1'), inv({ extra: 1 })));
    await assertSucceeds(issue(as('driver1'), inv({ sellerGstin: '27ABCDE1234F1Z5', ewayBillNo: '123456789012', ewayDistanceKm: 900, ewayValidUntil: Timestamp.fromDate(new Date('2026-11-01')) })));
  });
  test('the series continues at 2 and cannot be reset or skipped', async () => {
    await assertSucceeds(issue(as('driver1')));
    await seed((db) => setDoc(doc(db, 'bookings', 'L2'), { ...bookingFor('L1'), status: 'delivered' }));
    await assertFails(setDoc(doc(as('driver1'), 'invoice_series', `driver1_${FY}`), { next: 2, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'invoice_series', `driver1_${FY}`), { next: 9, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'invoice_series', `driver1_${FY}`), { next: 1, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver2'), 'invoice_series', `driver1_${FY}`), { next: 2, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(doc(as('driver1'), 'invoice_series', `driver1_${FY}`)));
  });
  test('only the issuer edits e-way fields; nothing else is editable or deletable', async () => {
    await issue(as('driver1'));
    const ref = (db) => doc(db, 'invoices', 'L1');
    await assertSucceeds(updateDoc(ref(as('driver1')), { ewayBillNo: '123456789012', ewayDistanceKm: 500 }));
    await assertFails(updateDoc(ref(as('driver1')), { ewayBillNo: 'abc' }));
    await assertFails(updateDoc(ref(as('driver1')), { totalPaise: 1 }));
    await assertFails(updateDoc(ref(as('driver1')), { number: 'LG/2026-27/00009' }));
    await assertFails(updateDoc(ref(as('customer1')), { ewayBillNo: '123456789012' }));
    await assertFails(deleteDoc(ref(as('driver1'))));
  });
});

describe('claims and disputes', () => {
  const claim = (extra = {}) => ({
    bookingId: 'L1', customerId: 'customer1', driverId: 'driver1', openedBy: 'customer1', type: 'damage',
    description: 'Boxes were crushed', status: 'open', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...extra,
  });
  const event = (uid, role, kind = 'message', extra = {}) => ({ by: uid, role, kind, text: 'hello', createdAt: serverTimestamp(), ...extra });
  const open = (db, uid, c = claim(), role = 'customer') => {
    const b = writeBatch(db);
    b.set(doc(db, 'claims', `L1_${uid}`), c);
    b.set(doc(db, 'claims', `L1_${uid}`, 'events', 'e1'), event(uid, role, 'opened'));
    return b.commit();
  };
  test('a party opens one claim, only once the trip reached unloading', async () => {
    await seedBooking('in_transit');
    await assertFails(open(as('customer1'), 'customer1'));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'unloading' }));
    await assertSucceeds(open(as('customer1'), 'customer1'));
    await assertSucceeds(open(as('driver1'), 'driver1', claim({ openedBy: 'driver1', type: 'payment' }), 'driver'));
    await assertFails(open(as('customer2'), 'customer2', claim({ openedBy: 'customer2' })));
  });
  test('claim fields are validated and must match the booking', async () => {
    await seedBooking('delivered');
    await assertFails(open(as('customer1'), 'customer1', claim({ description: 'short' })));
    await assertFails(open(as('customer1'), 'customer1', claim({ type: 'bogus' })));
    await assertFails(open(as('customer1'), 'customer1', claim({ driverId: 'driver2' })));
    await assertFails(open(as('customer1'), 'customer1', claim({ status: 'resolved' })));
    await assertFails(open(as('customer1'), 'customer1', claim({ amountPaise: 99999999 })));
    await assertFails(open(as('customer1'), 'customer1', claim({ extra: 1 })));
    await assertFails(setDoc(doc(as('customer1'), 'claims', 'L1_driver1'), claim()));
    await assertSucceeds(open(as('customer1'), 'customer1', claim({ amountPaise: 500000 })));
  });
  test('parties and admins read; outsiders do not; parties cannot change status', async () => {
    await seedBooking('delivered');
    await open(as('customer1'), 'customer1');
    const ref = (db) => doc(db, 'claims', 'L1_customer1');
    await assertSucceeds(getDoc(ref(as('customer1'))));
    await assertSucceeds(getDoc(ref(as('driver1'))));
    await assertSucceeds(getDoc(ref(asAdmin())));
    await assertFails(getDoc(ref(as('customer2'))));
    await assertSucceeds(getDoc(doc(as('driver1'), 'claims', 'L1_customer1', 'events', 'e1')));
    await assertFails(getDoc(doc(as('customer2'), 'claims', 'L1_customer1', 'events', 'e1')));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'resolved', outcome: 'upheld', resolvedBy: 'customer1', updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(asAdmin())));
  });
  test('timeline: parties message while open, the other party too, admin always; no edits', async () => {
    await seedBooking('delivered');
    await open(as('customer1'), 'customer1');
    const ev = (db, id) => doc(db, 'claims', 'L1_customer1', 'events', id);
    await assertSucceeds(setDoc(ev(as('driver1'), 'e2'), event('driver1', 'driver')));
    await assertFails(setDoc(ev(as('driver1'), 'e3'), event('driver1', 'customer')));
    await assertFails(setDoc(ev(as('driver1'), 'e4'), event('driver1', 'driver', 'resolution')));
    await assertFails(setDoc(ev(as('customer2'), 'e5'), event('customer2', 'customer')));
    await assertFails(setDoc(ev(as('driver1'), 'e6'), event('customer1', 'driver')));
    await assertFails(updateDoc(ev(as('driver1'), 'e2'), { text: 'changed' }));
    await assertFails(deleteDoc(ev(as('customer1'), 'e1')));
    await assertSucceeds(setDoc(ev(asAdmin(), 'e7'), event('admin1', 'admin', 'status')));
  });
  test('admin reviews and resolves; a resolved claim takes no party messages', async () => {
    await seedBooking('delivered');
    await open(as('customer1'), 'customer1');
    const ref = (db) => doc(db, 'claims', 'L1_customer1');
    await assertSucceeds(updateDoc(ref(asAdmin()), { status: 'under_review', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(asAdmin()), { status: 'resolved', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(asAdmin()), { status: 'resolved', outcome: 'upheld', resolvedBy: 'admin1', awardedPaise: -5, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(asAdmin()), { status: 'resolved', outcome: 'upheld', resolvedBy: 'admin1', customerId: 'x', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(asAdmin()), { status: 'resolved', outcome: 'partial', resolvedBy: 'admin1', resolvedAt: serverTimestamp(), awardedPaise: 60000, resolutionNote: 'ok', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver1'), 'claims', 'L1_customer1', 'events', 'late'), event('driver1', 'driver')));
  });
});

describe('rating categories and low-rating flags', () => {
  const rating = (extra = {}) => ({ bookingId: 'L1', raterId: 'customer1', ratedId: 'driver1', stars: 2, comment: '', createdAt: serverTimestamp(), ...extra });
  const flag = (extra = {}) => ({ bookingId: 'L1', raterId: 'customer1', ratedId: 'driver1', stars: 2, status: 'open', createdAt: serverTimestamp(), ...extra });
  const rate = (db, r, f) => {
    const b = writeBatch(db);
    b.set(doc(db, 'ratings', 'L1_customer1'), r);
    if (f) b.set(doc(db, 'rating_flags', 'L1_customer1'), f);
    return b.commit();
  };
  beforeEach(() => seedBooking('delivered'));
  test('categories must be 1-5 and one of time, behaviour, safety', async () => {
    await assertFails(rate(as('customer1'), rating({ cats: { speed: 3 } }), flag()));
    await assertFails(rate(as('customer1'), rating({ cats: { time: 6 } }), flag()));
    await assertFails(rate(as('customer1'), rating({ cats: { time: 2.5 } }), flag()));
    await assertSucceeds(rate(as('customer1'), rating({ cats: { time: 5, behaviour: 1, safety: 3 } }), flag()));
  });
  test('the flag needs a matching rating under 3 stars, written by the rater', async () => {
    await assertFails(rate(as('customer1'), rating({ stars: 4 }), flag({ stars: 4 })));
    await assertFails(rate(as('customer1'), rating({ stars: 4 }), flag({ stars: 2 })));
    await assertFails(rate(as('customer1'), rating(), flag({ ratedId: 'someone' })));
    await assertFails(rate(as('customer1'), rating(), flag({ status: 'reviewed' })));
    await assertFails(rate(as('customer1'), rating(), flag({ extra: 1 })));
    await assertSucceeds(rate(as('customer1'), rating({ stars: 4 })));
  });
  test('only admins read and resolve flags', async () => {
    await assertSucceeds(rate(as('customer1'), rating(), flag()));
    const ref = (db) => doc(db, 'rating_flags', 'L1_customer1');
    await assertFails(getDoc(ref(as('customer1'))));
    await assertFails(getDoc(ref(as('driver1'))));
    await assertSucceeds(getDoc(ref(asAdmin())));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'dismissed', handledBy: 'customer1', handledAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(asAdmin()), { status: 'open', handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(asAdmin()), { status: 'reviewed', handledBy: 'admin1', handledAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(asAdmin())));
  });
});

describe('templates, favourites and block list', () => {
  const tpl = (extra = {}) => ({
    name: 'Weekly FMCG', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 8, vehicleType: '20ft', budget: null,
    notes: '', pickupSlot: 'any', fragile: false, highValue: false, createdAt: serverTimestamp(), ...extra,
  });
  test('templates are private and validated', async () => {
    const t = (uid, id) => doc(as(uid), 'users', 'customer1', 'load_templates', id);
    await assertSucceeds(setDoc(t('customer1', 't1'), tpl()));
    await assertSucceeds(getDoc(t('customer1', 't1')));
    await assertFails(getDoc(t('customer2', 't1')));
    await assertFails(setDoc(t('customer2', 't2'), tpl()));
    await assertFails(setDoc(t('customer1', 't3'), tpl({ name: '' })));
    await assertFails(setDoc(t('customer1', 't4'), tpl({ weight: 0 })));
    await assertFails(setDoc(t('customer1', 't5'), tpl({ pickupDate: Timestamp.now() })));
    await assertSucceeds(deleteDoc(t('customer1', 't1')));
  });
  test('favourite and blocked lists are private, own uid cannot be listed', async () => {
    const fav = (uid, d) => doc(as(uid), 'users', 'customer1', 'favourite_drivers', d);
    const blk = (uid, d) => doc(as(uid), 'users', 'customer1', 'blocked_drivers', d);
    await assertSucceeds(setDoc(fav('customer1', 'driver1'), { name: 'Ramesh', vehicleNumber: 'MH12AB1234', createdAt: serverTimestamp() }));
    await assertFails(getDoc(fav('customer2', 'driver1')));
    await assertFails(setDoc(fav('customer1', 'customer1'), { name: 'x', vehicleNumber: '', createdAt: serverTimestamp() }));
    await assertSucceeds(setDoc(blk('customer1', 'driver2'), { name: 'Bad', createdAt: serverTimestamp() }));
    await assertFails(setDoc(blk('customer2', 'driver3'), { name: 'Bad', createdAt: serverTimestamp() }));
    await assertFails(setDoc(blk('customer1', 'driver3'), { name: 'Bad', extra: 1, createdAt: serverTimestamp() }));
    await assertFails(getDoc(blk('customer2', 'driver2')));
    await assertSucceeds(deleteDoc(blk('customer1', 'driver2')));
  });
  test('a blocked driver cannot accept the load, others can', async () => {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'loads', 'L1'), { ...LOAD, blockedDriverIds: ['driver1'] }));
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver2'), 'L1', 'driver2', { vehicleId: 'v1' }));
    await assertSucceeds(acceptBatch(as('driver2'), 'L1', 'driver2', { vehicleId: 'v2', vehicleNumber: 'KA01CD5678' }));
  });
  test('a load may carry at most 50 blocked ids', async () => {
    const ids = Array.from({ length: 51 }, (_, i) => `d${i}`);
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp(), blockedDriverIds: ids }));
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp(), blockedDriverIds: ids.slice(0, 50) }));
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

describe('account deletion', () => {
  const H = 'c'.repeat(64);
  const seedAccount = (extra = {}) => seed(async (db) => {
    await setDoc(doc(db, 'users', 'd1'), { role: 'driver', selectedRole: 'driver', identityHashes: { dl: H }, ...extra });
    await setDoc(doc(db, 'identity_index', H), { uid: 'd1', role: 'driver', type: 'dl' });
    await setDoc(doc(db, 'users', 'd1', 'saved_places', 'p1'), { label: 'home' });
    await setDoc(doc(db, 'notifications', 'n1'), { userId: 'd1' });
  });

  test('owner deletes profile, index entry and private data in one batch', async () => {
    await seedAccount();
    const db = as('d1');
    const b = writeBatch(db);
    b.delete(doc(db, 'identity_index', H));
    b.delete(doc(db, 'users', 'd1'));
    await assertSucceeds(b.commit());
    await assertSucceeds(deleteDoc(doc(db, 'users', 'd1', 'saved_places', 'p1')));
    await assertSucceeds(deleteDoc(doc(db, 'notifications', 'n1')));
  });

  test('an index entry cannot be dropped while the profile stays, nor for another user', async () => {
    await seedAccount();
    await assertFails(deleteDoc(doc(as('d1'), 'identity_index', H)));
    const other = as('d2');
    const b = writeBatch(other);
    b.delete(doc(other, 'identity_index', H));
    b.delete(doc(other, 'users', 'd2'));
    await assertFails(b.commit());
    await assertFails(deleteDoc(doc(as('d2'), 'users', 'd1')));
  });

  test('restricted, suspended and banned accounts cannot delete themselves', async () => {
    for (const tier of ['restricted', 'suspended', 'banned']) {
      await seedAccount({ riskTier: tier });
      await assertFails(deleteDoc(doc(as('d1'), 'users', 'd1')));
    }
    await seedAccount({ riskTier: 'review' });
    await assertSucceeds(deleteDoc(doc(as('d1'), 'users', 'd1')));
  });
});

describe('profile extras and review flag', () => {
  const seedUser = (extra = {}) => seed((db) => setDoc(doc(db, 'users', 'u1'), { role: 'customer', selectedRole: 'customer', name: 'Asha', ...extra }));

  test('addresses, business type and payout UPI id are validated', async () => {
    await seedUser();
    const ref = doc(as('u1'), 'users', 'u1');
    await assertSucceeds(updateDoc(ref, { addresses: { current: 'House 1', permanent: 'Village' }, businessType: 'importer', payoutProfile: { upiId: 'asha.k@okaxis', holder: 'Asha K' } }));
    await assertFails(updateDoc(ref, { businessType: 'pirate' }));
    await assertFails(updateDoc(ref, { payoutProfile: { upiId: 'not a upi', holder: 'x' } }));
    await assertFails(updateDoc(ref, { payoutProfile: { upiId: 'a@bank', holder: 'x', iban: 'DE00' } }));
    await assertFails(updateDoc(ref, { addresses: { current: 'x'.repeat(201) } }));
    await assertFails(updateDoc(ref, { addresses: { current: 'ok', office: 'extra key' } }));
  });

  test('only an admin sets or clears the review flag, in the allowed shape', async () => {
    await seedUser();
    const flag = (over = {}) => ({ kind: 'name', note: 'Name differs from licence', by: 'admin1', at: serverTimestamp(), ...over });
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { reviewFlag: flag({ by: 'u1' }) }));
    await assertFails(updateDoc(doc(as('u2'), 'users', 'u1'), { reviewFlag: flag() }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { reviewFlag: flag({ kind: 'bogus' }) }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { reviewFlag: flag({ by: 'someone' }) }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'u1'), { reviewFlag: flag(), name: 'Changed' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'u1'), { reviewFlag: flag(), updatedAt: serverTimestamp() }));
    // the owner cannot clear or edit it
    await assertFails(updateDoc(doc(as('u1'), 'users', 'u1'), { reviewFlag: deleteField() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'u1'), { reviewFlag: deleteField(), updatedAt: serverTimestamp() }));
  });

  test('a new profile cannot arrive with a review flag', async () => {
    await assertFails(setDoc(doc(as('u3'), 'users', 'u3'), { role: 'customer', selectedRole: 'customer', reviewFlag: { kind: 'name', note: 'x', by: 'u3', at: serverTimestamp() } }));
  });

  test('mobile change writes a phone_change signal for oneself only', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'risk_signals', 'S1'), { uid: 'u1', type: 'phone_change', note: 'from •••3210 to •••6789', createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('u1'), 'risk_signals', 'S2'), { uid: 'u2', type: 'phone_change', createdAt: serverTimestamp() }));
  });
});

describe('load visibility, pickup now and repeating loads', () => {
  const post = (over) => setDoc(doc(as('customer1'), 'loads', 'N1'), { ...LOAD, ...over });

  test('visibility is public, or favourites/invite with 1 to 20 allowed drivers', async () => {
    await assertSucceeds(post({ instant: true }));
    await assertSucceeds(post({ visibility: 'public' }));
    await assertSucceeds(post({ visibility: 'favourites', allowedDriverIds: ['driver1'] }));
    await assertSucceeds(post({ visibility: 'invite', allowedDriverIds: ['driver1'] }));
    await assertFails(post({ visibility: 'favourites' }));
    await assertFails(post({ visibility: 'favourites', allowedDriverIds: [] }));
    await assertFails(post({ visibility: 'favourites', allowedDriverIds: Array.from({ length: 21 }, (_, i) => `d${i}`) }));
    await assertFails(post({ visibility: 'public', allowedDriverIds: ['driver1'] }));
    await assertFails(post({ visibility: 'secret', allowedDriverIds: ['driver1'] }));
    await assertFails(post({ instant: 'yes' }));
  });

  test('only an allowed driver can accept a restricted load', async () => {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'loads', 'L1'), { ...LOAD, visibility: 'favourites', allowedDriverIds: ['driver2'] }));
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertSucceeds(acceptBatch(as('driver2'), 'L1', 'driver2', { vehicleId: 'v2', vehicleNumber: 'KA01CD5678' }));
  });

  test('repeating loads are private to the customer, weekly or monthly, and shaped', async () => {
    const r = (over = {}) => ({ name: 'Pune - Delhi', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 8, vehicleType: '20ft',
      frequency: 'weekly', nextDueAt: Timestamp.fromDate(new Date('2026-10-13')), active: true, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R1'), r()));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R2'), r({ frequency: 'daily' })));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R3'), r({ extra: 1 })));
    await assertFails(setDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R4'), r({ weight: 0 })));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u1', 'recurring_loads', 'R5'), r()));
    await assertFails(getDoc(doc(as('u2'), 'users', 'u1', 'recurring_loads', 'R1')));
    await assertSucceeds(updateDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R1'), { nextDueAt: Timestamp.fromDate(new Date('2026-10-20')) }));
    await assertSucceeds(deleteDoc(doc(as('u1'), 'users', 'u1', 'recurring_loads', 'R1')));
  });
});

describe('vehicle expenses and switching vehicle after a breakdown', () => {
  const expense = (over = {}) => ({ ownerId: 'driver1', vehicleId: 'v1', kind: 'fuel', amountPaise: 450000, note: 'Kherki', date: Timestamp.fromDate(new Date('2026-10-05')), createdAt: serverTimestamp(), ...over });

  test('expense lines: owner of the vehicle only, shaped, private', async () => {
    await seedOpenLoad();
    await assertSucceeds(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E1'), expense()));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E2'), expense({ kind: 'beer' })));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E3'), expense({ amountPaise: 0 })));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E4'), expense({ amountPaise: 10000001 })));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E5'), expense({ amountPaise: 12.5 })));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E6'), expense({ extra: 1 })));
    await assertFails(setDoc(doc(as('driver1'), 'vehicle_expenses', 'E7'), expense({ vehicleId: 'v2' }))); // not their vehicle
    await assertFails(setDoc(doc(as('driver2'), 'vehicle_expenses', 'E8'), expense({ ownerId: 'driver2' }))); // vehicle v1 is not theirs
    await assertFails(getDoc(doc(as('driver2'), 'vehicle_expenses', 'E1')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'vehicle_expenses', 'E1')));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicle_expenses', 'E1'), { amountPaise: 1 }));
    await assertFails(deleteDoc(doc(as('driver2'), 'vehicle_expenses', 'E1')));
    await assertSucceeds(deleteDoc(doc(as('driver1'), 'vehicle_expenses', 'E1')));
  });

  const swap = (over = {}) => ({ vehicleId: 'v3', vehicleNumber: 'GJ01CD9999', replacedVehicleIds: ['v1'], updatedAt: serverTimestamp(), ...over });

  async function seedBroken(replacement = true) {
    await seedBooking('in_transit');
    await seed(async (db) => {
      await setDoc(doc(db, 'vehicles', 'v3'), { ...VEHICLE, number: 'GJ01CD9999', capacity: 12 });
      await updateDoc(doc(db, 'bookings', 'L1'), { breakdown: { note: 'axle', replacementRequested: replacement, reportedAt: Timestamp.now() } });
    });
  }

  test('the driver moves the trip to another of their vehicles after a breakdown', async () => {
    await seedBroken();
    const ref = doc(as('driver1'), 'bookings', 'L1');
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), swap()));
    await assertFails(updateDoc(doc(as('driver2'), 'bookings', 'L1'), swap()));
    await assertFails(updateDoc(ref, swap({ vehicleNumber: 'WRONG' })));
    await assertFails(updateDoc(ref, swap({ replacedVehicleIds: [] })));
    await assertFails(updateDoc(ref, swap({ vehicleId: 'v1', vehicleNumber: 'MH12AB1234' }))); // same vehicle
    await assertFails(updateDoc(ref, swap({ vehicleId: 'v2', vehicleNumber: 'KA01CD5678' }))); // driver2's vehicle
    await assertFails(updateDoc(ref, { ...swap(), status: 'delivered' }));
    await assertFails(updateDoc(ref, { ...swap(), budget: 1 }));
    await assertSucceeds(updateDoc(ref, swap()));
  });

  test('without a replacement request the vehicle cannot be changed; a vehicle that is too small is refused', async () => {
    await seedBroken(false);
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), swap()));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { breakdown: { note: 'x', replacementRequested: true, reportedAt: Timestamp.now() } }));
    await seed((db) => updateDoc(doc(db, 'vehicles', 'v3'), { capacity: 2 }));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), swap()));
  });
});

describe('driver network: presence, connections, groups, chat', () => {
  const presence = (over = {}) => ({ name: 'Ramesh', mode: 'nearby', lat: 18.52, lng: 73.86, geohash: 'te7ud2', sharedUntil: Timestamp.fromMillis(Date.now() + 3600000), updatedAt: serverTimestamp(), ...over });
  const link = (a, b, over = {}) => ({ members: [a, b].sort(), requestedBy: a, requesterName: 'A', targetName: 'B', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
  const card = (over = {}) => ({ loadId: 'L1', pickup: 'Pune', drop: 'Delhi', cargoType: 'FMCG', weight: 10, vehicleType: '20ft', budgetPaise: 5000000, ...over });
  const msg = (uid, over = {}) => ({ senderId: uid, senderName: 'R', text: 'hello', flagged: false, createdAt: serverTimestamp(), ...over });

  beforeEach(async () => {
    await seed(async (db) => {
      for (const u of ['d1', 'd2', 'd3']) await setDoc(doc(db, 'users', u), { phone: '+91', role: 'driver', selectedRole: 'driver' });
      await setDoc(doc(db, 'users', 'c1'), { phone: '+91', role: 'customer', selectedRole: 'customer' });
    });
  });

  test('presence: a driver publishes a rounded, expiring position; others see nearby only', async () => {
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence()));
    await assertFails(setDoc(doc(as('d2'), 'driver_presence', 'd1'), presence())); // not theirs
    await assertFails(setDoc(doc(as('c1'), 'driver_presence', 'c1'), presence())); // customers do not publish
    await assertFails(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence({ sharedUntil: Timestamp.fromMillis(Date.now() + 3 * 86400000) }))); // over 24 h
    await assertFails(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence({ sharedUntil: Timestamp.fromMillis(Date.now() - 1000) })));
    await assertFails(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence({ mode: 'everyone' })));
    await assertFails(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence({ extra: 1 })));
    await assertFails(setDoc(doc(as('d1'), 'driver_presence', 'd1'), { name: 'R', mode: 'hidden', lat: 1, lng: 1, updatedAt: serverTimestamp() })); // hidden stores no position
    await assertSucceeds(getDoc(doc(as('d2'), 'driver_presence', 'd1')));
    const list = query(collection(as('d2'), 'driver_presence'), where('mode', '==', 'nearby'), where('geohash', '>=', 'te7u'), where('geohash', '<', 'te7u~'));
    await assertSucceeds(getDocs(list));
    await assertFails(getDocs(query(collection(as('d2'), 'driver_presence'), where('mode', '==', 'connections'))));
    await assertFails(getDocs(collection(as('d2'), 'driver_presence')));
  });

  test('presence: connections mode is read by connected drivers only; hidden and trip store no position', async () => {
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_presence', 'd1'), presence({ mode: 'connections' })));
    await assertFails(getDoc(doc(as('d2'), 'driver_presence', 'd1')));
    await seed((db) => setDoc(doc(db, 'driver_links', 'd1_d2'), link('d1', 'd2', { status: 'connected' })));
    await assertSucceeds(getDoc(doc(as('d2'), 'driver_presence', 'd1')));
    await assertFails(getDoc(doc(as('d3'), 'driver_presence', 'd1')));
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_presence', 'd1'), { name: 'R', mode: 'hidden', updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('d2'), 'driver_presence', 'd1')));
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_presence', 'd1'), { name: 'R', mode: 'trip', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(doc(as('d1'), 'driver_presence', 'd1')));
  });

  test('connections: request, accept by the other driver only, either ends it, blocked cannot ask', async () => {
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_links', 'd1_d2'), link('d1', 'd2')));
    await assertFails(setDoc(doc(as('d1'), 'driver_links', 'd1_d3'), link('d1', 'd2'))); // id must match the pair
    await assertFails(setDoc(doc(as('d3'), 'driver_links', 'd1_d2'), link('d1', 'd2', { requestedBy: 'd3' }))); // not a member
    await assertFails(setDoc(doc(as('d1'), 'driver_links', 'd1_d3'), link('d1', 'd3', { status: 'connected' }))); // cannot self-accept
    await assertFails(updateDoc(doc(as('d1'), 'driver_links', 'd1_d2'), { status: 'connected', updatedAt: serverTimestamp() })); // requester cannot accept
    await assertFails(updateDoc(doc(as('d3'), 'driver_links', 'd1_d2'), { status: 'connected', updatedAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('d3'), 'driver_links', 'd1_d2')));
    await assertSucceeds(updateDoc(doc(as('d2'), 'driver_links', 'd1_d2'), { status: 'connected', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('d2'), 'driver_links', 'd1_d2'), { requestedBy: 'd2', updatedAt: serverTimestamp() }));
    await assertSucceeds(getDocs(query(collection(as('d2'), 'driver_links'), where('members', 'array-contains', 'd2'))));
    await assertFails(deleteDoc(doc(as('d3'), 'driver_links', 'd1_d2')));
    await assertSucceeds(deleteDoc(doc(as('d2'), 'driver_links', 'd1_d2')));
    await seed((db) => setDoc(doc(db, 'users', 'd3', 'blocked', 'd1'), { createdAt: Timestamp.now() }));
    await assertFails(setDoc(doc(as('d1'), 'driver_links', 'd1_d3'), link('d1', 'd3')));
  });

  test('driver chat: only connected members, text or a shaped load card, no edits', async () => {
    await seed((db) => setDoc(doc(db, 'driver_links', 'd1_d2'), link('d1', 'd2')));
    await assertFails(setDoc(doc(as('d1'), 'driver_links', 'd1_d2', 'messages', 'm0'), msg('d1'))); // still pending
    await seed((db) => updateDoc(doc(db, 'driver_links', 'd1_d2'), { status: 'connected' }));
    const m = (uid, id) => doc(as(uid), 'driver_links', 'd1_d2', 'messages', id);
    await assertSucceeds(setDoc(m('d1', 'm1'), msg('d1')));
    await assertSucceeds(setDoc(m('d2', 'm2'), msg('d2', { text: '', loadCard: card() })));
    await assertSucceeds(setDoc(m('d1', 'm2b'), msg('d1', { loadCard: (({ budgetPaise, ...rest }) => rest)(card()) })));
    await assertFails(setDoc(m('d1', 'm3'), msg('d2'))); // sender must be me
    await assertFails(setDoc(m('d3', 'm4'), msg('d3'))); // not a member
    await assertFails(setDoc(m('d1', 'm5'), msg('d1', { text: '' }))); // nothing to send
    await assertFails(setDoc(m('d1', 'm6'), msg('d1', { text: 'x'.repeat(501) })));
    await assertFails(setDoc(m('d1', 'm7'), msg('d1', { loadCard: card({ weight: 0 }) })));
    await assertFails(setDoc(m('d1', 'm8'), msg('d1', { loadCard: card({ phone: '9999999999' }) })));
    await assertFails(setDoc(m('d1', 'm9'), msg('d1', { loadCard: card({ budgetPaise: 1.5 }) })));
    await assertSucceeds(getDoc(m('d2', 'm1')));
    await assertFails(getDoc(m('d3', 'm1')));
    await assertFails(updateDoc(m('d1', 'm1'), { text: 'edited' }));
    await assertFails(deleteDoc(m('d1', 'm1')));
    await seed((db) => setDoc(doc(db, 'users', 'd2', 'blocked', 'd1'), { createdAt: Timestamp.now() }));
    await assertFails(setDoc(m('d1', 'm10'), msg('d1')));
  });

  const group = (over = {}) => ({ name: 'Pune-Delhi convoy', kind: 'convoy', ownerId: 'd1', memberIds: ['d1'], createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });

  test('groups: owner creates alone, adds only connected drivers, members leave, owner deletes', async () => {
    await assertSucceeds(setDoc(doc(as('d1'), 'driver_groups', 'g1'), group()));
    await assertFails(setDoc(doc(as('d1'), 'driver_groups', 'g2'), group({ memberIds: ['d1', 'd2'] }))); // alone at first
    await assertFails(setDoc(doc(as('d1'), 'driver_groups', 'g3'), group({ kind: 'party' })));
    await assertFails(setDoc(doc(as('d1'), 'driver_groups', 'g4'), group({ name: '' })));
    await assertFails(setDoc(doc(as('d2'), 'driver_groups', 'g5'), group())); // owner must be me
    const add = (uid, ids) => updateDoc(doc(as(uid), 'driver_groups', 'g1'), { memberIds: ids, updatedAt: serverTimestamp() });
    await assertFails(add('d1', ['d1', 'd2'])); // not connected
    await seed((db) => setDoc(doc(db, 'driver_links', 'd1_d2'), link('d1', 'd2', { status: 'connected' })));
    await assertFails(add('d2', ['d1', 'd2'])); // a non-member cannot add themselves
    await assertFails(add('d1', ['d1', 'd2', 'd3'])); // one at a time
    await assertSucceeds(add('d1', ['d1', 'd2']));
    await assertSucceeds(getDoc(doc(as('d2'), 'driver_groups', 'g1')));
    await assertFails(getDoc(doc(as('d3'), 'driver_groups', 'g1')));
    await assertFails(add('d2', ['d1', 'd2', 'd3'])); // members cannot invite
    const gm = (uid, id) => doc(as(uid), 'driver_groups', 'g1', 'messages', id);
    await assertSucceeds(setDoc(gm('d2', 'm1'), msg('d2', { loadCard: card() })));
    await assertSucceeds(getDoc(gm('d1', 'm1')));
    await assertFails(setDoc(gm('d3', 'm2'), msg('d3')));
    await assertFails(getDoc(gm('d3', 'm1')));
    await assertFails(add('d1', ['d2'])); // owner stays
    await assertSucceeds(add('d2', ['d1'])); // d2 leaves
    await assertFails(setDoc(gm('d2', 'm3'), msg('d2'))); // and can no longer write
    await assertFails(deleteDoc(doc(as('d2'), 'driver_groups', 'g1')));
    await assertSucceeds(deleteDoc(doc(as('d1'), 'driver_groups', 'g1')));
  });
});

describe('trip alerts, evidence audit and document views', () => {
  const ev = (type, over = {}) => ({ type, actorId: 'driver1', bookingId: 'L1', data: { kind: 'pickup_gps' }, createdAt: serverTimestamp(), ...over });
  const notif = (over = {}) => ({ userId: 'customer1', type: 'driver_arriving_soon', message: 'Pune → Delhi', relatedId: 'L1', read: false, createdAt: serverTimestamp(), ...over });

  test('evidence and doc_view events: only a party of that booking writes them', async () => {
    await seedBooking('loading');
    await assertSucceeds(addDoc(collection(as('driver1'), 'audit_events'), ev('evidence')));
    await assertSucceeds(addDoc(collection(as('customer1'), 'audit_events'), ev('doc_view', { actorId: 'customer1', data: { doc: 'cargo_docs' } })));
    await assertFails(addDoc(collection(as('driver2'), 'audit_events'), ev('evidence', { actorId: 'driver2' }))); // not a party
    await assertFails(addDoc(collection(as('driver1'), 'audit_events'), (({ bookingId, ...rest }) => rest)(ev('evidence')))); // needs a booking
    await assertFails(addDoc(collection(as('driver1'), 'audit_events'), ev('evidence', { actorId: 'customer1' }))); // self-attributed
    await assertFails(addDoc(collection(as('driver1'), 'audit_events'), ev('evidence', { bookingId: 'NOPE' })));
  });

  test('arriving and chat notifications: to the other party of the booking only; a second write to the same id is refused', async () => {
    await seedBooking('driver_arriving');
    await assertSucceeds(setDoc(doc(as('driver1'), 'notifications', 'arrive_L1'), notif()));
    await assertFails(setDoc(doc(as('driver1'), 'notifications', 'arrive_L1'), notif())); // already exists: only 'read' may change, by the owner
    await assertSucceeds(addDoc(collection(as('customer1'), 'notifications'), notif({ userId: 'driver1', type: 'chat_message' })));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif({ userId: 'driver2' }))); // not in the booking
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif({ type: 'made_up' })));
    await assertFails(addDoc(collection(as('driver2'), 'notifications'), notif({ userId: 'customer1' }))); // not a party
  });

  test('gps_mismatch risk signal: self-attributed, with the booking', async () => {
    await assertSucceeds(addDoc(collection(as('driver1'), 'risk_signals'), { uid: 'driver1', type: 'gps_mismatch', bookingId: 'L1', note: 'delivery GPS 900 km from Delhi', createdAt: serverTimestamp() }));
    await assertFails(addDoc(collection(as('driver1'), 'risk_signals'), { uid: 'driver2', type: 'gps_mismatch', bookingId: 'L1', createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('driver1'), 'risk_signals', 'x')));
  });
});

describe('UPI id, advance, e-way validity, container handover, double confirms', () => {
  const bk = (db, data) => updateDoc(doc(db, 'bookings', 'L1'), { updatedAt: serverTimestamp(), ...data });

  test('driver shares a valid UPI id on the booking; nobody else, nothing malformed', async () => {
    await seedBooking('accepted');
    await assertSucceeds(bk(as('driver1'), { payUpiId: 'ravi.k@okaxis' }));
    await assertFails(bk(as('driver1'), { payUpiId: 'not a upi' }));
    await assertFails(bk(as('driver1'), { payUpiId: 'x@y' }));
    await assertFails(bk(as('customer1'), { payUpiId: 'ravi.k@okaxis' }));
    await assertFails(bk(as('driver2'), { payUpiId: 'ravi.k@okaxis' }));
  });

  test('advance: customer records once (Re 1 up to the fare), driver confirms once', async () => {
    await seedBooking('accepted');
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { agreedFarePaise: 1800000 }));
    const rec = (db, paise = 500000, extra = {}) => bk(db, { advancePaise: paise, advanceMarkedAt: serverTimestamp(), ...extra });
    await assertFails(rec(as('driver1')));
    await assertFails(rec(as('customer1'), 99));
    await assertFails(rec(as('customer1'), 1800000)); // not below the fare
    await assertFails(rec(as('customer1'), 1000.5));
    await assertFails(bk(as('customer1'), { advancePaise: 500000 })); // needs the server time
    await assertFails(bk(as('driver1'), { advanceConfirmedAt: serverTimestamp() })); // nothing to confirm yet
    await assertSucceeds(rec(as('customer1')));
    await assertFails(rec(as('customer1'), 600000)); // once
    await assertFails(bk(as('customer1'), { advanceConfirmedAt: serverTimestamp() })); // only the driver
    await assertSucceeds(bk(as('driver1'), { advanceConfirmedAt: serverTimestamp() }));
    await assertFails(bk(as('driver1'), { advanceConfirmedAt: serverTimestamp() })); // once
  });

  test('advance is closed after delivery or once the payment is marked', async () => {
    await seedBooking('delivered');
    await assertFails(bk(as('customer1'), { advancePaise: 500000, advanceMarkedAt: serverTimestamp() }));
  });

  test('e-way bill validity date: timestamp, with a number, at most a year ahead', async () => {
    await seedBooking('in_transit');
    const week = Timestamp.fromMillis(Date.now() + 7 * 86400000);
    await assertSucceeds(bk(as('customer1'), { ewayBillNo: '123456789012', ewayValidUntil: week }));
    await assertSucceeds(bk(as('driver1'), { ewayBillNo: '123456789012', ewayValidUntil: week }));
    await assertFails(bk(as('driver1'), { ewayBillNo: '123456789012', ewayValidUntil: 'tomorrow' }));
    await assertFails(bk(as('driver1'), { ewayBillNo: '123456789012', ewayValidUntil: Timestamp.fromMillis(Date.now() + 400 * 86400000) }));
    await assertFails(bk(as('driver1'), { ewayBillNo: '', ewayValidUntil: week }));
    await assertFails(bk(as('driver2'), { ewayBillNo: '123456789012' }));
  });

  describe('handover', () => {
    const side = (uid, bookingId, over = {}) => ({ driverId: uid, bookingId, sealNumber: 'SL-9', note: '', at: serverTimestamp(), ...over });
    const leg1 = (over = {}, sideOver = {}) => ({ shipmentId: 's1', leg1: { ...side('driver1', 'L1'), containerNumber: 'CSQU3054383', ...sideOver }, createdAt: serverTimestamp(), ...over });

    async function seedLegs(status = 'unloading') {
      await seedBooking(status);
      await seed(async (db) => {
        await setDoc(doc(db, 'shipments', 's1'), { ownerId: 'customer1', kind: 'export', origin: 'A', hub: 'B', destination: 'C', containerNumber: '', sealNumber: '', leg1LoadId: 'L1', leg2LoadId: 'L2', createdAt: Timestamp.now() });
        await updateDoc(doc(db, 'loads', 'L1'), { shipmentId: 's1', shipmentLeg: 1 });
        await setDoc(doc(db, 'loads', 'L2'), { ...LOAD, status: 'matched', driverId: 'driver2', bookingId: 'L2', shipmentId: 's1', shipmentLeg: 2 });
        await setDoc(doc(db, 'bookings', 'L2'), { ...bookingFor('L2', { driverId: 'driver2', vehicleId: 'v2' }), status: 'accepted', timeline: {} });
      });
    }

    test('leg 1 driver hands over from unloading; shape and identity are checked', async () => {
      await seedLegs('loading');
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1())); // still loading
      await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'unloading' }));
      await assertFails(setDoc(doc(as('driver2'), 'handovers', 's1'), leg1())); // not their trip
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1({}, { driverId: 'driver2' })));
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1({}, { containerNumber: 'BAD' })));
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1({}, { sealNumber: 'no spaces!' })));
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1({}, { bookingId: 'L2' })));
      await assertFails(setDoc(doc(as('driver1'), 'handovers', 's2'), leg1())); // id must match the shipment
      await assertSucceeds(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1()));
    });

    test('leg 2 driver confirms once, the rules compute whether the seal matches; read by the two drivers, the shipment owner and admins', async () => {
      await seedLegs();
      await assertSucceeds(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1()));
      const confirm = (uid, over = {}) => updateDoc(doc(as(uid), 'handovers', 's1'), { leg2: { ...side(uid, 'L2'), sealMatches: true, ...over } });
      await assertFails(confirm('driver1')); // leg 1 driver is not on leg 2
      await assertFails(confirm('driver3'));
      await assertFails(confirm('driver2', { sealMatches: false })); // seals match, so the flag must say so
      await assertFails(confirm('driver2', { sealNumber: 'OTHER' })); // different seal but flag says match
      await assertSucceeds(confirm('driver2'));
      await assertFails(confirm('driver2')); // once
      await assertFails(updateDoc(doc(as('driver1'), 'handovers', 's1'), { leg1: side('driver1', 'L1') })); // leg 1 is frozen
      for (const u of ['driver1', 'driver2', 'customer1']) await assertSucceeds(getDoc(doc(as(u), 'handovers', 's1')));
      await assertSucceeds(getDoc(doc(asAdmin(), 'handovers', 's1')));
      await assertFails(getDoc(doc(as('driver3'), 'handovers', 's1')));
      await assertFails(deleteDoc(doc(as('driver1'), 'handovers', 's1')));
    });

    test('a different seal at leg 2 is accepted only with sealMatches false', async () => {
      await seedLegs();
      await assertSucceeds(setDoc(doc(as('driver1'), 'handovers', 's1'), leg1()));
      await assertSucceeds(updateDoc(doc(as('driver2'), 'handovers', 's1'), { leg2: { ...side('driver2', 'L2', { sealNumber: 'SL-1' }), sealMatches: false } }));
    });
  });

  test('double confirm of a payment and of the ledger lines is refused', async () => {
    await seedBooking('delivered');
    await updateDoc(doc(as('customer1'), 'bookings', 'L1'), { paymentStatus: 'customer_marked_paid', paidAmountPaise: 2500000, paymentMarkedAt: serverTimestamp(), updatedAt: serverTimestamp() });
    const dr = as('driver1');
    const confirm = () => {
      const b = writeBatch(dr);
      b.update(doc(dr, 'bookings', 'L1'), { paymentStatus: 'driver_confirmed', paymentConfirmedAt: serverTimestamp(), updatedAt: serverTimestamp() });
      b.set(doc(dr, 'ledger', 'L1_trip_earning'), { driverId: 'driver1', bookingId: 'L1', type: 'trip_earning', amountPaise: 2500000, createdAt: serverTimestamp() });
      b.set(doc(dr, 'ledger', 'L1_platform_commission'), { driverId: 'driver1', bookingId: 'L1', type: 'platform_commission', amountPaise: -125000, createdAt: serverTimestamp() });
      return b.commit();
    };
    await assertSucceeds(confirm());
    await assertFails(confirm());
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { paymentStatus: 'customer_marked_paid', paidAmountPaise: 1, paymentMarkedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });
});

describe('business roles, approvals, contracts, pool, expenses, support', () => {
  const asPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
  const PHONE = '+919876543210';
  const mem = (uid, role) => ({ ownerId: 'owner1', ownerName: 'Acme', memberId: uid, memberName: uid, memberPhone: '+919800000000', role, active: true, createdAt: Timestamp.now() });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', 'owner1'), { role: 'customer', selectedRole: 'customer' });
      for (const [uid, role] of [['mgr', 'manager'], ['dsp', 'dispatch'], ['acc', 'accounts'], ['vwr', 'viewer'], ['bkr', 'booker']]) {
        await setDoc(doc(db, 'users', uid), { role: 'customer', selectedRole: 'customer' });
        await setDoc(doc(db, 'business_members', `owner1_${uid}`), mem(uid, role));
      }
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
  });

  test('invites carry a role; the member document must copy it; the owner changes it later', async () => {
    const invite = (role) => ({ ownerId: 'owner1', ownerName: 'Acme', phone: PHONE, status: 'pending', role, createdAt: serverTimestamp() });
    await assertFails(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919876543210'), invite('ceo')));
    await assertFails(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919876543210'), invite('owner')));
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_invites', 'owner1_919876543210'), invite('viewer')));
    await seed((db) => updateDoc(doc(db, 'business_invites', 'owner1_919876543210'), { status: 'accepted' }));
    await seed((db) => setDoc(doc(db, 'users', 'newbie'), { role: 'customer', selectedRole: 'customer' }));
    const join = (role) => setDoc(doc(asPhone('newbie', PHONE), 'business_members', 'owner1_newbie'), { ownerId: 'owner1', ownerName: 'Acme', memberId: 'newbie', memberName: 'N', memberPhone: PHONE, role, active: true, createdAt: serverTimestamp() });
    await assertFails(join('manager')); // the invite said viewer
    await assertSucceeds(join('viewer'));
    await assertSucceeds(updateDoc(doc(as('owner1'), 'business_members', 'owner1_newbie'), { role: 'accounts' }));
    await assertFails(updateDoc(doc(as('owner1'), 'business_members', 'owner1_newbie'), { role: 'owner' }));
    await assertFails(updateDoc(doc(as('newbie'), 'business_members', 'owner1_newbie'), { role: 'manager' })); // members cannot promote themselves
    await assertFails(updateDoc(doc(as('mgr'), 'business_members', 'owner1_newbie'), { role: 'manager' }));
  });

  test('settings: owner writes the approval limit, members read it, others nothing', async () => {
    const s = (over = {}) => ({ ownerId: 'owner1', approvalLimitPaise: 2000000, updatedAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_settings', 'owner1'), s()));
    await assertFails(setDoc(doc(as('mgr'), 'business_settings', 'owner1'), s()));
    await assertFails(setDoc(doc(as('owner1'), 'business_settings', 'owner1'), s({ approvalLimitPaise: -1 })));
    await assertFails(setDoc(doc(as('owner1'), 'business_settings', 'owner1'), s({ approvalLimitPaise: 1.5 })));
    await assertSucceeds(getDoc(doc(as('vwr'), 'business_settings', 'owner1')));
    await assertFails(getDoc(doc(as('customer9'), 'business_settings', 'owner1')));
  });

  describe('loads', () => {
    const post = (uid, over) => addDoc(collection(as(uid), 'loads'), { ...LOAD, shipperId: uid, createdAt: serverTimestamp(), businessId: 'owner1', ...over });

    test('only booker, manager, dispatch and the owner post for the company', async () => {
      for (const u of ['bkr', 'mgr', 'dsp', 'owner1']) await assertSucceeds(post(u));
      for (const u of ['acc', 'vwr', 'customer9']) await assertFails(post(u));
    });

    test('over the limit a member load must wait; owner and manager post freely; the status cannot be faked', async () => {
      await seed((db) => setDoc(doc(db, 'business_settings', 'owner1'), { ownerId: 'owner1', approvalLimitPaise: 2000000, updatedAt: Timestamp.now() }));
      await assertFails(post('bkr', { budget: 50000 })); // open over the limit
      await assertSucceeds(post('bkr', { budget: 50000, status: 'awaiting_approval' }));
      await assertFails(post('bkr', { budget: 10000, status: 'awaiting_approval' })); // under the limit: not waiting
      await assertSucceeds(post('bkr', { budget: 10000 }));
      await assertSucceeds(post('mgr', { budget: 50000 }));
      await assertSucceeds(post('owner1', { budget: 50000 }));
      await assertFails(post('owner1', { budget: 50000, status: 'awaiting_approval' }));
      await assertSucceeds(post('dsp', { budget: null, estimate: { total: 500000, tripFare: 500000, distanceKm: 100 } })); // under by estimate
      await assertFails(post('dsp', { budget: null, estimate: { total: 5000000, tripFare: 5000000, distanceKm: 100 } }));
    });

    test('owner and manager approve or reject; the poster, dispatch and others cannot; the poster can cancel', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'business_settings', 'owner1'), { ownerId: 'owner1', approvalLimitPaise: 2000000, updatedAt: Timestamp.now() });
        for (const id of ['W1', 'W2', 'W3', 'W4']) await setDoc(doc(db, 'loads', id), { ...LOAD, shipperId: 'bkr', businessId: 'owner1', budget: 50000, status: 'awaiting_approval' });
      });
      const decide = (uid, id, over) => updateDoc(doc(as(uid), 'loads', id), { status: 'open', approval: { by: uid, at: serverTimestamp(), decision: 'approved' }, updatedAt: serverTimestamp(), ...over });
      await assertFails(decide('bkr', 'W1')); // the poster cannot approve their own load
      await assertFails(updateDoc(doc(as('bkr'), 'loads', 'W1'), { status: 'open' }));
      await assertFails(decide('dsp', 'W1'));
      await assertFails(decide('customer9', 'W1'));
      await assertFails(decide('mgr', 'W1', { approval: { by: 'owner1', at: serverTimestamp(), decision: 'approved' } })); // not as someone else
      await assertSucceeds(decide('mgr', 'W1'));
      await assertSucceeds(decide('owner1', 'W2'));
      await assertFails(decide('mgr', 'W1')); // already open
      await assertFails(decide('mgr', 'W3', { status: 'closed' })); // reject needs decision rejected and cancelled
      await assertSucceeds(decide('mgr', 'W3', { status: 'closed', cancelled: true, approval: { by: 'mgr', at: serverTimestamp(), decision: 'rejected' } }));
      await assertSucceeds(updateDoc(doc(as('bkr'), 'loads', 'W4'), { status: 'closed', cancelled: true, updatedAt: serverTimestamp() }));
    });

    test('every active member reads the company loads and bookings; strangers do not; lists work', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'loads', 'C1'), { ...LOAD, shipperId: 'bkr', businessId: 'owner1', status: 'awaiting_approval' });
        await setDoc(doc(db, 'bookings', 'C1'), { ...bookingFor('C1'), businessId: 'owner1', timeline: {} });
      });
      for (const u of ['vwr', 'acc', 'dsp', 'mgr', 'owner1']) {
        await assertSucceeds(getDoc(doc(as(u), 'loads', 'C1')));
        await assertSucceeds(getDoc(doc(as(u), 'bookings', 'C1')));
      }
      await assertFails(getDoc(doc(as('customer9'), 'loads', 'C1')));
      await assertFails(getDoc(doc(as('customer9'), 'bookings', 'C1')));
      await assertSucceeds(getDocs(query(collection(as('vwr'), 'bookings'), where('businessId', '==', 'owner1'))));
      await assertSucceeds(getDocs(query(collection(as('mgr'), 'loads'), where('businessId', '==', 'owner1'), where('status', '==', 'awaiting_approval'))));
      await assertFails(getDocs(query(collection(as('customer9'), 'bookings'), where('businessId', '==', 'owner1'))));
    });
  });

  test('contract vehicles: manager and owner write, every member reads, nobody edits', async () => {
    const c = (uid, over = {}) => ({ ownerId: 'owner1', vehicleNumber: 'MH12AB1234', vehicleType: '20ft', vendorName: 'Ram Transport', ratePerTripPaise: 1800000, validUntil: Timestamp.fromMillis(Date.now() + 86400000), note: '', addedBy: uid, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('mgr'), 'business_contracts', 'c1'), c('mgr')));
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_contracts', 'c2'), c('owner1')));
    await assertFails(setDoc(doc(as('dsp'), 'business_contracts', 'c3'), c('dsp')));
    await assertFails(setDoc(doc(as('acc'), 'business_contracts', 'c4'), c('acc')));
    await assertFails(setDoc(doc(as('customer9'), 'business_contracts', 'c5'), c('customer9')));
    await assertFails(setDoc(doc(as('mgr'), 'business_contracts', 'c6'), c('mgr', { ratePerTripPaise: -1 })));
    await assertFails(setDoc(doc(as('mgr'), 'business_contracts', 'c7'), c('mgr', { vendorName: 'R' })));
    await assertFails(setDoc(doc(as('mgr'), 'business_contracts', 'c8'), c('owner1'))); // addedBy must be me
    await assertSucceeds(getDoc(doc(as('vwr'), 'business_contracts', 'c1')));
    await assertFails(getDoc(doc(as('customer9'), 'business_contracts', 'c1')));
    await assertFails(updateDoc(doc(as('mgr'), 'business_contracts', 'c1'), { vendorName: 'Other' }));
    await assertFails(deleteDoc(doc(as('dsp'), 'business_contracts', 'c1')));
    await assertSucceeds(deleteDoc(doc(as('mgr'), 'business_contracts', 'c1')));
  });

  test('approved driver pool: manager and dispatch manage it, id is owner_driver', async () => {
    const p = (uid, over = {}) => ({ ownerId: 'owner1', driverId: 'd1', driverName: 'Ramesh', vehicleNumber: 'MH12AB1234', addedBy: uid, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('dsp'), 'business_pool', 'owner1_d1'), p('dsp')));
    await assertSucceeds(setDoc(doc(as('mgr'), 'business_pool', 'owner1_d2'), p('mgr', { driverId: 'd2' })));
    await assertFails(setDoc(doc(as('acc'), 'business_pool', 'owner1_d3'), p('acc', { driverId: 'd3' })));
    await assertFails(setDoc(doc(as('bkr'), 'business_pool', 'owner1_d4'), p('bkr', { driverId: 'd4' })));
    await assertFails(setDoc(doc(as('dsp'), 'business_pool', 'owner1_zz'), p('dsp', { driverId: 'd5' }))); // id mismatch
    await assertSucceeds(getDoc(doc(as('bkr'), 'business_pool', 'owner1_d1'))); // bookers read it to post to the pool
    await assertSucceeds(getDocs(query(collection(as('bkr'), 'business_pool'), where('ownerId', '==', 'owner1'))));
    await assertFails(getDoc(doc(as('customer9'), 'business_pool', 'owner1_d1')));
    await assertFails(deleteDoc(doc(as('vwr'), 'business_pool', 'owner1_d1')));
    await assertSucceeds(deleteDoc(doc(as('dsp'), 'business_pool', 'owner1_d1')));
  });

  test('expenses: manager and accounts write, viewer reads, dispatch and bookers see nothing', async () => {
    const e = (uid, over = {}) => ({ ownerId: 'owner1', kind: 'fuel', amountPaise: 450000, date: Timestamp.now(), costCenter: 'Plant 2', note: 'Kherki', addedBy: uid, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('acc'), 'business_expenses', 'e1'), e('acc')));
    await assertSucceeds(setDoc(doc(as('mgr'), 'business_expenses', 'e2'), e('mgr')));
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_expenses', 'e3'), e('owner1')));
    await assertFails(setDoc(doc(as('dsp'), 'business_expenses', 'e4'), e('dsp')));
    await assertFails(setDoc(doc(as('vwr'), 'business_expenses', 'e5'), e('vwr')));
    await assertFails(setDoc(doc(as('acc'), 'business_expenses', 'e6'), e('acc', { kind: 'beer' })));
    await assertFails(setDoc(doc(as('acc'), 'business_expenses', 'e7'), e('acc', { amountPaise: 0 })));
    await assertFails(setDoc(doc(as('acc'), 'business_expenses', 'e8'), e('acc', { amountPaise: 10.5 })));
    await assertFails(setDoc(doc(as('acc'), 'business_expenses', 'e9'), e('acc', { extra: 1 })));
    await assertSucceeds(getDoc(doc(as('vwr'), 'business_expenses', 'e1')));
    await assertSucceeds(getDocs(query(collection(as('vwr'), 'business_expenses'), where('ownerId', '==', 'owner1'))));
    await assertFails(getDoc(doc(as('dsp'), 'business_expenses', 'e1')));
    await assertFails(getDoc(doc(as('bkr'), 'business_expenses', 'e1')));
    await assertFails(updateDoc(doc(as('acc'), 'business_expenses', 'e1'), { amountPaise: 1 }));
    await assertFails(deleteDoc(doc(as('vwr'), 'business_expenses', 'e1')));
    await assertSucceeds(deleteDoc(doc(as('acc'), 'business_expenses', 'e1')));
  });

  test('statements: owner, manager and accounts save; viewer reads; dispatch does not', async () => {
    const st = (over = {}) => ({ ownerId: 'owner1', month: '2026-09', trips: 4, totalPaise: 425050, byCostCenter: { 'Plant 2': 350050 }, createdAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('owner1'), 'business_statements', 'owner1_2026-09'), st()));
    await assertSucceeds(setDoc(doc(as('acc'), 'business_statements', 'owner1_2026-09'), st()));
    await assertSucceeds(setDoc(doc(as('mgr'), 'business_statements', 'owner1_2026-08'), st({ month: '2026-08' })));
    await assertFails(setDoc(doc(as('vwr'), 'business_statements', 'owner1_2026-07'), st({ month: '2026-07' })));
    await assertFails(setDoc(doc(as('dsp'), 'business_statements', 'owner1_2026-07'), st({ month: '2026-07' })));
    await assertFails(setDoc(doc(as('customer9'), 'business_statements', 'owner1_2026-07'), st({ month: '2026-07' })));
    await assertSucceeds(getDoc(doc(as('vwr'), 'business_statements', 'owner1_2026-09')));
    await assertFails(getDoc(doc(as('dsp'), 'business_statements', 'owner1_2026-09')));
  });

  test('company tickets: members raise them, the owner, managers and accounts read them, others do not', async () => {
    const t = (uid, over = {}) => ({ userId: uid, category: 'other', priority: 'high', status: 'open', subject: 'Invoice question', description: '', businessId: 'owner1', escalationLevel: 0, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...over });
    await assertSucceeds(setDoc(doc(as('bkr'), 'tickets', 't1'), t('bkr')));
    await assertSucceeds(setDoc(doc(as('owner1'), 'tickets', 't2'), t('owner1')));
    await assertFails(setDoc(doc(as('customer9'), 'tickets', 't3'), t('customer9'))); // not a member
    await assertSucceeds(getDoc(doc(as('owner1'), 'tickets', 't1')));
    await assertSucceeds(getDoc(doc(as('mgr'), 'tickets', 't1')));
    await assertSucceeds(getDoc(doc(as('acc'), 'tickets', 't1')));
    await assertFails(getDoc(doc(as('dsp'), 'tickets', 't1')));
    await assertFails(getDoc(doc(as('vwr'), 'tickets', 't1')));
    await assertSucceeds(getDocs(query(collection(as('mgr'), 'tickets'), where('businessId', '==', 'owner1'))));
    await assertSucceeds(getDoc(doc(asAdmin(), 'tickets', 't1')));
  });
});

describe('staff roles and risk signals', () => {
  const staff = (uid) => env.authenticatedContext(uid).firestore();

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
      await setDoc(doc(db, 'admins', 'ver1'), { role: 'verifier' });
      await setDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
      await setDoc(doc(db, 'admins', 'sup2'), { role: 'owner-of-the-universe' }); // unknown role = no staff powers
      await setDoc(doc(db, 'users', 'driver1'), { role: 'driver', selectedRole: 'driver', verificationStatus: 'pending', verified: false });
    });
  });

  test('driver verification: verifier and super; not support or ops', async () => {
    const verify = (db) => updateDoc(doc(db, 'users', 'driver1'), { verified: true, verificationStatus: 'approved', updatedAt: serverTimestamp() });
    await assertFails(verify(staff('sup1')));
    await assertFails(verify(staff('ops1')));
    await assertFails(verify(staff('sup2')));
    await assertSucceeds(verify(staff('ver1')));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'driver1'), { verified: false, verificationStatus: 'pending', updatedAt: serverTimestamp() })); // super (no role field)
  });

  test('risk tier: ops and super; not support or verifier', async () => {
    const hold = (db) => updateDoc(doc(db, 'users', 'driver1'), { riskTier: 'restricted', riskReason: 'burst', riskUpdatedAt: serverTimestamp() });
    await assertFails(hold(staff('sup1')));
    await assertFails(hold(staff('ver1')));
    await assertSucceeds(hold(staff('ops1')));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'driver1'), { riskTier: 'normal', riskReason: '', riskUpdatedAt: serverTimestamp() }));
  });

  test('tickets: support and super answer and change them; others read only', async () => {
    await seed((db) => setDoc(doc(db, 'tickets', 't1'), { userId: 'driver1', category: 'other', priority: 'normal', status: 'open', subject: 'Help me', description: '', escalationLevel: 0, createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
    const status = (db) => updateDoc(doc(db, 'tickets', 't1'), { status: 'in_progress', updatedAt: serverTimestamp() });
    const reply = (db) => addDoc(collection(db, 'tickets', 't1', 'replies'), { authorId: db.__uid, text: 'On it', fromAdmin: true, createdAt: serverTimestamp() });
    const asStaff = (uid) => { const d = staff(uid); d.__uid = uid; return d; };
    await assertSucceeds(getDoc(doc(staff('ver1'), 'tickets', 't1')));
    await assertFails(status(staff('ver1')));
    await assertFails(status(staff('ops1')));
    await assertFails(reply(asStaff('ver1')));
    await assertSucceeds(status(staff('sup1')));
    await assertSucceeds(reply(asStaff('sup1')));
    await assertSucceeds(status(asAdmin()));
  });

  test('config, plans and incentives are for super admins only', async () => {
    const cfg = (db) => setDoc(doc(db, 'config', 'pricing'), { platformFeePercent: 7 });
    await assertFails(cfg(staff('sup1')));
    await assertFails(cfg(staff('ops1')));
    await assertFails(cfg(staff('ver1')));
    await assertSucceeds(cfg(asAdmin()));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'risk'), { reviewScore: 40, holdScore: 60 }));
    await assertFails(setDoc(doc(staff('ops1'), 'config', 'risk'), { reviewScore: 1 }));
    await assertFails(updateDoc(doc(staff('sup1'), 'users', 'driver1'), { plan: 'pro', planUntil: Timestamp.fromMillis(Date.now() + 86400000), updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'driver1'), { plan: 'pro', planUntil: Timestamp.fromMillis(Date.now() + 86400000), updatedAt: serverTimestamp() }));
  });

  test('every staff role still reads what the panel lists', async () => {
    await seed((db) => setDoc(doc(db, 'risk_signals', 's1'), { uid: 'driver1', type: 'many_devices', createdAt: Timestamp.now() }));
    for (const u of ['sup1', 'ver1', 'ops1']) {
      await assertSucceeds(getDoc(doc(staff(u), 'risk_signals', 's1')));
      await assertSucceeds(getDoc(doc(staff(u), 'users', 'driver1')));
    }
    await assertFails(getDoc(doc(as('driver2'), 'risk_signals', 's1')));
  });

  test('many_devices is a signal a user writes about themselves', async () => {
    const sig = (uid, over = {}) => ({ uid, type: 'many_devices', deviceId: 'dev12345', note: '3 devices in 24 hours', createdAt: serverTimestamp(), ...over });
    await assertSucceeds(addDoc(collection(as('driver1'), 'risk_signals'), sig('driver1')));
    await assertFails(addDoc(collection(as('driver1'), 'risk_signals'), sig('driver2')));
    await assertFails(addDoc(collection(as('driver1'), 'risk_signals'), sig('driver1', { type: 'made_up' })));
  });
});

describe('assistant unknown questions', () => {
  const q = (uid, over = {}) => ({ text: 'weather today', userId: uid, role: 'customer', language: 'hindi', resolved: false, createdAt: serverTimestamp(), ...over });
  const staff = (uid) => env.authenticatedContext(uid).firestore();

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
      await setDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
    });
  });

  test('a signed-in user creates their own, valid question', async () => {
    await assertSucceeds(addDoc(collection(as('customer1'), 'assistant_unknown'), q('customer1')));
    await assertSucceeds(addDoc(collection(as('driver1'), 'assistant_unknown'), q('driver1', { role: 'driver' })));
    await assertFails(addDoc(collection(anon(), 'assistant_unknown'), q('customer1')));
  });

  test('refused: someone else, long or empty text, bad role, extra fields, resolved, wrong time', async () => {
    const add = (uid, over) => addDoc(collection(as(uid), 'assistant_unknown'), q(uid, over));
    await assertFails(addDoc(collection(as('customer1'), 'assistant_unknown'), q('driver1')));
    await assertFails(add('customer1', { text: 'a'.repeat(301) }));
    await assertSucceeds(add('customer1', { text: 'a'.repeat(300) }));
    await assertFails(add('customer1', { text: '' }));
    await assertFails(add('customer1', { text: 42 }));
    await assertFails(add('customer1', { role: 'admin' }));
    await assertFails(add('customer1', { language: 'x'.repeat(21) }));
    await assertFails(add('customer1', { extra: 1 }));
    await assertSucceeds(add('customer1', { expireAt: Timestamp.fromMillis(Date.now() + 180 * 86400000) })); // MASTER-5 Task 7 clean-up date
    await assertFails(add('customer1', { expireAt: Timestamp.fromMillis(Date.now() + 3000 * 86400000) }));
    await assertFails(add('customer1', { resolved: true }));
    await assertFails(add('customer1', { createdAt: Timestamp.fromMillis(1000) }));
  });

  test('only super and support admins read; the author cannot', async () => {
    await seed((db) => setDoc(doc(db, 'assistant_unknown', 'a1'), { text: 'x', userId: 'customer1', role: 'customer', language: 'english', resolved: false, createdAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(asAdmin(), 'assistant_unknown', 'a1')));
    await assertSucceeds(getDoc(doc(staff('sup1'), 'assistant_unknown', 'a1')));
    await assertSucceeds(getDocs(collection(staff('sup1'), 'assistant_unknown')));
    await assertFails(getDoc(doc(staff('ops1'), 'assistant_unknown', 'a1')));
    await assertFails(getDoc(doc(as('customer1'), 'assistant_unknown', 'a1')));
    await assertFails(getDocs(collection(as('customer1'), 'assistant_unknown')));
  });

  test('admins mark resolved only; nobody edits the text or deletes', async () => {
    await seed((db) => setDoc(doc(db, 'assistant_unknown', 'a1'), { text: 'x', userId: 'customer1', role: 'customer', language: 'english', resolved: false, createdAt: Timestamp.now() }));
    const done = (by) => ({ resolved: true, resolvedAt: serverTimestamp(), resolvedBy: by });
    await assertFails(updateDoc(doc(as('customer1'), 'assistant_unknown', 'a1'), done('customer1')));
    await assertFails(updateDoc(doc(staff('ops1'), 'assistant_unknown', 'a1'), done('ops1')));
    await assertFails(updateDoc(doc(staff('sup1'), 'assistant_unknown', 'a1'), { ...done('sup1'), text: 'changed' }));
    await assertFails(updateDoc(doc(staff('sup1'), 'assistant_unknown', 'a1'), done('someone-else')));
    await assertFails(updateDoc(doc(staff('sup1'), 'assistant_unknown', 'a1'), { resolved: false, resolvedAt: serverTimestamp(), resolvedBy: 'sup1' }));
    await assertSucceeds(updateDoc(doc(staff('sup1'), 'assistant_unknown', 'a1'), done('sup1')));
    await assertFails(deleteDoc(doc(asAdmin(), 'assistant_unknown', 'a1')));
    await assertFails(deleteDoc(doc(as('customer1'), 'assistant_unknown', 'a1')));
  });
});

describe('cancel reasons, declared value and feedback', () => {
  const CUSTOMER_REASONS = ['found_other', 'plan_changed', 'price_high', 'driver_delay', 'wrong_details', 'other'];
  const DRIVER_REASONS = ['vehicle_problem', 'load_mismatch', 'customer_unreachable', 'personal', 'price_low', 'other'];

  function shipperCancel(uid, extra = {}) {
    const db = as(uid);
    const b = writeBatch(db);
    b.update(doc(db, 'loads', 'L1'), { status: 'closed', cancelled: true, cancelledAt: serverTimestamp(), ...extra });
    b.set(doc(db, 'users', uid), { cancelCount: increment(1) }, { merge: true });
    return b.commit();
  }

  function driverCancel(cancellation) {
    const db = as('driver1');
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'L1'), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation, updatedAt: serverTimestamp() });
    b.update(doc(db, 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField(), matchedAt: deleteField(), reopenedAt: serverTimestamp() });
    b.set(doc(db, 'users', 'driver1'), { cancelCount: increment(1) }, { merge: true });
    return b.commit();
  }

  test('a customer cancelling an open load may name one of the customer reasons', async () => {
    for (const r of CUSTOMER_REASONS) {
      await env.clearFirestore();
      await seed((db) => setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' }));
      await seedOpenLoad();
      await assertSucceeds(shipperCancel('customer1', { cancelReason: r }));
    }
  });

  test('refused: a driver reason, a made-up code, a non-string, or a reason on a load that stays open', async () => {
    await seedOpenLoad();
    await assertFails(shipperCancel('customer1', { cancelReason: 'vehicle_problem' }));
    await assertFails(shipperCancel('customer1', { cancelReason: 'because' }));
    await assertFails(shipperCancel('customer1', { cancelReason: 5 }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { notes: 'x', cancelReason: 'other' }));
    await assertSucceeds(shipperCancel('customer1'));
  });

  test('a new load cannot carry a cancel reason', async () => {
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'N1'), { ...LOAD, cancelReason: 'other' }));
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'N2'), { ...LOAD }));
  });

  test('a driver cancelling a booking may name a driver reason, never a customer one', async () => {
    for (const r of DRIVER_REASONS) {
      await env.clearFirestore();
      await seed((db) => setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' }));
      await seedBooking();
      await assertSucceeds(driverCancel({ by: 'driver', chargePaise: 0, reason: r }));
    }
    await env.clearFirestore();
    await seed((db) => setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' }));
    await seedBooking();
    await assertFails(driverCancel({ by: 'driver', chargePaise: 0, reason: 'price_high' }));
    await assertFails(driverCancel({ by: 'driver', chargePaise: 0, reason: 'nope' }));
    await assertFails(driverCancel({ by: 'driver', chargePaise: 0, reason: 7 }));
    await assertFails(driverCancel({ by: 'driver', chargePaise: 0, reason: 'other', why: 'x' }));
  });

  test('a customer cancelling an advance booking: customer reasons only', async () => {
    const at = Timestamp.fromMillis(Date.now() + 2 * 86400000);
    const cancel = (reason) => {
      const db = as('customer1');
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'S1'), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation: { by: 'customer', chargePaise: 0, ...(reason ? { reason } : {}) }, updatedAt: serverTimestamp() });
      b.update(doc(db, 'loads', 'S1'), { status: 'closed', cancelled: true, cancelledAt: serverTimestamp() });
      b.set(doc(db, 'users', 'customer1'), { cancelCount: increment(1) }, { merge: true });
      return b.commit();
    };
    const seedS = () => seed(async (db) => {
      await setDoc(doc(db, 'loads', 'S1'), { ...LOAD, status: 'matched', driverId: 'driver1', bookingId: 'S1', scheduledAt: at });
      await setDoc(doc(db, 'bookings', 'S1'), { ...bookingFor('S1'), scheduledAt: at, status: 'accepted', timeline: {} });
      await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', selectedRole: 'customer', cancelCount: 0 });
    });
    await seedS();
    await assertFails(cancel('vehicle_problem'));
    await assertFails(cancel('nonsense'));
    await assertSucceeds(cancel('driver_delay'));
    await env.clearFirestore();
    await seed((db) => setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' }));
    await seedS();
    await assertSucceeds(cancel(null));
  });

  test('declared goods value: optional integer paise from 0 to 10 crore rupees; fixed after posting', async () => {
    const post = (id, extra) => setDoc(doc(as('customer1'), 'loads', id), { ...LOAD, ...extra });
    await assertSucceeds(post('V1', { declaredValuePaise: 5000000 }));
    await assertSucceeds(post('V2', { declaredValuePaise: 0 }));
    await assertSucceeds(post('V3', { declaredValuePaise: 10000000000 }));
    await assertFails(post('V4', { declaredValuePaise: 10000000001 }));
    await assertFails(post('V5', { declaredValuePaise: -1 }));
    await assertFails(post('V6', { declaredValuePaise: 12.5 }));
    await assertFails(post('V7', { declaredValuePaise: '500' }));
    await assertSucceeds(post('V8', {}));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'V1'), { declaredValuePaise: 1 }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'V8'), { declaredValuePaise: 100 }));
  });

  describe('feedback', () => {
    const fb = (uid, over = {}) => ({ userId: uid, role: 'customer', rating: 4, category: 'app', text: 'Nice app', appVersion: '1.0.0', createdAt: serverTimestamp(), ...over });
    const staff = (uid) => env.authenticatedContext(uid).firestore();

    beforeEach(async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
        await setDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
      });
    });

    test('a signed-in user sends their own feedback', async () => {
      await assertSucceeds(addDoc(collection(as('customer1'), 'feedback'), fb('customer1')));
      await assertSucceeds(addDoc(collection(as('driver1'), 'feedback'), fb('driver1', { role: 'driver', category: 'idea', text: '' })));
      await assertFails(addDoc(collection(anon(), 'feedback'), fb('customer1')));
    });

    test('refused: someone else, bad rating, bad category or role, long text, extra fields, wrong time', async () => {
      const add = (over) => addDoc(collection(as('customer1'), 'feedback'), fb('customer1', over));
      await assertFails(addDoc(collection(as('customer1'), 'feedback'), fb('driver1')));
      for (const rating of [0, 6, 3.5, '4']) await assertFails(add({ rating }));
      await assertFails(add({ category: 'rant' }));
      await assertFails(add({ role: 'admin' }));
      await assertSucceeds(add({ text: 'a'.repeat(500) }));
      await assertFails(add({ text: 'a'.repeat(501) }));
      await assertFails(add({ text: 9 }));
      await assertFails(add({ appVersion: 'v'.repeat(21) }));
      await assertFails(add({ extra: 1 }));
      await assertFails(add({ createdAt: Timestamp.fromMillis(1000) }));
    });

    test('only super and support admins read; nobody edits or deletes', async () => {
      await seed((db) => setDoc(doc(db, 'feedback', 'f1'), { userId: 'customer1', role: 'customer', rating: 5, category: 'app', text: 'x', appVersion: '1', createdAt: Timestamp.now() }));
      await assertSucceeds(getDoc(doc(asAdmin(), 'feedback', 'f1')));
      await assertSucceeds(getDocs(collection(staff('sup1'), 'feedback')));
      await assertFails(getDoc(doc(staff('ops1'), 'feedback', 'f1')));
      await assertFails(getDoc(doc(as('customer1'), 'feedback', 'f1')));
      await assertFails(updateDoc(doc(as('customer1'), 'feedback', 'f1'), { text: 'y' }));
      await assertFails(updateDoc(doc(asAdmin(), 'feedback', 'f1'), { text: 'y' }));
      await assertFails(deleteDoc(doc(asAdmin(), 'feedback', 'f1')));
      await assertFails(deleteDoc(doc(as('customer1'), 'feedback', 'f1')));
    });
  });
});

describe('admin tools: app errors, reply templates and bulk user changes', () => {
  const staff = (uid) => env.authenticatedContext(uid).firestore();
  const err = (over = {}) => ({ message: 'Null check operator used on a null value', screen: 'driver/driver_trip_screen.dart', kind: 'flutter', appVersion: '1.0.0+1', createdAt: serverTimestamp(), ...over });

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
      await setDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
      for (const u of ['u1', 'u2', 'u3']) await setDoc(doc(db, 'users', u), { name: u, riskTier: 'normal' });
    });
  });

  describe('app_errors', () => {
    test('a signed-in user logs a valid error', async () => {
      await assertSucceeds(addDoc(collection(as('driver1'), 'app_errors'), err()));
      await assertSucceeds(addDoc(collection(as('customer1'), 'app_errors'), err({ kind: 'async', screen: '' })));
      await assertFails(addDoc(collection(anon(), 'app_errors'), err()));
    });

    test('refused: extra fields (a user id), empty or long text, bad kind, long screen or version, wrong time', async () => {
      const add = (over) => addDoc(collection(as('driver1'), 'app_errors'), err(over));
      await assertFails(add({ userId: 'driver1' }));
      await assertFails(add({ message: '' }));
      await assertSucceeds(add({ message: 'a'.repeat(300) }));
      await assertFails(add({ message: 'a'.repeat(301) }));
      await assertFails(add({ message: 5 }));
      await assertFails(add({ kind: 'crash' }));
      await assertFails(add({ screen: 's'.repeat(61) }));
      await assertFails(add({ appVersion: 'v'.repeat(21) }));
      await assertFails(add({ createdAt: Timestamp.fromMillis(1000) }));
    });

    test('only super and ops admins read; nobody changes or deletes', async () => {
      await seed((db) => setDoc(doc(db, 'app_errors', 'e1'), { message: 'x', screen: 's', kind: 'flutter', appVersion: '1', createdAt: Timestamp.now() }));
      await assertSucceeds(getDoc(doc(asAdmin(), 'app_errors', 'e1')));
      await assertSucceeds(getDocs(collection(staff('ops1'), 'app_errors')));
      await assertFails(getDoc(doc(staff('sup1'), 'app_errors', 'e1')));
      await assertFails(getDoc(doc(as('driver1'), 'app_errors', 'e1')));
      await assertFails(updateDoc(doc(asAdmin(), 'app_errors', 'e1'), { message: 'y' }));
      await assertFails(deleteDoc(doc(asAdmin(), 'app_errors', 'e1')));
      await assertFails(deleteDoc(doc(as('driver1'), 'app_errors', 'e1')));
    });
  });

  describe('config/reply_templates', () => {
    const items = (n) => Array.from({ length: n }, (_, i) => ({ id: `t${i}`, title: `T${i}`, text: 'Hello' }));

    test('super admins save up to 20 templates; nobody else; everyone signed in reads', async () => {
      await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'reply_templates'), { items: items(20), updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(asAdmin(), 'config', 'reply_templates'), { items: items(21), updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(asAdmin(), 'config', 'reply_templates'), { items: items(2), other: 1, updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(asAdmin(), 'config', 'reply_templates'), { items: 'nope', updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(staff('sup1'), 'config', 'reply_templates'), { items: items(1), updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(as('driver1'), 'config', 'reply_templates'), { items: items(1), updatedAt: serverTimestamp() }));
      await assertSucceeds(getDoc(doc(staff('sup1'), 'config', 'reply_templates')));
      await assertSucceeds(getDoc(doc(as('driver1'), 'config', 'reply_templates')));
    });

    test('other config documents keep their old rule', async () => {
      await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'pricing'), { platformFeePercent: 5 }));
    });
  });

  describe('bulk tier change with one audit row per user', () => {
    const bulk = (db, actor, uids, tier = 'restricted') => {
      const b = writeBatch(db);
      for (const u of uids) {
        b.update(doc(db, 'users', u), { riskTier: tier, riskReason: 'bulk', riskUpdatedAt: serverTimestamp() });
        b.set(doc(collection(db, 'audit_events')), {
          type: 'user_action', actorId: actor, targetId: u, createdAt: serverTimestamp(),
          data: { action: 'bulk_hold', reason: 'bulk', from: 'normal', to: tier, bulk: true },
        });
      }
      return b.commit();
    };

    test('ops and super admins hold several users in one batch', async () => {
      await assertSucceeds(bulk(staff('ops1'), 'ops1', ['u1', 'u2', 'u3']));
      await assertSucceeds(bulk(asAdmin(), 'admin1', ['u1', 'u2', 'u3'], 'normal'));
    });

    test('refused: support, an ordinary user, a made-up tier, an audit row as someone else', async () => {
      await assertFails(bulk(staff('sup1'), 'sup1', ['u1']));
      await assertFails(bulk(as('u2'), 'u2', ['u1']));
      await assertFails(bulk(staff('ops1'), 'ops1', ['u1'], 'evil'));
      await assertFails(bulk(staff('ops1'), 'someone-else', ['u1']));
    });
  });
});

describe('demo data', () => {
  const demo = (over = {}) => ({ demo: true, name: 'Demo', ...over });
  const cols = ['users', 'vehicles', 'loads', 'bookings'];
  const staff = (uid) => env.authenticatedContext(uid).firestore();

  beforeEach(async () => {
    await seed(async (db) => {
      await rawSetDoc(doc(db, 'admins', 'sup1'), { role: 'support' });
      await rawSetDoc(doc(db, 'admins', 'ops1'), { role: 'ops' });
      for (const c of cols) {
        await rawSetDoc(doc(db, c, 'demo_old'), demo());
        await rawSetDoc(doc(db, c, 'real_old'), { name: 'Real' });
      }
    });
  });

  test('a super admin creates demo documents in all four collections', async () => {
    for (const c of cols) await assertSucceeds(rawSetDoc(doc(asAdmin(), c, 'demo_new_1'), demo()));
  });

  test('refused: other staff roles, ordinary users, signed-out', async () => {
    for (const c of cols) {
      await assertFails(rawSetDoc(doc(staff('sup1'), c, 'demo_x'), demo()));
      await assertFails(rawSetDoc(doc(staff('ops1'), c, 'demo_x'), demo()));
      await assertFails(rawSetDoc(doc(as('driver1'), c, 'demo_x'), demo()));
      await assertFails(rawSetDoc(doc(anon(), c, 'demo_x'), demo()));
    }
  });

  test('refused: id without the demo_ prefix, demo false or missing', async () => {
    for (const c of cols) {
      await assertFails(rawSetDoc(doc(asAdmin(), c, 'plain_id'), demo()));
      await assertFails(rawSetDoc(doc(asAdmin(), c, 'demo_x'), demo({ demo: false })));
      await assertFails(rawSetDoc(doc(asAdmin(), c, 'demo_x'), { name: 'No flag' }));
      await assertFails(rawSetDoc(doc(asAdmin(), c, 'demo_x'), demo({ demo: 'true' })));
    }
  });

  test('a real document flagged demo is not deletable (id prefix is checked too)', async () => {
    await seed((db) => rawSetDoc(doc(db, 'users', 'driver9'), { name: 'X', demo: true }));
    await assertFails(deleteDoc(doc(asAdmin(), 'users', 'driver9')));
  });

  test('a super admin deletes demo documents only', async () => {
    for (const c of cols) {
      await assertSucceeds(deleteDoc(doc(asAdmin(), c, 'demo_old')));
      await assertFails(deleteDoc(doc(asAdmin(), c, 'real_old')));
      await assertFails(deleteDoc(doc(staff('sup1'), c, 'demo_old')));
      await assertFails(deleteDoc(doc(as('driver1'), c, 'demo_old')));
    }
  });
});

describe('abuse guards (Task 56)', () => {
  const OFFER = {
    loadId: 'L1', driverId: 'driver1', customerId: 'customer1', vehicleId: 'v1', vehicleNumber: VEHICLE.number,
    vehicleType: '20ft', driverName: 'Ramesh', pricePaise: 2400000, originalPaise: 2400000, status: 'pending',
  };
  const offerAt = (db, paise) => setDoc(doc(db, 'offers', 'L1_driver1'), { ...OFFER, pricePaise: paise, originalPaise: paise });
  const withEstimate = (total) => seed((db) => updateDoc(doc(db, 'loads', 'L1'), { estimate: { total } }));

  test('offer price must be 30%..300% of the estimate (inclusive), in whole paise', async () => {
    await seedOpenLoad();
    await withEstimate(1000000);
    await assertFails(offerAt(as('driver1'), 299999));
    await assertSucceeds(offerAt(as('driver1'), 300000));
    await seed((db) => deleteDoc(doc(db, 'offers', 'L1_driver1')));
    await assertSucceeds(offerAt(as('driver1'), 3000000));
    await seed((db) => deleteDoc(doc(db, 'offers', 'L1_driver1')));
    await assertFails(offerAt(as('driver1'), 3000001));
    await assertFails(offerAt(as('driver1'), 99999999));
  });

  test('without an estimate (or a zero one) there are no limits except the hard cap', async () => {
    await seedOpenLoad();
    await assertSucceeds(offerAt(as('driver1'), 100));
    await seed((db) => deleteDoc(doc(db, 'offers', 'L1_driver1')));
    await withEstimate(0);
    await assertSucceeds(offerAt(as('driver1'), 99999999));
    await seed((db) => deleteDoc(doc(db, 'offers', 'L1_driver1')));
    await assertFails(offerAt(as('driver1'), 100000001));
  });

  test('chat: a message of only spaces is refused', async () => {
    await seedBooking();
    const msgs = collection(as('customer1'), 'bookings', 'L1', 'messages');
    const msg = (text) => ({ senderId: 'customer1', text, flagged: false, createdAt: serverTimestamp() });
    await assertFails(addDoc(msgs, msg('   ')));
    await assertFails(addDoc(msgs, msg('\n\t ')));
    await assertSucceeds(addDoc(msgs, msg(' hi ')));
    await assertSucceeds(addDoc(msgs, msg('x'.repeat(500))));
    await assertFails(addDoc(msgs, msg('x'.repeat(501))));
  });
});

describe('trip share link (Task 64)', () => {
  const TOKEN = 'abcdefghijkmnpqrstuvwxy2';
  const hours = (h) => Timestamp.fromMillis(Date.now() + h * 3600 * 1000);
  const share = (over = {}) => ({
    bookingId: 'L1', ownerId: 'customer1', pickup: 'Delhi', drop: 'Mumbai', status: 'accepted', vehicleNumber: 'MH12AB1234', driverName: 'Ramesh',
    statusAt: serverTimestamp(), expiresAt: hours(24), createdAt: serverTimestamp(), ...over,
  });
  const ref = (db, t = TOKEN) => doc(db, 'trip_shares', t);
  const seedShare = (over = {}) => seed((db) => rawSetDoc(ref(db), { ...share(), statusAt: Timestamp.now(), createdAt: Timestamp.now(), ...over }));

  beforeEach(async () => {
    await seedBooking();
  });

  test('a booking party creates a share with the exact fields; outsiders and others cannot', async () => {
    await assertSucceeds(rawSetDoc(ref(as('customer1')), share()));
    await assertSucceeds(rawSetDoc(ref(as('driver1'), 'bcdefghijkmnpqrstuvwxy23'), share({ ownerId: 'driver1' })));
    await assertFails(rawSetDoc(ref(as('driver2'), 'cdefghijkmnpqrstuvwxy234'), share({ ownerId: 'driver2' })), 'not a party');
    await assertFails(rawSetDoc(ref(anon(), 'defghijkmnpqrstuvwxy2345'), share()), 'signed out');
    await assertFails(rawSetDoc(ref(as('customer1'), 'efghijkmnpqrstuvwxy23456'), share({ ownerId: 'driver1' })), 'owner must be me');
  });

  test('refused: bad token, extra field, long text, wrong times', async () => {
    const c = as('customer1');
    await assertFails(rawSetDoc(ref(c, 'short'), share()));
    await assertFails(rawSetDoc(ref(c, 'ABCDEFGHIJKMNPQRSTUVWXY2'), share()), 'upper case');
    await assertFails(rawSetDoc(ref(c, 'fghijkmnpqrstuvwxy234567'), share({ phone: '+919800000000' })));
    await assertFails(rawSetDoc(ref(c, 'ghijkmnpqrstuvwxy2345678'), share({ pickup: 'x'.repeat(201) })));
    await assertFails(rawSetDoc(ref(c, 'hijkmnpqrstuvwxy23456789'), share({ driverName: 'x'.repeat(41) })));
    await assertFails(rawSetDoc(ref(c, 'ijkmnpqrstuvwxy2345678ab'), share({ expiresAt: hours(72) })), 'too long');
    await assertFails(rawSetDoc(ref(c, 'jkmnpqrstuvwxy2345678abc'), share({ expiresAt: hours(-1) })), 'already ended');
    await assertFails(rawSetDoc(ref(c, 'kmnpqrstuvwxy2345678abcd'), share({ createdAt: Timestamp.fromMillis(1000) })));
    await assertFails(rawSetDoc(ref(c, 'mnpqrstuvwxy2345678abcde'), share({ bookingId: 'NOPE' })), 'booking must exist');
  });

  test('anyone with the token reads one document while it lasts; nobody can list', async () => {
    await seedShare();
    await assertSucceeds(getDoc(ref(anon())));
    await assertSucceeds(getDoc(ref(as('driver2'))));
    await assertFails(getDocs(collection(anon(), 'trip_shares')));
    await assertFails(getDocs(collection(as('driver2'), 'trip_shares')));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'trip_shares'), where('bookingId', '==', 'L1'))));
    await assertFails(getDocs(query(collection(as('driver2'), 'trip_shares'), where('bookingId', '==', 'L1'))));
  });

  test('an ended link cannot be read or updated', async () => {
    await seedShare({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await assertFails(getDoc(ref(anon())));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'loading', statusAt: serverTimestamp() }));
  });

  test('either party moves the status; nothing else may change', async () => {
    await seedShare();
    await assertSucceeds(updateDoc(ref(as('driver1')), { status: 'loading', statusAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'cancelled', statusAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'loading', statusAt: serverTimestamp(), pickup: 'Elsewhere' }));
    await assertFails(updateDoc(ref(as('driver1')), { expiresAt: hours(40) }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'x'.repeat(31), statusAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(as('driver2')), { status: 'loading', statusAt: serverTimestamp() }));
    await assertFails(updateDoc(ref(anon()), { status: 'loading', statusAt: serverTimestamp() }));
  });

  test('only the owner ends a link', async () => {
    await seedShare();
    await assertFails(deleteDoc(ref(as('driver1'))));
    await assertFails(deleteDoc(ref(anon())));
    await assertSucceeds(deleteDoc(ref(as('customer1'))));
  });
});

// ---------------------------------------------------------------------------
// Task 69: admin-only collections stay closed to customer, driver, transporter.
// ---------------------------------------------------------------------------
describe('admin lock (Task 69)', () => {
  const ROLES = ['customer1', 'driver1', 'transporter1'];
  const auditBody = (uid, type) => ({ type, actorId: uid, data: {}, createdAt: serverTimestamp() });

  for (const uid of ROLES) {
    test(`${uid}: cannot read or write the admins collection`, async () => {
      const db = as(uid);
      await assertFails(getDoc(doc(db, 'admins', 'admin1')));
      await assertFails(getDocs(collection(db, 'admins')));
      await assertFails(setDoc(doc(db, 'admins', uid), { role: 'super' }));
      await assertFails(updateDoc(doc(db, 'admins', 'admin1'), { role: 'support' }));
      await assertFails(deleteDoc(doc(db, 'admins', 'admin1')));
    });

    test(`${uid}: no audit_events read, no admin-type audit writes`, async () => {
      const db = as(uid);
      await seed((a) => setDoc(doc(a, 'audit_events', 'e1'), { type: 'config_change', actorId: 'admin1', data: {}, createdAt: Timestamp.now() }));
      await assertFails(getDoc(doc(db, 'audit_events', 'e1')));
      await assertFails(getDocs(collection(db, 'audit_events')));
      for (const type of ['verification', 'risk_change', 'reassign', 'config_change', 'user_action', 'contact_view', 'chat_view']) {
        await assertFails(addDoc(collection(db, 'audit_events'), auditBody(uid, type)));
      }
      await assertFails(deleteDoc(doc(db, 'audit_events', 'e1')));
    });

    test(`${uid}: cannot write config (features, pricing) or admin-only docs`, async () => {
      const db = as(uid);
      await assertFails(setDoc(doc(db, 'config', 'features'), { pilotMode: false, flags: { bilty: true } }));
      await assertFails(setDoc(doc(db, 'config', 'pricing'), { platformFeePercent: 0 }));
      await assertFails(updateDoc(doc(db, 'config', 'features'), { pilotMode: true }));
      await assertFails(deleteDoc(doc(db, 'config', 'features')));
    });

    test(`${uid}: cannot touch fraud cases, error logs or other people's violations`, async () => {
      const db = as(uid);
      await seed(async (a) => {
        await setDoc(doc(a, 'fraud_cases', 'c1'), { userId: 'x', summary: 'abc', status: 'open', reportIds: [], createdBy: 'admin1', createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
        await setDoc(doc(a, 'app_errors', 'e1'), { message: 'm', screen: 's', kind: 'flutter', appVersion: '1', createdAt: Timestamp.now() });
        await setDoc(doc(a, 'violations', 'someone_1'), { userId: 'someone', bookingId: 'b', kind: 'phone', excerpt: 'x', createdAt: Timestamp.now() });
      });
      await assertFails(getDoc(doc(db, 'fraud_cases', 'c1')));
      await assertFails(getDocs(collection(db, 'fraud_cases')));
      await assertFails(setDoc(doc(db, 'fraud_cases', 'c2'), { userId: 'x', summary: 'abc', status: 'open', reportIds: [], createdBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
      await assertFails(getDoc(doc(db, 'app_errors', 'e1')));
      await assertFails(getDocs(collection(db, 'app_errors')));
      await assertFails(getDoc(doc(db, 'violations', 'someone_1')));
      await assertFails(getDocs(collection(db, 'violations')));
      await assertFails(deleteDoc(doc(db, 'violations', 'someone_1')));
    });

    test(`${uid}: cannot give themselves a risk tier or lift a restriction`, async () => {
      const db = as(uid);
      await seed((a) => setDoc(doc(a, 'users', uid), { name: 'N', role: 'customer', riskTier: 'review' }));
      await assertFails(updateDoc(doc(db, 'users', uid), { riskTier: 'normal' }));
      await assertFails(updateDoc(doc(db, 'users', uid), { riskTier: 'banned' }));
      await assertFails(updateDoc(doc(db, 'users', uid), { riskReason: 'none' }));
    });
  }

  test('the real admin still reads and writes what the others cannot', async () => {
    await assertSucceeds(getDoc(doc(asAdmin(), 'admins', 'admin1')));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'features'), { pilotMode: false, flags: {}, updatedAt: serverTimestamp() }));
    await assertSucceeds(getDocs(collection(asAdmin(), 'audit_events')));
    await assertSucceeds(getDocs(collection(asAdmin(), 'fraud_cases')));
  });
});

// ---------------------------------------------------------------------------
// Task 70: bilty (LR)
// ---------------------------------------------------------------------------
describe('bilty (Task 70)', () => {
  const YEAR = 2026;
  const lrIdOf = (issuer, seq, v = 1) => `${issuer}_${YEAR}_${seq}_v${v}`;
  const pub = (issuer, role, seq, over = {}) => ({
    bookingId: 'B1', issuerId: issuer, issuerRole: role, customerId: 'customer1', ...((over.bookingId ?? 'B1') !== 'B2' ? { fleetOwnerId: 'tr1' } : {}),
    lrNo: `${role === 'transporter' ? 'TR' : 'CS'}-${YEAR}-00000${seq}`, seq, year: YEAR, version: 1, status: 'issued', date: Timestamp.now(),
    pickup: 'Delhi', drop: 'Jaipur', route: 'Delhi → Jaipur', goods: 'FMCG', packages: 40, weightTons: 7.5, vehicleNumber: 'MH12AB1234',
    driverName: 'Suresh', consignorName: 'A Traders', consigneeName: 'B Stores', issuerName: 'Fast Cargo', complianceMode: 'hide',
    createdAt: serverTimestamp(), ...over,
  });
  const DETAILS = { freightPaise: 2500000, advancePaise: 500000, balancePaise: 2000000, marginPaise: 100000, gstPaise: 0, consignorPhone: '+919800000001', createdAt: serverTimestamp() };
  const COMPLIANCE = { goodsValuePaise: 90000000, invoiceNo: 'INV-1', ewayBillNo: '123456789012', createdAt: serverTimestamp() };

  async function issue(db, issuer, role, seq, over = {}, { compliance = true, series = true } = {}) {
    const id = lrIdOf(issuer, seq, over.version ?? 1);
    const b = writeBatch(db);
    b.set(doc(db, 'lrs', id), pub(issuer, role, seq, over));
    b.set(doc(db, 'lrs', id, 'private', 'details'), DETAILS);
    if (compliance) b.set(doc(db, 'lrs', id, 'private', 'compliance'), COMPLIANCE);
    if (series) b.set(doc(db, 'lr_series', `${issuer}_${YEAR}`), { next: seq + 1, updatedAt: serverTimestamp() });
    await b.commit();
    return id;
  }

  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', 'tr1'), { role: 'fleet', name: 'Fast Cargo' });
      await setDoc(doc(db, 'users', 'customer1'), { role: 'customer', name: 'C' });
      await setDoc(doc(db, 'users', 'drvA'), { role: 'driver', name: 'Suresh' });
      await setDoc(doc(db, 'bookings', 'B1'), { ...bookingFor('L1', { driverId: 'tr1', fleetOwnerId: 'tr1', assignedDriverId: 'drvA' }), timeline: {} });
      await setDoc(doc(db, 'bookings', 'B2'), { ...bookingFor('L2', { driverId: 'driver1' }), timeline: {} });
      await setDoc(doc(db, 'bookings', 'B3'), { ...bookingFor('L3', { driverId: 'tr1', fleetOwnerId: 'tr1', customerId: 'customer2' }), timeline: {} });
    });
  });

  test('transporter and customer issue; driver, admin and strangers cannot', async () => {
    await assertSucceeds(issue(as('tr1'), 'tr1', 'transporter', 1));
    await assertSucceeds(issue(as('customer1'), 'customer1', 'customer', 1));
    await assertFails(issue(as('drvA'), 'drvA', 'transporter', 1));
    await assertFails(issue(as('driver1'), 'driver1', 'customer', 1, { bookingId: 'B2' }));
    await assertFails(issue(asAdmin(), 'admin1', 'customer', 1));
    await assertFails(issue(as('customer2'), 'customer2', 'customer', 1)); // not their booking B1
    await assertFails(issue(as('customer1'), 'customer1', 'customer', 1, { bookingId: 'B3', customerId: 'customer1' })); // B3 belongs to customer2
    await assertFails(issue(as('tr2'), 'tr2', 'transporter', 1));
  });

  test('a customer cannot issue as transporter, and a transporter only on their own booking', async () => {
    await assertFails(issue(as('customer1'), 'customer1', 'transporter', 1));
    await assertSucceeds(issue(as('tr1'), 'tr1', 'transporter', 1, { bookingId: 'B3', customerId: 'customer2' }));
    await assertFails(issue(as('tr1'), 'tr1', 'transporter', 2, { bookingId: 'B2' })); // B2 has no fleetOwnerId
  });

  test('number series: seq must follow the counter; a repeat is refused', async () => {
    await assertSucceeds(issue(as('tr1'), 'tr1', 'transporter', 1));
    await assertFails(issue(as('tr1'), 'tr1', 'transporter', 1)); // same id and seq again
    await assertFails(issue(as('tr1'), 'tr1', 'transporter', 3)); // skipped 2
    await assertSucceeds(issue(as('tr1'), 'tr1', 'transporter', 2));
    await assertFails(issue(as('tr1'), 'tr1', 'transporter', 3, {}, { series: false }));
    await assertFails(setDoc(doc(as('tr2'), 'lr_series', 'tr1_2026'), { next: 9, updatedAt: serverTimestamp() }));
  });

  test('the id must match issuer, year, seq and version', async () => {
    const db = as('tr1');
    const b = writeBatch(db);
    b.set(doc(db, 'lrs', 'tr1_2026_1_v2'), pub('tr1', 'transporter', 1));
    b.set(doc(db, 'lrs', 'tr1_2026_1_v2', 'private', 'details'), DETAILS);
    b.set(doc(db, 'lr_series', 'tr1_2026'), { next: 2, updatedAt: serverTimestamp() });
    await assertFails(b.commit());
  });

  describe('who reads what', () => {
    let id;
    beforeEach(async () => {
      id = await issue(as('tr1'), 'tr1', 'transporter', 1);
    });
    const priv = (uid, name) => getDoc(doc(as(uid), 'lrs', id, 'private', name));

    test('private details and compliance: issuer, customer, admin; never the driver or a stranger', async () => {
      for (const name of ['details', 'compliance']) {
        await assertSucceeds(priv('tr1', name));
        await assertSucceeds(priv('customer1', name));
        await assertSucceeds(priv('admin1', name));
        await assertFails(priv('drvA', name));
        await assertFails(priv('driver1', name));
        await assertFails(priv('customer2', name));
        await assertFails(priv('tr2', name));
      }
    });

    test('public part: parties, the assigned driver and admin; not a stranger or another driver', async () => {
      for (const uid of ['tr1', 'customer1', 'drvA', 'admin1']) await assertSucceeds(getDoc(doc(as(uid), 'lrs', id)));
      for (const uid of ['customer2', 'tr2', 'driver1', 'drvB']) await assertFails(getDoc(doc(as(uid), 'lrs', id)));
    });

    test('lists by booking work for the parties and the driver, not for others', async () => {
      const q = (uid) => getDocs(query(collection(as(uid), 'lrs'), where('bookingId', '==', 'B1')));
      for (const uid of ['tr1', 'customer1', 'drvA']) await assertSucceeds(q(uid));
      await assertFails(q('customer2'));
      await assertFails(q('drvB'));
    });

    test('an independent driver reads the customer LR of their own booking (public only)', async () => {
      const cid = await issue(as('customer1'), 'customer1', 'customer', 1, { bookingId: 'B2' });
      await assertSucceeds(getDoc(doc(as('driver1'), 'lrs', cid)));
      await assertFails(getDoc(doc(as('driver1'), 'lrs', cid, 'private', 'details')));
      await assertFails(getDoc(doc(as('driver1'), 'lrs', cid, 'private', 'compliance')));
      await assertSucceeds(getDoc(doc(as('customer1'), 'lrs', cid, 'private', 'details')));
    });
  });

  describe('lock after issue', () => {
    let id;
    beforeEach(async () => {
      id = await issue(as('tr1'), 'tr1', 'transporter', 1);
    });

    test('content never changes; private parts cannot be edited or deleted', async () => {
      const db = as('tr1');
      await assertFails(updateDoc(doc(db, 'lrs', id), { goods: 'Steel', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db, 'lrs', id, 'private', 'details'), { freightPaise: 1 }));
      await assertFails(deleteDoc(doc(db, 'lrs', id)));
      await assertFails(deleteDoc(doc(db, 'lrs', id, 'private', 'details')));
    });

    test('edit = a new version; the old one becomes superseded and stays view-only', async () => {
      const db = as('tr1');
      const b = writeBatch(db);
      b.update(doc(db, 'lrs', id), { status: 'superseded', supersededBy: 2, updatedAt: serverTimestamp() });
      b.set(doc(db, 'lrs', lrIdOf('tr1', 1, 2)), pub('tr1', 'transporter', 1, { version: 2 }));
      b.set(doc(db, 'lrs', lrIdOf('tr1', 1, 2), 'private', 'details'), DETAILS);
      await assertSucceeds(b.commit());
      await assertFails(updateDoc(doc(db, 'lrs', id), { status: 'cancelled', cancelReason: 'late', updatedAt: serverTimestamp() }));
    });

    test('a new version without superseding the old one is refused, and nobody else versions it', async () => {
      const tdb = as('tr1');
      const b = writeBatch(tdb);
      b.set(doc(tdb, 'lrs', lrIdOf('tr1', 1, 2)), pub('tr1', 'transporter', 1, { version: 2 }));
      b.set(doc(tdb, 'lrs', lrIdOf('tr1', 1, 2), 'private', 'details'), DETAILS);
      await assertFails(b.commit());
      const cdb = as('customer1');
      const c = writeBatch(cdb);
      c.update(doc(cdb, 'lrs', id), { status: 'superseded', supersededBy: 2, updatedAt: serverTimestamp() });
      await assertFails(c.commit());
    });

    test('cancel needs a reason and the issuer; the customer cannot cancel the transporter LR', async () => {
      await assertFails(updateDoc(doc(as('tr1'), 'lrs', id), { status: 'cancelled', cancelReason: '', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('customer1'), 'lrs', id), { status: 'cancelled', cancelReason: 'no thanks', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('drvA'), 'lrs', id), { status: 'cancelled', cancelReason: 'no thanks', updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(doc(as('tr1'), 'lrs', id), { status: 'cancelled', cancelReason: 'wrong vehicle', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('tr1'), 'lrs', id), { status: 'issued', updatedAt: serverTimestamp() }));
    });

    test('the issuer changes the compliance mode, nobody else', async () => {
      await assertSucceeds(updateDoc(doc(as('tr1'), 'lrs', id), { complianceMode: 'inspection_on_request', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('tr1'), 'lrs', id), { complianceMode: 'everyone', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('customer1'), 'lrs', id), { complianceMode: 'show', updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(as('drvA'), 'lrs', id), { complianceMode: 'show', updatedAt: serverTimestamp() }));
    });
  });

  describe('share links', () => {
    let id;
    const TOKEN = '0123456789abcdef0123456789abcdef';
    const share = (over = {}) => ({
      lrId: id, bookingId: 'B1', ownerId: 'tr1', copyType: 'driver', fields: { lrNo: 'TR-2026-000001', route: 'Delhi → Jaipur', goods: 'FMCG' },
      status: 'issued', statusAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 86400000), createdAt: serverTimestamp(), revoked: false, views: 0, ...over,
    });
    beforeEach(async () => {
      id = await issue(as('tr1'), 'tr1', 'transporter', 1);
    });

    test('only the issuer creates; token must be 32 hex letters', async () => {
      await assertSucceeds(setDoc(doc(as('tr1'), 'lr_shares', TOKEN), share()));
      await assertFails(setDoc(doc(as('customer1'), 'lr_shares', 'fedcba9876543210fedcba9876543210'), share({ ownerId: 'customer1' })));
      await assertFails(setDoc(doc(as('drvA'), 'lr_shares', 'fedcba9876543210fedcba9876543210'), share({ ownerId: 'drvA' })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', 'short'), share()));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', 'ABCDEF9876543210fedcba9876543210'), share()));
    });

    test('driver copy cannot carry rate, margin, phone or compliance; consignee never carries margin or phone', async () => {
      const t = (n) => `${n}`.padStart(32, 'a');
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(1)), share({ fields: { lrNo: 'x', freightPaise: 1 } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(2)), share({ fields: { lrNo: 'x', marginPaise: 1 } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(3)), share({ fields: { lrNo: 'x', consignorPhone: '+91' } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(4)), share({ fields: { lrNo: 'x', ewayBillNo: '123456789012' } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(5)), share({ copyType: 'consignee', fields: { lrNo: 'x', marginPaise: 1 } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(6)), share({ copyType: 'consignee', fields: { lrNo: 'x', consigneePhone: '+91' } })));
      await assertSucceeds(setDoc(doc(as('tr1'), 'lr_shares', t(7)), share({ copyType: 'consignee', fields: { lrNo: 'x', freightPaise: 100 } })));
      await assertSucceeds(setDoc(doc(as('tr1'), 'lr_shares', t(8)), share({ copyType: 'full', fields: { lrNo: 'x', marginPaise: 100 } })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', t(9)), share({ copyType: 'verify', fields: { lrNo: 'x', freightPaise: 100 } })));
      await assertSucceeds(setDoc(doc(as('tr1'), 'lr_shares', t(10)), share({ copyType: 'verify', fields: { lrNo: 'x', route: 'a', status: 'issued', issuerName: 'F' } })));
    });

    test('a share of someone else\'s LR, or one that lasts too long, is refused', async () => {
      await assertFails(setDoc(doc(as('tr2'), 'lr_shares', TOKEN), share({ ownerId: 'tr2' })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', TOKEN), share({ expiresAt: Timestamp.fromMillis(Date.now() + 500 * 86400000) })));
      await assertFails(setDoc(doc(as('tr1'), 'lr_shares', TOKEN), share({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) })));
    });

    test('get by token works for anyone while valid; list is closed except for the owner\'s own', async () => {
      await setDoc(doc(as('tr1'), 'lr_shares', TOKEN), share());
      await assertSucceeds(getDoc(doc(anon(), 'lr_shares', TOKEN)));
      await assertFails(getDocs(collection(anon(), 'lr_shares')));
      await assertFails(getDocs(collection(as('customer1'), 'lr_shares')));
      await assertFails(getDocs(query(collection(as('customer1'), 'lr_shares'), where('ownerId', '==', 'tr1'))));
      await assertSucceeds(getDocs(query(collection(as('tr1'), 'lr_shares'), where('ownerId', '==', 'tr1'))));
    });

    test('expired and revoked tokens fail', async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'lr_shares', 'e'.repeat(32)), share({ expiresAt: Timestamp.fromMillis(Date.now() - 1000), statusAt: Timestamp.now(), createdAt: Timestamp.now() }));
        await setDoc(doc(db, 'lr_shares', 'f'.repeat(32)), share({ revoked: true, statusAt: Timestamp.now(), createdAt: Timestamp.now() }));
      });
      await assertFails(getDoc(doc(anon(), 'lr_shares', 'e'.repeat(32))));
      await assertFails(getDoc(doc(anon(), 'lr_shares', 'f'.repeat(32))));
      await assertFails(updateDoc(doc(anon(), 'lr_shares', 'e'.repeat(32)), { views: increment(1) }));
      await assertFails(updateDoc(doc(anon(), 'lr_shares', 'f'.repeat(32)), { views: increment(1) }));
    });

    test('revoke by the owner; view count goes up by one for anyone with the token', async () => {
      await setDoc(doc(as('tr1'), 'lr_shares', TOKEN), share());
      await assertSucceeds(updateDoc(doc(anon(), 'lr_shares', TOKEN), { views: increment(1) }));
      await assertFails(updateDoc(doc(anon(), 'lr_shares', TOKEN), { views: increment(5) }));
      await assertFails(updateDoc(doc(anon(), 'lr_shares', TOKEN), { revoked: true, statusAt: serverTimestamp(), status: 'x' }));
      await assertFails(updateDoc(doc(as('customer1'), 'lr_shares', TOKEN), { revoked: true, statusAt: serverTimestamp(), status: 'issued' }));
      await assertSucceeds(updateDoc(doc(as('tr1'), 'lr_shares', TOKEN), { revoked: true, statusAt: serverTimestamp(), status: 'issued' }));
      await assertFails(updateDoc(doc(as('tr1'), 'lr_shares', TOKEN), { revoked: false, statusAt: serverTimestamp(), status: 'issued' }));
      await assertFails(getDoc(doc(anon(), 'lr_shares', TOKEN)));
    });
  });

  test('audit events for bilty actions: parties only', async () => {
    const ev = (uid, type) => ({ type, actorId: uid, bookingId: 'B1', data: {}, createdAt: serverTimestamp() });
    for (const type of ['lr_issue', 'lr_version', 'lr_cancel', 'lr_share', 'lr_revoke', 'lr_mode']) {
      await assertSucceeds(addDoc(collection(as('tr1'), 'audit_events'), ev('tr1', type)));
      await assertSucceeds(addDoc(collection(as('customer1'), 'audit_events'), ev('customer1', type)));
      await assertFails(addDoc(collection(as('customer2'), 'audit_events'), ev('customer2', type)));
    }
  });
});

// ---------------------------------------------------------------------------
// Task 71: bilty inspection mode
// ---------------------------------------------------------------------------
describe('bilty inspection mode (Task 71)', () => {
  const YEAR = 2026;
  const ID = `tr1_${YEAR}_1_v1`;
  const hours = (h) => Timestamp.fromMillis(Date.now() + h * 3600000);
  const lr = (mode) => ({
    bookingId: 'B1', issuerId: 'tr1', issuerRole: 'transporter', customerId: 'customer1', fleetOwnerId: 'tr1', lrNo: 'TR-2026-000001', seq: 1, year: YEAR, version: 1,
    status: 'issued', date: Timestamp.now(), pickup: 'Delhi', drop: 'Jaipur', goods: 'FMCG', complianceMode: mode, createdAt: Timestamp.now(),
  });
  const grant = (over = {}) => ({ driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: hours(2) , verifyToken: '', createdAt: serverTimestamp(), ...over });
  const seedLr = async (mode = 'inspection_on_request') => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users', 'tr1'), { role: 'fleet', name: 'Fast Cargo' });
      await setDoc(doc(db, 'bookings', 'B1'), { ...bookingFor('L1', { driverId: 'tr1', fleetOwnerId: 'tr1', assignedDriverId: 'drvA' }), timeline: {} });
      await setDoc(doc(db, 'bookings', 'B2'), { ...bookingFor('L2', { driverId: 'driver1' }), timeline: {} });
      await setDoc(doc(db, 'lrs', ID), lr(mode));
      await setDoc(doc(db, 'lrs', ID, 'private', 'details'), { freightPaise: 100, advancePaise: 0, balancePaise: 100, marginPaise: 5, gstPaise: 0, createdAt: Timestamp.now() });
      await setDoc(doc(db, 'lrs', ID, 'private', 'compliance'), { goodsValuePaise: 9000, invoiceNo: 'I1', ewayBillNo: '123456789012', createdAt: Timestamp.now() });
    });
  };
  const comp = (uid) => getDoc(doc(as(uid), 'lrs', ID, 'private', 'compliance'));
  const details = (uid) => getDoc(doc(as(uid), 'lrs', ID, 'private', 'details'));

  test('the driver never reads the rate group, in any mode, with or without a grant', async () => {
    for (const mode of ['hide', 'show', 'inspection_on_request']) {
      await seedLr(mode);
      await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvA'), { driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: hours(1), verifyToken: '', createdAt: Timestamp.now() }));
      await assertFails(details('drvA'));
      await assertSucceeds(details('tr1'));
    }
  });

  test('compliance: hidden in hide and inspection_on_request mode, open in show mode', async () => {
    await seedLr('hide');
    await assertFails(comp('drvA'));
    await seedLr('inspection_on_request');
    await assertFails(comp('drvA'));
    await seedLr('show');
    await assertSucceeds(comp('drvA'));
    await assertSucceeds(comp('tr1'));
    await assertSucceeds(comp('customer1'));
    await assertFails(comp('customer2'));
    await assertFails(comp('drvB'));
  });

  test('compliance opens on a valid grant and closes when it expires', async () => {
    await seedLr('inspection_on_request');
    await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvA'), { driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: hours(1), verifyToken: '', createdAt: Timestamp.now() }));
    await assertSucceeds(comp('drvA'));
    await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvA'), { driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: Timestamp.fromMillis(Date.now() - 1000), verifyToken: '', createdAt: Timestamp.now() }));
    await assertFails(comp('drvA'));
  });

  test('another driver\'s grant does not work for me', async () => {
    await seedLr('inspection_on_request');
    await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvB'), { driverId: 'drvB', ownerId: 'tr1', kind: 'approved', expiresAt: hours(1), verifyToken: '', createdAt: Timestamp.now() }));
    await assertFails(comp('drvA'));
    await assertFails(comp('drvB')); // drvB is not the driver of this booking
    await assertFails(getDoc(doc(as('drvA'), 'lrs', ID, 'inspection_grants', 'drvB')));
  });

  describe('grants', () => {
    beforeEach(() => seedLr());
    const put = (uid, driver, data) => setDoc(doc(as(uid), 'lrs', ID, 'inspection_grants', driver), data);

    test('only the issuer creates, only for the trip driver, 2 hours at most when approved', async () => {
      await assertSucceeds(put('tr1', 'drvA', grant()));
      await assertFails(put('customer1', 'drvA', grant({ ownerId: 'customer1' })));
      await assertFails(put('drvA', 'drvA', grant({ ownerId: 'drvA' })));
      await assertFails(put('tr1', 'drvB', grant({ driverId: 'drvB' })));
      await assertFails(put('tr1', 'drvA', grant({ expiresAt: hours(3) })));
      await assertFails(put('tr1', 'drvA', grant({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) })));
      await assertFails(put('tr1', 'drvA', grant({ kind: 'forever' })));
    });

    test('a pre-approved grant may last up to 72 hours, not more', async () => {
      await assertSucceeds(put('tr1', 'drvA', grant({ kind: 'preapproved', expiresAt: hours(48) })));
      await assertFails(put('tr1', 'drvA', grant({ kind: 'preapproved', expiresAt: hours(80) })));
    });

    test('the driver reads their grant; another driver and a stranger do not', async () => {
      await put('tr1', 'drvA', grant());
      await assertSucceeds(getDoc(doc(as('drvA'), 'lrs', ID, 'inspection_grants', 'drvA')));
      await assertSucceeds(getDoc(doc(as('tr1'), 'lrs', ID, 'inspection_grants', 'drvA')));
      await assertFails(getDoc(doc(as('drvB'), 'lrs', ID, 'inspection_grants', 'drvA')));
      await assertFails(getDoc(doc(as('customer2'), 'lrs', ID, 'inspection_grants', 'drvA')));
    });

    test('the driver cannot make or extend their own grant; the issuer can end it', async () => {
      await assertFails(put('drvA', 'drvA', grant({ ownerId: 'tr1' })));
      await put('tr1', 'drvA', grant());
      await assertFails(put('drvA', 'drvA', grant({ expiresAt: hours(2) })));
      await assertFails(deleteDoc(doc(as('drvA'), 'lrs', ID, 'inspection_grants', 'drvA')));
      await assertSucceeds(deleteDoc(doc(as('tr1'), 'lrs', ID, 'inspection_grants', 'drvA')));
    });
  });

  describe('requests', () => {
    beforeEach(() => seedLr());
    const req = (over = {}) => ({ driverId: 'drvA', ownerId: 'tr1', bookingId: 'B1', driverName: 'Suresh', status: 'pending', requestedAt: serverTimestamp(), ...over });
    const reqRef = (uid, driver = 'drvA') => doc(as(uid), 'lrs', ID, 'inspection_requests', driver);

    test('the trip driver asks; others cannot ask for someone else or as a non-driver', async () => {
      await assertSucceeds(setDoc(reqRef('drvA'), req()));
      await assertFails(setDoc(reqRef('drvB', 'drvB'), req({ driverId: 'drvB' })));
      await assertFails(setDoc(reqRef('customer1', 'customer1'), req({ driverId: 'customer1' })));
      await assertFails(setDoc(reqRef('drvA', 'drvB'), req({ driverId: 'drvB' })));
      await assertFails(setDoc(reqRef('drvA'), req({ status: 'approved' })));
      await assertFails(setDoc(reqRef('drvA'), req({ ownerId: 'drvA' })));
    });

    test('the issuer approves or denies a pending request; the driver cannot', async () => {
      await setDoc(reqRef('drvA'), req());
      await assertFails(updateDoc(reqRef('drvA'), { status: 'approved', decidedAt: serverTimestamp() }));
      await assertFails(updateDoc(reqRef('customer1'), { status: 'approved', decidedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(reqRef('tr1'), { status: 'approved', decidedAt: serverTimestamp() }));
      await assertFails(updateDoc(reqRef('tr1'), { status: 'denied', decidedAt: serverTimestamp() }));
    });

    test('after a denial the driver may ask again', async () => {
      await setDoc(reqRef('drvA'), req());
      await updateDoc(reqRef('tr1'), { status: 'denied', decidedAt: serverTimestamp() });
      await assertSucceeds(updateDoc(reqRef('drvA'), { status: 'pending', requestedAt: serverTimestamp() }));
    });

    test('the driver marks an approved request expired only once the grant has run out', async () => {
      await setDoc(reqRef('drvA'), req());
      await updateDoc(reqRef('tr1'), { status: 'approved', decidedAt: serverTimestamp() });
      await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvA'), { driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: hours(1), verifyToken: '', createdAt: Timestamp.now() }));
      await assertFails(updateDoc(reqRef('drvA'), { status: 'expired', decidedAt: serverTimestamp() }));
      await seed((db) => setDoc(doc(db, 'lrs', ID, 'inspection_grants', 'drvA'), { driverId: 'drvA', ownerId: 'tr1', kind: 'approved', expiresAt: Timestamp.fromMillis(Date.now() - 1000), verifyToken: '', createdAt: Timestamp.now() }));
      await assertSucceeds(updateDoc(reqRef('drvA'), { status: 'expired', decidedAt: serverTimestamp() }));
    });

    test('requests are readable by the driver and the parties only; never deleted', async () => {
      await setDoc(reqRef('drvA'), req());
      await assertSucceeds(getDoc(reqRef('drvA')));
      await assertSucceeds(getDoc(reqRef('tr1', 'drvA')));
      await assertFails(getDoc(reqRef('drvB', 'drvA')));
      await assertFails(deleteDoc(reqRef('tr1')));
    });
  });

  test('audit and notices for inspection', async () => {
    await seedLr();
    const ev = (uid, type) => ({ type, actorId: uid, bookingId: 'B1', data: {}, createdAt: serverTimestamp() });
    for (const type of ['inspection_request', 'inspection_approve', 'inspection_deny', 'inspection_expire']) {
      await assertSucceeds(addDoc(collection(as('drvA'), 'audit_events'), ev('drvA', type)));
      await assertSucceeds(addDoc(collection(as('tr1'), 'audit_events'), ev('tr1', type)));
      await assertFails(addDoc(collection(as('drvB'), 'audit_events'), ev('drvB', type)));
    }
    const note = (type, to) => ({ userId: to, type, message: 'x', relatedId: 'B1', read: false, createdAt: serverTimestamp() });
    await assertSucceeds(setDoc(doc(as('drvA'), 'notifications', 'n1'), note('inspection_request', 'tr1')));
    await assertSucceeds(setDoc(doc(as('tr1'), 'notifications', 'n2'), note('inspection_approved', 'drvA')));
    await assertSucceeds(setDoc(doc(as('tr1'), 'notifications', 'n3'), note('inspection_denied', 'drvA')));
    await assertSucceeds(setDoc(doc(as('tr1'), 'notifications', 'n4'), note('lr_sent', 'drvA')));
  });
});

describe('pilot invite codes (M6-1)', () => {
  const FUTURE = () => Timestamp.fromMillis(Date.now() + 86400000);
  const CODE = (over = {}) => ({ role: 'any', route: 'Delhi-Jaipur', maxUses: 2, uses: 0, expiresAt: FUTURE(), active: true, createdBy: 'admin1', createdAt: serverTimestamp(), ...over });
  const seedCode = (over = {}) => seed((db) => rawSetDoc(doc(db, 'invite_codes', 'ABCD2345'), CODE({ createdAt: Timestamp.now(), ...over })));
  const redeem = (uid, code = 'ABCD2345', uses = 1) => {
    const db = as(uid);
    const b = rawWriteBatch(db);
    b.update(doc(db, 'invite_codes', code), { uses });
    b.set(doc(db, 'invite_redemptions', uid), { code, role: 'customer', createdAt: serverTimestamp() });
    return b.commit();
  };

  test('admin makes a code with a valid shape; users cannot', async () => {
    await assertSucceeds(rawSetDoc(doc(asAdmin(), 'invite_codes', 'ABCD2345'), CODE()));
    await assertFails(rawSetDoc(doc(as('u1'), 'invite_codes', 'ABCD2346'), CODE({ createdBy: 'u1' })));
    await assertFails(rawSetDoc(doc(asAdmin(), 'invite_codes', 'abcd2347'), CODE()));
    await assertFails(rawSetDoc(doc(asAdmin(), 'invite_codes', 'ABCD2348'), CODE({ maxUses: 0 })));
    await assertFails(rawSetDoc(doc(asAdmin(), 'invite_codes', 'ABCD2349'), CODE({ uses: 5 })));
    await assertFails(rawSetDoc(doc(asAdmin(), 'invite_codes', 'ABCD234A'), CODE({ extra: 1 })));
  });

  test('one code can be read by id, only an admin lists', async () => {
    await seedCode();
    await assertSucceeds(getDoc(doc(as('u1'), 'invite_codes', 'ABCD2345')));
    await assertFails(getDocs(collection(as('u1'), 'invite_codes')));
    await assertSucceeds(getDocs(collection(asAdmin(), 'invite_codes')));
    await assertFails(getDoc(doc(anon(), 'invite_codes', 'ABCD2345')));
  });

  test('a person redeems once with the counter raised by exactly one', async () => {
    await seedCode();
    await assertSucceeds(redeem('u1'));
    await assertFails(redeem('u1')); // the redemption cannot be written twice
    await assertFails(redeem('u2', 'ABCD2345', 5)); // not +1
    await assertSucceeds(redeem('u3', 'ABCD2345', 2));
    await assertFails(redeem('u4', 'ABCD2345', 3)); // above maxUses
  });

  test('an expired or switched-off code cannot be redeemed; the counter alone cannot move', async () => {
    await seedCode({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
    await assertFails(redeem('u1'));
    await seedCode({ active: false });
    await assertFails(redeem('u1'));
    await seedCode();
    await assertFails(updateDoc(doc(as('u1'), 'invite_codes', 'ABCD2345'), { uses: 1 }));
    await assertFails(updateDoc(doc(as('u1'), 'invite_codes', 'ABCD2345'), { maxUses: 999 }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'invite_codes', 'ABCD2345'), { active: false }));
    await assertFails(updateDoc(doc(asAdmin(), 'invite_codes', 'ABCD2345'), { maxUses: 999 }));
  });

  test('redemptions are private; the whitelist shows a person only their own number', async () => {
    await seedCode();
    await redeem('u1');
    await assertSucceeds(getDoc(doc(as('u1'), 'invite_redemptions', 'u1')));
    await assertFails(getDoc(doc(as('u2'), 'invite_redemptions', 'u1')));
    await seed((db) => rawSetDoc(doc(db, 'pilot_whitelist', '919999900001'), { createdBy: 'admin1', createdAt: Timestamp.now() }));
    const withPhone = (uid, phone) => env.authenticatedContext(uid, { phone_number: phone }).firestore();
    await assertSucceeds(getDoc(doc(withPhone('u9', '+919999900001'), 'pilot_whitelist', '919999900001')));
    await assertFails(getDoc(doc(withPhone('u8', '+919999900002'), 'pilot_whitelist', '919999900001')));
    await assertFails(getDocs(collection(as('u9'), 'pilot_whitelist')));
    await assertSucceeds(rawSetDoc(doc(asAdmin(), 'pilot_whitelist', '919999900003'), { createdBy: 'admin1', createdAt: serverTimestamp() }));
    await assertFails(rawSetDoc(doc(as('u9'), 'pilot_whitelist', '919999900004'), { createdBy: 'u9', createdAt: serverTimestamp() }));
  });
});

describe('waitlist (M6-2)', () => {
  const W = (uid, over = {}) => ({ uid, role: 'customer', from: 'Pune', to: 'Delhi', createdAt: serverTimestamp(), ...over });

  test('a person joins for themselves only, with a valid shape', async () => {
    await assertSucceeds(rawSetDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi'), W('u1')));
    await assertFails(rawSetDoc(doc(as('u1'), 'waitlist', 'u2_pune_delhi'), W('u2')));
    await assertFails(rawSetDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi'), W('u1', { role: 'admin' })));
    await assertFails(rawSetDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi'), W('u1', { extra: 1 })));
    await assertFails(rawSetDoc(doc(anon(), 'waitlist', 'u1_pune_delhi'), W('u1')));
  });

  test('owner and admins read; others cannot; only the owner deletes; no edits', async () => {
    await seed((db) => rawSetDoc(doc(db, 'waitlist', 'u1_pune_delhi'), W('u1', { createdAt: Timestamp.now() })));
    await assertSucceeds(getDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'waitlist', 'u1_pune_delhi')));
    await assertFails(getDoc(doc(as('u2'), 'waitlist', 'u1_pune_delhi')));
    await assertSucceeds(getDocs(query(collection(as('u1'), 'waitlist'), where('uid', '==', 'u1'))));
    await assertFails(getDocs(collection(as('u2'), 'waitlist')));
    await assertFails(updateDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi'), { to: 'Agra' }));
    await assertFails(deleteDoc(doc(as('u2'), 'waitlist', 'u1_pune_delhi')));
    await assertSucceeds(deleteDoc(doc(as('u1'), 'waitlist', 'u1_pune_delhi')));
  });
});

describe('dispatch suggestions (M6-4)', () => {
  const S = (over = {}) => ({ loadId: 'L1', driverId: 'd1', pickup: 'Delhi', drop: 'Jaipur', weight: 3, vehicleType: 'Mini', note: 'Call first', by: 'admin1', status: 'suggested', createdAt: serverTimestamp(), ...over });
  const seedS = () => seed((db) => rawSetDoc(doc(db, 'dispatch_suggestions', 'L1_d1'), S({ createdAt: Timestamp.now() })));

  test('an admin suggests with the right id and shape; users cannot', async () => {
    await assertSucceeds(rawSetDoc(doc(asAdmin(), 'dispatch_suggestions', 'L1_d1'), S()));
    await assertFails(rawSetDoc(doc(asAdmin(), 'dispatch_suggestions', 'L1_d2'), S()));
    await assertFails(rawSetDoc(doc(asAdmin(), 'dispatch_suggestions', 'L1_d1'), S({ status: 'accepted' })));
    await assertFails(rawSetDoc(doc(asAdmin(), 'dispatch_suggestions', 'L1_d1'), S({ note: 'x'.repeat(301) })));
    await assertFails(rawSetDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1'), S({ by: 'd1' })));
  });

  test('the driver reads their own and may only mark seen or declined', async () => {
    await seedS();
    await assertSucceeds(getDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1')));
    await assertFails(getDoc(doc(as('d2'), 'dispatch_suggestions', 'L1_d1')));
    await assertSucceeds(getDocs(query(collection(as('d1'), 'dispatch_suggestions'), where('driverId', '==', 'd1'))));
    await assertFails(updateDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1'), { status: 'accepted' }));
    await assertFails(updateDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1'), { note: 'mine' }));
    await assertFails(updateDoc(doc(as('d2'), 'dispatch_suggestions', 'L1_d1'), { status: 'seen' }));
    await assertSucceeds(updateDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1'), { status: 'declined' }));
    await assertSucceeds(deleteDoc(doc(as('d1'), 'dispatch_suggestions', 'L1_d1')));
  });
});

describe('trip surveys (M6-7)', () => {
  const SV = (uid, role, over = {}) => ({ bookingId: 'b1', uid, role, answer: 'yes', createdAt: serverTimestamp(), ...over });
  const seedBooking = (status = 'delivered') => seed((db) => rawSetDoc(doc(db, 'bookings', 'b1'), { customerId: 'c1', driverId: 'd1', fleetOwnerId: 'f1', status, loadId: 'l1' }));

  test('each side answers once after delivery, for themselves', async () => {
    await seedBooking();
    await assertSucceeds(rawSetDoc(doc(as('c1'), 'trip_surveys', 'b1_c1'), SV('c1', 'customer')));
    await assertSucceeds(rawSetDoc(doc(as('d1'), 'trip_surveys', 'b1_d1'), SV('d1', 'driver')));
    await assertSucceeds(rawSetDoc(doc(as('f1'), 'trip_surveys', 'b1_f1'), SV('f1', 'driver')));
    await assertFails(rawSetDoc(doc(as('x1'), 'trip_surveys', 'b1_x1'), SV('x1', 'customer')));
    await assertFails(rawSetDoc(doc(as('c1'), 'trip_surveys', 'b1_d1'), SV('c1', 'customer')));
    await assertFails(rawSetDoc(doc(as('c1'), 'trip_surveys', 'b1_c1'), SV('c1', 'driver')));
    await assertFails(rawSetDoc(doc(as('d1'), 'trip_surveys', 'b1_d1'), SV('d1', 'driver', { answer: 'definitely' })));
  });

  test('not before delivery; no edits; owner and admin read, others not', async () => {
    await seedBooking('in_transit');
    await assertFails(rawSetDoc(doc(as('c1'), 'trip_surveys', 'b1_c1'), SV('c1', 'customer')));
    await seedBooking();
    await assertSucceeds(rawSetDoc(doc(as('c1'), 'trip_surveys', 'b1_c1'), SV('c1', 'customer')));
    await assertFails(updateDoc(doc(as('c1'), 'trip_surveys', 'b1_c1'), { answer: 'no' }));
    await assertSucceeds(getDoc(doc(as('c1'), 'trip_surveys', 'b1_c1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'trip_surveys', 'b1_c1')));
    await assertFails(getDoc(doc(as('d1'), 'trip_surveys', 'b1_c1')));
    await assertSucceeds(deleteDoc(doc(as('c1'), 'trip_surveys', 'b1_c1')));
  });
});
