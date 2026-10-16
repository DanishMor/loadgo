'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { SPECS, check, enforce, creatorOf } = require('../../src/limits');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);
const ago = (ms) => Timestamp.fromMillis(NOW - ms);

test.beforeEach(clearDb);

async function seedOffers(db, uid, times) {
  let i = 0;
  for (const t of times) await db.collection('offers').doc(`${uid}-o${i++}`).set({ driverId: uid, createdAt: ago(t) });
}

test('the hour limits are the same numbers as the rules and the app', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(SPECS).map(([k, s]) => [k, s.hour])),
    { load: 30, offer: 60, message: 120, call: 20, ticket: 10 },
  );
});

test('within the limits nothing happens', async () => {
  const db = getDb();
  await seedOffers(db, 'd1', [1000, 5000, 20000]);
  await db.collection('offers').doc('new').set({ driverId: 'd1', createdAt: ago(0) });
  const r = await enforce(db, 'offer', db.collection('offers').doc('new'), { driverId: 'd1' }, NOW);
  assert.equal(r.action, 'none');
  assert.equal((await db.collection('offers').doc('new').get()).exists, true);
  assert.equal((await db.collection('audit_events').get()).size, 0);
});

test('a burst over the minute limit removes the newest document and writes one audit line', async () => {
  const db = getDb();
  await seedOffers(db, 'd1', Array.from({ length: 10 }, (_, i) => i * 1000)); // 10 in the last 10 seconds
  await db.collection('offers').doc('burst').set({ driverId: 'd1', createdAt: ago(0) }); // the 11th
  const r = await enforce(db, 'offer', db.collection('offers').doc('burst'), { driverId: 'd1' }, NOW);
  assert.equal(r.action, 'removed');
  assert.equal(r.over[0].window, 'minute');
  assert.equal((await db.collection('offers').doc('burst').get()).exists, false);
  const audit = (await db.collection('audit_events').get()).docs.map((d) => d.data());
  assert.equal(audit.length, 1);
  assert.equal(audit[0].type, 'user_action');
  assert.equal(audit[0].data.action, 'server_limit');
  assert.equal(audit[0].data.limit, 10);
  assert.equal(audit[0].targetId, 'd1');
});

test('the hour limit counts older documents too, and other people are not affected', async () => {
  const db = getDb();
  await seedOffers(db, 'd1', Array.from({ length: 60 }, (_, i) => 120000 + i * 30000)); // 60 offers spread over the hour, none in the last 2 minutes
  await seedOffers(db, 'd2', [1000, 2000]);
  await db.collection('offers').doc('o-new').set({ driverId: 'd1', createdAt: ago(0) }); // the 61st
  const r = await check(db, 'offer', 'd1', NOW);
  assert.equal(r.over.length, 1);
  assert.equal(r.over[0].window, 'hour');
  assert.equal(r.over[0].count, 61);
  assert.equal((await check(db, 'offer', 'd2', NOW)).over.length, 0);
});

test('documents older than an hour do not count', async () => {
  const db = getDb();
  await seedOffers(db, 'd1', Array.from({ length: 80 }, (_, i) => 3600000 + 1000 + i));
  assert.deepEqual((await check(db, 'offer', 'd1', NOW)).counts, { minute: 0, hour: 0 });
});

test('chat messages are counted across all bookings (collection group)', async () => {
  const db = getDb();
  for (let b = 0; b < 3; b++) {
    for (let i = 0; i < 7; i++) {
      await db.collection('bookings').doc(`b${b}`).collection('messages').doc(`m${i}`).set({ senderId: 'u1', createdAt: ago(i * 1000) });
    }
  }
  const r = await check(db, 'message', 'u1', NOW);
  assert.equal(r.counts.minute, 21);
  assert.equal(r.over[0].window, 'minute'); // 21 > 20
  const ref = db.collection('bookings').doc('b0').collection('messages').doc('m0');
  const out = await enforce(db, 'message', ref, { senderId: 'u1' }, NOW);
  assert.equal(out.action, 'removed');
  assert.equal((await ref.get()).exists, false);
});

test('a document with no usable creator is skipped, never throws', async () => {
  const db = getDb();
  for (const data of [null, {}, { driverId: 5 }, { driverId: 'a/b' }, { driverId: '' }]) {
    assert.equal(creatorOf('offer', data), null);
    assert.equal((await enforce(db, 'offer', db.collection('offers').doc('x'), data, NOW)).action, 'skipped');
  }
  assert.equal((await enforce(db, 'unknown', db.collection('offers').doc('x'), { driverId: 'd1' }, NOW)).action, 'skipped');
});
