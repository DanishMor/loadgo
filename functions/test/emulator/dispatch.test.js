'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { autoAccept, runWave } = require('../../src/dispatch');

const ts = (ms) => Timestamp.fromMillis(ms);
const RULE = { maxPaise: 100000, minRating: 4, verifiedOnly: true };

test.beforeEach(clearDb);

async function seed(db, loadExtra = {}) {
  await db.collection('loads').doc('L1').set({ shipperId: 'c1', status: 'open', autoAccept: RULE, createdAt: ts(1000), ...loadExtra });
  await db.collection('public_trust').doc('d1').set({ rating: 4.6, verified: true });
  await db.collection('public_trust').doc('d2').set({ rating: 4.9, verified: true });
  await db.collection('public_trust').doc('d3').set({ rating: 3.1, verified: true });
  const offer = (id, price, status = 'pending') => db.collection('offers').doc(`L1_${id}`).set({ loadId: 'L1', driverId: id, customerId: 'c1', pricePaise: price, status, createdAt: ts(price) });
  await offer('d1', 90000);
  await offer('d2', 80000);
  await offer('d3', 50000);
  await offer('d4', 70000, 'withdrawn');
}

const status = async (db, id) => (await db.collection('offers').doc(`L1_${id}`).get()).data().status;

test('the cheapest bid that fits the rule is selected and the other open bids are rejected', async () => {
  const db = getDb();
  await seed(db);
  const r = await autoAccept(db, 'L1', FieldValue);
  assert.equal(r.accepted, 'L1_d2');
  assert.equal(await status(db, 'd2'), 'selected');
  assert.equal(await status(db, 'd1'), 'rejected');
  assert.equal(await status(db, 'd3'), 'rejected');
  assert.equal(await status(db, 'd4'), 'withdrawn', 'a withdrawn bid stays withdrawn');
  assert.equal((await db.collection('offers').doc('L1_d2').get()).data().autoAccepted, true);
});

test('no rule, a closed load or no bid that fits changes nothing', async () => {
  const db = getDb();
  await seed(db);
  await db.collection('loads').doc('L1').update({ autoAccept: FieldValue.delete() });
  assert.equal((await autoAccept(db, 'L1', FieldValue)).accepted, null);
  await db.collection('loads').doc('L1').set({ status: 'open', autoAccept: { ...RULE, maxPaise: 1000 } }, { merge: true });
  assert.equal((await autoAccept(db, 'L1', FieldValue)).accepted, null);
  await db.collection('loads').doc('L1').set({ status: 'matched', autoAccept: RULE }, { merge: true });
  assert.equal((await autoAccept(db, 'L1', FieldValue)).accepted, null);
  assert.equal(await status(db, 'd2'), 'pending');
  assert.equal((await autoAccept(db, 'nope', FieldValue)).accepted, null);
});

test('running it twice does not select a second bid', async () => {
  const db = getDb();
  await seed(db);
  await autoAccept(db, 'L1', FieldValue);
  const again = await autoAccept(db, 'L1', FieldValue);
  assert.equal(again.accepted, null, 'the others were rejected and the winner is no longer pending');
  assert.equal(await status(db, 'd2'), 'selected');
});

test('the wave job records the open ring on recent instant loads only, once per change', async () => {
  const db = getDb();
  const now = 10_000_000;
  await db.collection('loads').doc('i1').set({ status: 'open', createdAt: ts(now - 35 * 1000) });
  await db.collection('loads').doc('i2').set({ status: 'open', createdAt: ts(now - 200 * 1000) });
  await db.collection('loads').doc('b1').set({ status: 'open', mode: 'bid', createdAt: ts(now - 35 * 1000) });
  await db.collection('loads').doc('old').set({ status: 'open', createdAt: ts(now - 3600 * 1000) });
  await db.collection('loads').doc('m1').set({ status: 'matched', createdAt: ts(now - 35 * 1000) });
  assert.equal((await runWave(db, now)).updated, 2);
  assert.equal((await db.collection('loads').doc('i1').get()).data().dispatchWave, 1);
  assert.equal((await db.collection('loads').doc('i2').get()).data().dispatchStalled, true);
  assert.equal((await db.collection('loads').doc('b1').get()).data().dispatchWave, undefined);
  assert.equal((await runWave(db, now)).updated, 0, 'nothing changed since');
});
