'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { monthKey, countTrip, refreshSummary, onDelivered } = require('../../src/trust');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);

test.beforeEach(clearDb);

test('monthKey is the UTC month', () => {
  assert.equal(monthKey(Date.UTC(2026, 0, 31, 23, 59)), '2026-01');
  assert.equal(monthKey(Date.UTC(2026, 11, 1)), '2026-12');
});

test('a delivered trip is counted once, however many times it is reported', async () => {
  const db = getDb();
  assert.equal(await countTrip(db, 'd1', 'B1', NOW, NOW), true);
  assert.equal(await countTrip(db, 'd1', 'B1', NOW, NOW), false);
  assert.equal(await countTrip(db, 'd1', 'B2', NOW, NOW), true);
  const c = (await db.collection('trip_counts').doc('d1').get()).data();
  assert.equal(c.total, 2);
  assert.equal(c.months['2026-10'], 2);
});

test('trips of different months are counted per month; parallel reports of one booking still count once', async () => {
  const db = getDb();
  await countTrip(db, 'd1', 'B1', Date.UTC(2026, 8, 30), NOW);
  await countTrip(db, 'd1', 'B2', Date.UTC(2026, 9, 1), NOW);
  const results = await Promise.all([1, 2, 3, 4, 5].map(() => countTrip(db, 'd1', 'B3', NOW, NOW)));
  assert.equal(results.filter(Boolean).length, 1);
  const c = (await db.collection('trip_counts').doc('d1').get()).data();
  assert.equal(c.total, 3);
  assert.equal(c.months['2026-09'], 1);
  assert.equal(c.months['2026-10'], 2);
});

test('unsafe ids are not counted', async () => {
  const db = getDb();
  assert.equal(await countTrip(db, 'a/b', 'B1', NOW, NOW), false);
  assert.equal(await countTrip(db, 'd1', '../x', NOW, NOW), false);
});

test('the public summary holds only safe fields and the real numbers', async () => {
  const db = getDb();
  await db.collection('users').doc('d1').set({ driverName: 'Ravi', driverPhone: '9876543210', verified: true, createdAt: Timestamp.fromMillis(Date.UTC(2026, 2, 5)), driverKyc: { dl: 'secret' } });
  await countTrip(db, 'd1', 'B1', NOW, NOW);
  await countTrip(db, 'd1', 'B2', NOW, NOW);
  for (const [i, stars] of [5, 4, 4].entries()) await db.collection('ratings').doc(`r${i}`).set({ ratedId: 'd1', raterId: `c${i}`, stars });
  await db.collection('ratings').doc('other').set({ ratedId: 'd2', raterId: 'c1', stars: 1 });
  const s = await refreshSummary(db, 'd1', NOW);
  assert.deepEqual(Object.keys(s).sort(), ['rating', 'ratingCount', 'since', 'trips', 'updatedAt', 'verified']);
  assert.equal(s.trips, 2);
  assert.equal(s.ratingCount, 3);
  assert.equal(s.rating, 4.3);
  assert.equal(s.verified, true);
  assert.equal(s.since, '2026-03');
  const stored = JSON.stringify((await db.collection('public_trust').doc('d1').get()).data());
  for (const secret of ['Ravi', '9876543210', 'secret', 'driverKyc']) assert.equal(stored.includes(secret), false, secret);
});

test('a driver with no trips and no ratings gets zeros and no rating, not an error', async () => {
  const db = getDb();
  const s = await refreshSummary(db, 'newbie', NOW);
  assert.equal(s.trips, 0);
  assert.equal(s.rating, null);
  assert.equal(s.ratingCount, 0);
  assert.equal(s.verified, false);
  assert.equal(s.since, null);
  assert.equal(await refreshSummary(db, 'a/b', NOW), null);
});

test('a delivered booking counts for the holder and the assigned driver', async () => {
  const db = getDb();
  const booking = { driverId: 'fleet1', assignedDriverId: 'd9', status: 'delivered', timeline: { delivered: Timestamp.fromMillis(NOW) } };
  const r = await onDelivered(db, 'B7', booking, NOW);
  assert.deepEqual(r.counted.sort(), ['d9', 'fleet1']);
  assert.equal((await db.collection('public_trust').doc('d9').get()).data().trips, 1);
  const again = await onDelivered(db, 'B7', booking, NOW);
  assert.deepEqual(again.counted, []);
  assert.equal((await db.collection('public_trust').doc('d9').get()).data().trips, 1);
  assert.equal((await onDelivered(db, 'B8', null, NOW)).action, 'skipped');
});

test('a holder who is also the assigned driver is counted once', async () => {
  const db = getDb();
  const r = await onDelivered(db, 'B1', { driverId: 'd1', assignedDriverId: 'd1' }, NOW);
  assert.deepEqual(r.counted, ['d1']);
  assert.equal((await db.collection('trip_counts').doc('d1').get()).data().total, 1);
});
