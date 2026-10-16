'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { expireOpenLoads, holdScheduled, suspendExpiredDocs, startOfDayMs, expiredBlockingDocs } = require('../../src/jobs');

const DAY = 24 * 3600 * 1000;
const NOW = Date.UTC(2026, 9, 15, 6, 30, 0); // 12:00 in India
const ts = (ms) => Timestamp.fromMillis(ms);

test.beforeEach(clearDb);

test('a day starts at midnight India time', () => {
  const start = startOfDayMs(NOW);
  assert.equal(new Date(start).toISOString(), '2026-10-14T18:30:00.000Z');
  assert.equal(startOfDayMs(start), start);
  assert.equal(startOfDayMs(start - 1), start - DAY);
});

test('open loads whose pickup day has passed are closed; today and the future stay open', async () => {
  const db = getDb();
  const day = startOfDayMs(NOW);
  await db.collection('loads').doc('old').set({ status: 'open', pickupDate: ts(day - DAY), createdAt: ts(NOW - 2 * DAY) });
  await db.collection('loads').doc('today').set({ status: 'open', pickupDate: ts(day + 3600 * 1000), createdAt: ts(NOW - 2 * DAY) });
  await db.collection('loads').doc('later').set({ status: 'open', pickupDate: ts(NOW + 5 * DAY), createdAt: ts(NOW - 40 * DAY) });
  await db.collection('loads').doc('matched').set({ status: 'matched', pickupDate: ts(day - 5 * DAY), createdAt: ts(NOW - 9 * DAY) });
  const r = await expireOpenLoads(db, NOW);
  assert.equal(r.closed, 1);
  const status = async (id) => (await db.collection('loads').doc(id).get()).data().status;
  assert.equal(await status('old'), 'closed');
  assert.equal((await db.collection('loads').doc('old').get()).data().closedReason, 'expired');
  assert.equal(await status('today'), 'open');
  assert.equal(await status('later'), 'open', 'a dated load is judged by its date, not by age');
  assert.equal(await status('matched'), 'matched');
  assert.equal((await db.collection('audit_events').get()).size, 1);
});

test('an open load with no pickup date is closed after 30 days', async () => {
  const db = getDb();
  await db.collection('loads').doc('undated-old').set({ status: 'open', createdAt: ts(NOW - 31 * DAY) });
  await db.collection('loads').doc('undated-new').set({ status: 'open', createdAt: ts(NOW - 5 * DAY) });
  assert.equal((await expireOpenLoads(db, NOW)).closed, 1);
  assert.equal((await db.collection('loads').doc('undated-old').get()).data().status, 'closed');
  assert.equal((await db.collection('loads').doc('undated-new').get()).data().status, 'open');
});

test('running the expiry job again changes nothing', async () => {
  const db = getDb();
  await db.collection('loads').doc('old').set({ status: 'open', pickupDate: ts(NOW - 3 * DAY), createdAt: ts(NOW - 5 * DAY) });
  assert.equal((await expireOpenLoads(db, NOW)).closed, 1);
  assert.equal((await expireOpenLoads(db, NOW)).closed, 0);
  assert.equal((await db.collection('audit_events').get()).size, 1);
});

test('more loads than one page are all handled', async () => {
  const db = getDb();
  const batch = db.batch();
  for (let i = 0; i < 450; i++) batch.set(db.collection('loads').doc(`l${String(i).padStart(3, '0')}`), { status: 'open', pickupDate: ts(NOW - 2 * DAY), createdAt: ts(NOW - 3 * DAY) });
  await batch.commit();
  assert.equal((await expireOpenLoads(db, NOW)).closed, 450);
});

test('a scheduled booking holds its free vehicle one lead time before pickup', async () => {
  const db = getDb();
  await db.collection('vehicles').doc('vNear').set({ availability: 'available' });
  await db.collection('vehicles').doc('vFar').set({ availability: 'available' });
  await db.collection('vehicles').doc('vBusy').set({ availability: 'on_trip' });
  await db.collection('bookings').doc('b1').set({ status: 'accepted', vehicleId: 'vNear', scheduledAt: ts(NOW + 30 * 60 * 1000) });
  await db.collection('bookings').doc('b2').set({ status: 'accepted', vehicleId: 'vFar', scheduledAt: ts(NOW + 5 * 3600 * 1000) });
  await db.collection('bookings').doc('b3').set({ status: 'accepted', vehicleId: 'vBusy', scheduledAt: ts(NOW + 10 * 60 * 1000) });
  await db.collection('bookings').doc('b4').set({ status: 'picked_up', vehicleId: 'vFar', scheduledAt: ts(NOW + 10 * 60 * 1000) });
  await db.collection('bookings').doc('b5').set({ status: 'accepted', scheduledAt: ts(NOW + 10 * 60 * 1000) }); // no vehicle: skipped
  const r = await holdScheduled(db, NOW);
  assert.equal(r.held, 1);
  const av = async (id) => (await db.collection('vehicles').doc(id).get()).data().availability;
  assert.equal(await av('vNear'), 'on_trip');
  assert.equal(await av('vFar'), 'available');
  assert.equal(await av('vBusy'), 'on_trip');
  assert.equal((await holdScheduled(db, NOW)).held, 0, 'again: nothing new');
});

const lastWeek = () => ts(NOW - 7 * DAY);
const nextYear = () => ts(NOW + 300 * DAY);

test('expired blocking papers: only insurance, permit and fitness count; PUC only warns', () => {
  const v = { docs: { insurance: { expiry: lastWeek() }, puc: { expiry: lastWeek() }, permit: { expiry: nextYear() }, fitness: { number: 'x' } } };
  assert.deepEqual(expiredBlockingDocs(v, NOW), ['insurance']);
  assert.deepEqual(expiredBlockingDocs({ docs: { puc: { expiry: lastWeek() } } }, NOW), []);
  for (const odd of [null, {}, { docs: null }, { docs: 'x' }, { docs: { insurance: 5 } }, { docs: { insurance: { expiry: 'soon' } } }]) {
    assert.deepEqual(expiredBlockingDocs(odd, NOW), []);
  }
});

test('vehicles with an expired paper are held, renewed ones lifted, overrides respected, busy ones left alone', async () => {
  const db = getDb();
  await db.collection('vehicles').doc('expired').set({ availability: 'available', docs: { insurance: { expiry: lastWeek() } } });
  await db.collection('vehicles').doc('overridden').set({ availability: 'available', docs: { permit: { expiry: lastWeek() } }, docOverrideUntil: ts(NOW + DAY) });
  await db.collection('vehicles').doc('busy').set({ availability: 'on_trip', docs: { insurance: { expiry: lastWeek() } } });
  await db.collection('vehicles').doc('renewed').set({ availability: 'doc_expired', docs: { insurance: { expiry: nextYear() } } });
  await db.collection('vehicles').doc('stillExpired').set({ availability: 'doc_expired', docs: { fitness: { expiry: lastWeek() } } });
  await db.collection('vehicles').doc('lapsedOverride').set({ availability: 'doc_expired', docs: { fitness: { expiry: lastWeek() } }, docOverrideUntil: ts(NOW + DAY) });
  const r = await suspendExpiredDocs(db, NOW);
  assert.equal(r.vehiclesHeld, 1);
  assert.equal(r.vehiclesLifted, 2);
  const av = async (id) => (await db.collection('vehicles').doc(id).get()).data().availability;
  assert.equal(await av('expired'), 'doc_expired');
  assert.equal(await av('overridden'), 'available');
  assert.equal(await av('busy'), 'on_trip');
  assert.equal(await av('renewed'), 'available');
  assert.equal(await av('stillExpired'), 'doc_expired');
  assert.equal(await av('lapsedOverride'), 'available', 'an admin override lifts the hold');
});

test('drivers with an expired licence are marked and lifted again when they renew; an override wins', async () => {
  const db = getDb();
  await db.collection('users').doc('expired').set({ driverKyc: { dlExpiry: lastWeek() } });
  await db.collection('users').doc('today').set({ driverKyc: { dlExpiry: ts(startOfDayMs(NOW) + 3600 * 1000) } });
  await db.collection('users').doc('over').set({ driverKyc: { dlExpiry: lastWeek() }, docOverrideUntil: ts(NOW + DAY) });
  await db.collection('users').doc('renewed').set({ docSuspended: true, driverKyc: { dlExpiry: nextYear() } });
  await db.collection('users').doc('customer').set({ name: 'Asha' });
  const r = await suspendExpiredDocs(db, NOW);
  assert.equal(r.driversSuspended, 1);
  assert.equal(r.driversLifted, 1);
  const get = async (id) => (await db.collection('users').doc(id).get()).data();
  assert.equal((await get('expired')).docSuspended, true);
  assert.equal((await get('today')).docSuspended, undefined, 'a licence that expires today is still valid today');
  assert.equal((await get('over')).docSuspended, undefined);
  assert.equal((await get('renewed')).docSuspended, false);
  const again = await suspendExpiredDocs(db, NOW);
  assert.deepEqual(again, { vehiclesHeld: 0, vehiclesLifted: 0, driversSuspended: 0, driversLifted: 0 });
});
