'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { deleteAccount } = require('../../src/deletion');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);

function fakes() {
  const calls = { deleted: [], prefixes: [] };
  return {
    calls,
    auth: {
      deleteUser: async (uid) => {
        calls.deleted.push(uid);
      },
    },
    storage: {
      deleteFiles: async ({ prefix }) => {
        calls.prefixes.push(prefix);
      },
    },
  };
}

async function seedPerson(db, uid) {
  await db.collection('users').doc(uid).set({ name: 'Asha', phone: '9876543210' });
  await db.collection('users').doc(uid).collection('credits').doc('c1').set({ amountPaise: 100 });
  await db.collection('users').doc(uid).collection('devices').doc('dev1').set({ model: 'X' });
  await db.collection('identity_index').doc('hash1').set({ uid, role: 'driver' });
  await db.collection('identity_index').doc('hash2').set({ uid: 'someoneElse', role: 'driver' });
  await db.collection('referral_codes').doc('ABC234').set({ uid });
  await db.collection('notifications').doc('n1').set({ userId: uid, type: 'x' });
  await db.collection('notifications').doc('n2').set({ userId: 'other', type: 'x' });
  await db.collection('rate_limits').doc(`${uid}_offer`).set({ count: 3 });
  await db.collection('rate_limits').doc(`${uid}2_offer`).set({ count: 3 });
  await db.collection('credit_balances').doc(uid).set({ balancePaise: 5 });
  await db.collection('public_trust').doc(uid).set({ trips: 4 });
  await db.collection('trip_counts').doc(uid).set({ total: 4 });
  await db.collection('trip_counts').doc(uid).collection('seen').doc('B1').set({ month: '2026-10' });
  await db.collection('bookings').doc('B1').set({ driverId: uid, customerId: 'cust', driverName: 'Asha', driverPhone: '9876543210', vehicleNumber: 'MH12AB1', pickup: 'Pune' });
  await db.collection('bookings').doc('B2').set({ driverId: 'dX', customerId: uid, customerName: 'Asha', customerPhone: '9876543210', driverName: 'Ravi' });
  await db.collection('ledger').doc('B1_trip_earning').set({ driverId: uid, amountPaise: 1000 });
  await db.collection('payouts').doc('p1').set({ driverId: uid, amountPaise: 500, status: 'paid' });
  await db.collection('deletion_requests').doc(uid).set({ userId: uid, status: 'approved', reason: '', createdAt: Timestamp.fromMillis(NOW) });
}

test.beforeEach(clearDb);

test('nothing happens unless the request is approved', async () => {
  const db = getDb();
  const f = fakes();
  await seedPerson(db, 'u1');
  await db.collection('deletion_requests').doc('u1').update({ status: 'pending' });
  assert.equal((await deleteAccount(db, f.auth, f.storage, 'u1', NOW)).action, 'skipped');
  assert.equal((await deleteAccount(db, f.auth, f.storage, 'nobody', NOW)).action, 'skipped');
  assert.equal((await deleteAccount(db, f.auth, f.storage, 'a/b', NOW)).action, 'skipped');
  assert.equal((await db.collection('users').doc('u1').get()).exists, true);
  assert.deepEqual(f.calls.deleted, []);
});

test('an approved deletion removes the person, keeps what others and the tax records need', async () => {
  const db = getDb();
  const f = fakes();
  await seedPerson(db, 'u1');
  const r = await deleteAccount(db, f.auth, f.storage, 'u1', NOW);
  assert.equal(r.action, 'deleted');

  // gone
  assert.equal((await db.collection('users').doc('u1').get()).exists, false);
  assert.equal((await db.collection('users').doc('u1').collection('credits').get()).size, 0);
  assert.equal((await db.collection('users').doc('u1').collection('devices').get()).size, 0);
  assert.equal((await db.collection('identity_index').doc('hash1').get()).exists, false);
  assert.equal((await db.collection('referral_codes').doc('ABC234').get()).exists, false);
  assert.equal((await db.collection('notifications').doc('n1').get()).exists, false);
  assert.equal((await db.collection('rate_limits').doc('u1_offer').get()).exists, false);
  for (const c of ['credit_balances', 'public_trust', 'trip_counts']) assert.equal((await db.collection(c).doc('u1').get()).exists, false, c);
  assert.equal((await db.collection('trip_counts').doc('u1').collection('seen').get()).size, 0);
  assert.deepEqual(f.calls.deleted, ['u1']);
  assert.deepEqual(f.calls.prefixes, ['users/u1/']);

  // others untouched
  assert.equal((await db.collection('identity_index').doc('hash2').get()).exists, true);
  assert.equal((await db.collection('notifications').doc('n2').get()).exists, true);
  assert.equal((await db.collection('rate_limits').doc('u12_offer').get()).exists, true, 'u12 is another person');

  // kept, with the personal fields cleared
  const b1 = (await db.collection('bookings').doc('B1').get()).data();
  assert.equal(b1.driverName, '');
  assert.equal(b1.driverPhone, '');
  assert.equal(b1.vehicleNumber, '');
  assert.equal(b1.anonymised, true);
  assert.equal(b1.pickup, 'Pune');
  const b2 = (await db.collection('bookings').doc('B2').get()).data();
  assert.equal(b2.customerName, '');
  assert.equal(b2.customerPhone, '');
  assert.equal(b2.driverName, 'Ravi', 'the other side keeps their own details');

  // money records stay
  assert.equal((await db.collection('ledger').doc('B1_trip_earning').get()).exists, true);
  assert.equal((await db.collection('payouts').doc('p1').get()).exists, true);

  // the request is closed
  const req = (await db.collection('deletion_requests').doc('u1').get()).data();
  assert.equal(req.status, 'done');
  assert.equal(req.deletedBy, 'server');
  assert.equal(req.completedAt.toMillis(), NOW);
});

test('an open payout blocks the deletion and puts the request back to pending with the reason', async () => {
  const db = getDb();
  const f = fakes();
  await seedPerson(db, 'u1');
  await db.collection('payouts').doc('p2').set({ driverId: 'u1', amountPaise: 900, status: 'approved' });
  const r = await deleteAccount(db, f.auth, f.storage, 'u1', NOW);
  assert.deepEqual(r, { action: 'blocked', reason: 'open_payout' });
  assert.equal((await db.collection('users').doc('u1').get()).exists, true);
  assert.deepEqual(f.calls.deleted, []);
  const req = (await db.collection('deletion_requests').doc('u1').get()).data();
  assert.equal(req.status, 'pending');
  assert.equal(req.blockedReason, 'open_payout');
});

test('an admin account is never deleted this way', async () => {
  const db = getDb();
  const f = fakes();
  await seedPerson(db, 'u1');
  await db.collection('admins').doc('u1').set({ role: 'finance' });
  assert.deepEqual(await deleteAccount(db, f.auth, f.storage, 'u1', NOW), { action: 'blocked', reason: 'admin_account' });
  assert.equal((await db.collection('users').doc('u1').get()).exists, true);
});

test('a sign-in that is already gone does not stop the deletion; any other sign-in error does, and the run can be repeated', async () => {
  const db = getDb();
  await seedPerson(db, 'u1');
  const gone = fakes();
  gone.auth.deleteUser = async () => {
    const e = new Error('no user');
    e.code = 'auth/user-not-found';
    throw e;
  };
  assert.equal((await deleteAccount(db, gone.auth, gone.storage, 'u1', NOW)).action, 'deleted');

  await clearDb();
  await seedPerson(db, 'u2');
  const broken = fakes();
  broken.auth.deleteUser = async () => {
    const e = new Error('network');
    e.code = 'auth/internal-error';
    throw e;
  };
  await assert.rejects(deleteAccount(db, broken.auth, broken.storage, 'u2', NOW));
  assert.equal((await db.collection('users').doc('u2').get()).exists, true, 'the user document goes last, so the run can be repeated');
  const good = fakes();
  assert.equal((await deleteAccount(db, good.auth, good.storage, 'u2', NOW)).action, 'deleted');
  assert.equal((await db.collection('users').doc('u2').get()).exists, false);
});

test('more bookings than one page are all cleaned', async () => {
  const db = getDb();
  const f = fakes();
  await db.collection('deletion_requests').doc('u1').set({ userId: 'u1', status: 'approved', createdAt: Timestamp.fromMillis(NOW) });
  const batch = db.batch();
  for (let i = 0; i < 650; i++) batch.set(db.collection('bookings').doc(`b${String(i).padStart(4, '0')}`), { driverId: 'u1', driverName: 'Asha', driverPhone: '1' });
  await batch.commit();
  const r = await deleteAccount(db, f.auth, f.storage, 'u1', NOW);
  assert.equal(r.counts.bookings, 650);
  const left = await db.collection('bookings').where('driverName', '==', 'Asha').count().get();
  assert.equal(left.data().count, 0);
});
