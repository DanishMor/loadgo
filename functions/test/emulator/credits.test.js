'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { recomputeBalance, onCreditLine, onReferral, MAX_REFERRALS_PER_PERSON } = require('../../src/credits');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);

test.beforeEach(clearDb);

async function line(db, uid, id, amountPaise, extra = {}) {
  const ref = db.collection('users').doc(uid).collection('credits').doc(id);
  await ref.set({ amountPaise, kind: 'admin_grant', createdAt: Timestamp.fromMillis(NOW), ...extra });
  return (await ref.get()).data();
}

test('the balance is the sum of every line and is written to credit_balances', async () => {
  const db = getDb();
  await line(db, 'u1', 'a', 20000);
  await line(db, 'u1', 'b', -5000, { kind: 'spend' });
  await line(db, 'u1', 'c', 1500);
  await line(db, 'u2', 'x', 99999);
  const r = await recomputeBalance(db, 'u1', NOW);
  assert.deepEqual(r, { balancePaise: 16500, lines: 3 });
  const doc = (await db.collection('credit_balances').doc('u1').get()).data();
  assert.equal(doc.balancePaise, 16500);
  assert.equal(doc.lines, 3);
  assert.equal(doc.updatedAt.toMillis(), NOW);
});

test('no lines is a zero balance; an unsafe id is skipped; damaged amounts are ignored by the sum', async () => {
  const db = getDb();
  assert.deepEqual(await recomputeBalance(db, 'nobody', NOW), { balancePaise: 0, lines: 0 });
  assert.equal(await recomputeBalance(db, 'a/b', NOW), null);
  await line(db, 'u1', 'ok', 700);
  await db.collection('users').doc('u1').collection('credits').doc('bad').set({ amountPaise: 'lots', kind: 'x' });
  assert.equal((await recomputeBalance(db, 'u1', NOW)).balancePaise, 700);
});

test('a spend within the balance is fine', async () => {
  const db = getDb();
  await line(db, 'u1', 'g', 50000);
  const data = await line(db, 'u1', 'spend_L1', -30000, { kind: 'spend', loadId: 'L1' });
  const r = await onCreditLine(db, 'u1', 'spend_L1', data, NOW);
  assert.equal(r.action, 'balanced');
  assert.equal(r.balancePaise, 20000);
});

test('an overspend marks the load with the shortfall and writes one audit line', async () => {
  const db = getDb();
  await db.collection('loads').doc('L1').set({ shipperId: 'u1', creditsUsedPaise: 50000 });
  await line(db, 'u1', 'g', 10000);
  const data = await line(db, 'u1', 'spend_L1', -50000, { kind: 'spend', loadId: 'L1' });
  const r = await onCreditLine(db, 'u1', 'spend_L1', data, NOW);
  assert.equal(r.action, 'overspend');
  assert.equal(r.balancePaise, -40000);
  assert.equal(r.shortfallPaise, 40000);
  assert.equal((await db.collection('loads').doc('L1').get()).data().creditsShortfallPaise, 40000);
  const audits = (await db.collection('audit_events').get()).docs.map((d) => d.data());
  assert.equal(audits.length, 1);
  assert.equal(audits[0].data.action, 'credit_overspend');
  assert.equal(audits[0].targetId, 'u1');
});

test('a later grant pays the shortfall back: the real balance is right again', async () => {
  const db = getDb();
  await line(db, 'u1', 'g', 10000);
  await line(db, 'u1', 'spend_L1', -50000, { kind: 'spend', loadId: 'L1' });
  await line(db, 'u1', 'g2', 40000);
  assert.equal((await recomputeBalance(db, 'u1', NOW)).balancePaise, 0);
});

async function referral(db, newUser, referrer, { createdAgoDays = 1, bonus = 10000 } = {}) {
  await db.collection('users').doc(newUser).set({ createdAt: Timestamp.fromMillis(NOW - createdAgoDays * 24 * 3600 * 1000) });
  await db.collection('users').doc(referrer).set({ name: 'Ref' }, { merge: true });
  await db.collection('referrals').doc(newUser).set({ referrerUid: referrer, code: 'ABC234', createdAt: Timestamp.fromMillis(NOW) });
  await line(db, newUser, 'referral_in', bonus, { kind: 'referral' });
  await line(db, referrer, `referral_from_${newUser}`, bonus, { kind: 'referral' });
  return (await db.collection('referrals').doc(newUser).get()).data();
}

test('a good referral is left alone', async () => {
  const db = getDb();
  const data = await referral(db, 'new1', 'old1');
  assert.deepEqual(await onReferral(db, 'new1', data, NOW), { action: 'ok' });
  assert.equal((await recomputeBalance(db, 'new1', NOW)).balancePaise, 10000);
});

test('a referral after the first 7 days is voided on both sides', async () => {
  const db = getDb();
  const data = await referral(db, 'new1', 'old1', { createdAgoDays: 9 });
  const r = await onReferral(db, 'new1', data, NOW);
  assert.equal(r.action, 'voided');
  assert.deepEqual(r.problems, ['too_late']);
  assert.equal((await recomputeBalance(db, 'new1', NOW)).balancePaise, 0);
  assert.equal((await recomputeBalance(db, 'old1', NOW)).balancePaise, 0);
  assert.equal((await db.collection('audit_events').get()).size, 1);
});

test('your own code and an unknown referrer are voided', async () => {
  const db = getDb();
  await db.collection('users').doc('me').set({ createdAt: Timestamp.fromMillis(NOW) });
  await db.collection('referrals').doc('me').set({ referrerUid: 'me' });
  await line(db, 'me', 'referral_in', 10000, { kind: 'referral' });
  await line(db, 'me', 'referral_from_me', 10000, { kind: 'referral' });
  const r = await onReferral(db, 'me', { referrerUid: 'me' }, NOW);
  assert.deepEqual(r.problems, ['own_code']);
  assert.equal((await recomputeBalance(db, 'me', NOW)).balancePaise, 0);
  await db.collection('users').doc('lone').set({ createdAt: Timestamp.fromMillis(NOW) });
  const r2 = await onReferral(db, 'lone', { referrerUid: 'ghost' }, NOW);
  assert.deepEqual(r2.problems, ['unknown_referrer']);
});

test('one person cannot collect more than the cap of referrals', async () => {
  const db = getDb();
  await db.collection('users').doc('boss').set({ name: 'Boss' });
  let last;
  for (let i = 0; i <= MAX_REFERRALS_PER_PERSON; i++) {
    last = await referral(db, `n${i}`, 'boss');
  }
  const r = await onReferral(db, `n${MAX_REFERRALS_PER_PERSON}`, last, NOW);
  assert.equal(r.action, 'voided');
  assert.deepEqual(r.problems, ['too_many']);
});

test('odd referral data never throws', async () => {
  const db = getDb();
  for (const data of [null, {}, { referrerUid: 5 }, { referrerUid: 'a/b' }]) {
    assert.equal((await onReferral(db, 'x1', data, NOW)).action, 'skipped');
  }
  assert.equal((await onReferral(db, 'a/b', { referrerUid: 'y' }, NOW)).action, 'skipped');
});
