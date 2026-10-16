'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { scanMessage } = require('../../src/chatScan');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);
const at = (ms) => Timestamp.fromMillis(NOW - ms);

test.beforeEach(clearDb);

async function say(db, bookingId, id, senderId, body, agoMs = 0) {
  const ref = db.collection('bookings').doc(bookingId).collection('messages').doc(id);
  await ref.set({ senderId, text: body, flagged: false, createdAt: at(agoMs) });
  return ref;
}

test('a normal message is left alone', async () => {
  const db = getDb();
  const ref = await say(db, 'b1', 'm1', 'u1', 'Truck will reach by 6 pm');
  const r = await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal(r.action, 'clean');
  assert.equal((await ref.get()).exists, true);
  assert.equal((await db.collection('violations').get()).size, 0);
});

test('a phone number is removed, a strike and a violation line are written', async () => {
  const db = getDb();
  await db.collection('users').doc('u1').set({ name: 'Asha' });
  const ref = await say(db, 'b1', 'm1', 'u1', 'call me on 9876543210');
  const r = await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal(r.action, 'violation');
  assert.equal(r.strikes, 1);
  assert.equal(r.blockedUntil, null);
  assert.equal((await ref.get()).exists, false);
  const v = (await db.collection('violations').doc('u1_1').get()).data();
  assert.equal(v.userId, 'u1');
  assert.equal(v.bookingId, 'b1');
  assert.equal(v.source, 'server');
  assert.ok(['phone', 'app'].includes(v.kind));
  const u = (await db.collection('users').doc('u1').get()).data();
  assert.equal(u.chatStrikes, 1);
  assert.equal(u.chatSeq, 1);
  assert.equal(u.chatBlockedUntil, undefined);
});

test('the strike ladder: the 3rd strike blocks chat for 24 hours, the 5th for 7 days with a review', async () => {
  const db = getDb();
  await db.collection('users').doc('u1').set({ chatStrikes: 2, chatSeq: 2 });
  let ref = await say(db, 'b1', 'm3', 'u1', 'whatsapp me');
  let r = await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal(r.strikes, 3);
  assert.equal(r.blockedUntil, NOW + 24 * 3600 * 1000);
  assert.equal((await db.collection('users').doc('u1').get()).data().chatBlockedUntil.toMillis(), NOW + 24 * 3600 * 1000);
  await db.collection('users').doc('u1').set({ chatStrikes: 4, chatSeq: 4 }, { merge: true });
  ref = await say(db, 'b1', 'm5', 'u1', 'ravi@okaxis pay here');
  r = await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal(r.strikes, 5);
  assert.equal(r.blockedUntil, NOW + 7 * 24 * 3600 * 1000);
  const u = (await db.collection('users').doc('u1').get()).data();
  assert.equal(u.chatReview, true);
  assert.equal(u.chatSeq, 5);
  assert.ok((await db.collection('violations').doc('u1_5').get()).exists);
});

test('a number split over two messages is caught with the earlier one', async () => {
  const db = getDb();
  await say(db, 'b1', 'm1', 'u1', '98765', 5000);
  const ref = await say(db, 'b1', 'm2', 'u1', '43210', 0);
  const r = await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal(r.action, 'violation');
  assert.equal(r.kind, 'phone');
});

test('running the scan twice for the same message (a retry) gives one strike, not two', async () => {
  const db = getDb();
  const ref = await say(db, 'b1', 'm1', 'u1', 'call me');
  const data = (await ref.get()).data();
  const a = await scanMessage(db, ref, data, NOW);
  const b = await scanMessage(db, ref, data, NOW);
  assert.equal(a.action, 'violation');
  assert.equal(b.action, 'skipped');
  assert.equal((await db.collection('violations').get()).size, 1);
  assert.equal((await db.collection('users').doc('u1').get()).data().chatStrikes, 1);
});

test('odd messages never throw', async () => {
  const db = getDb();
  const ref = db.collection('bookings').doc('b1').collection('messages').doc('x');
  for (const data of [null, {}, { senderId: 5, text: 'x' }, { senderId: 'u1' }, { senderId: 'u1', text: '' }, { senderId: 'a/b', text: 'call me' }, { senderId: 'u1', text: 5 }]) {
    const r = await scanMessage(db, ref, data, NOW);
    assert.equal(r.action, 'skipped');
  }
});

test('other people are not touched and groups use the parent id', async () => {
  const db = getDb();
  await db.collection('users').doc('u2').set({ chatStrikes: 1, chatSeq: 1 });
  const ref = db.collection('driver_groups').doc('g1').collection('messages').doc('m1');
  await ref.set({ senderId: 'u1', text: 'my number 9876543210', createdAt: at(0) });
  await scanMessage(db, ref, (await ref.get()).data(), NOW);
  assert.equal((await db.collection('users').doc('u2').get()).data().chatStrikes, 1);
  assert.equal((await db.collection('violations').doc('u1_1').get()).data().bookingId, 'g1');
});
