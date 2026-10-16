'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { recomputeWallet, validatePayout, reconcileAll, decidePayout } = require('../../src/wallet');
const { ActionError } = require('../../src/adminActions');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('admins').doc('fin2').set({ role: 'finance' });
  await db.collection('admins').doc('boss').set({ createdBy: 'console' });
  await db.collection('admins').doc('sup1').set({ role: 'support' });
});

const line = (db, uid, id, type, amountPaise) => db.collection('ledger').doc(id).set({ driverId: uid, bookingId: id.split('_')[0], type, amountPaise, createdAt: Timestamp.fromMillis(NOW) });
const wallet = async (db, uid) => (await db.collection('wallets').doc(uid).get()).data();

test('the summary is the sum of the lines and payouts, and is written to wallets/{uid}', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  await line(db, 'd1', 'B1_platform_commission', 'platform_commission', -5000);
  await line(db, 'd2', 'B2_trip_earning', 'trip_earning', 777);
  await db.collection('payouts').doc('p1').set({ driverId: 'd1', amountPaise: 20000, status: 'requested' });
  await db.collection('payouts').doc('p2').set({ driverId: 'd1', amountPaise: 10000, status: 'paid' });
  await db.collection('bookings').doc('B9').set({ driverId: 'd1', status: 'delivered', paymentStatus: 'customer_marked_paid', paidAmountPaise: 40000 });
  await db.collection('bookings').doc('B8').set({ assignedDriverId: 'd1', driverId: 'fleet', status: 'delivered', paymentStatus: 'pending', agreedFarePaise: 5000 });
  const s = await recomputeWallet(db, 'd1', NOW);
  assert.equal(s.netPaise, 95000);
  assert.equal(s.availablePaise, 65000);
  assert.equal(s.heldPaise, 20000);
  assert.equal(s.paidOutPaise, 10000);
  assert.equal(s.pendingPaise, 45000);
  assert.equal(s.lines, 2);
  assert.equal(s.payouts, 2);
  assert.deepEqual(await wallet(db, 'd1'), { ...s, updatedAt: Timestamp.fromMillis(NOW) });
  assert.equal((await wallet(db, 'd2')), undefined, 'only the asked person is written');
  assert.equal(await recomputeWallet(db, 'a/b', NOW), null);
});

test('parallel ledger writes and parallel recomputes end with the right total', async () => {
  const db = getDb();
  await Promise.all(Array.from({ length: 30 }, (_, i) => line(db, 'd1', `B${i}_trip_earning`, 'trip_earning', 1000 + i)));
  await Promise.all(Array.from({ length: 8 }, () => recomputeWallet(db, 'd1', NOW)));
  const s = await wallet(db, 'd1');
  assert.equal(s.availablePaise, 30 * 1000 + (29 * 30) / 2);
  assert.equal(s.lines, 30);
  // And again after more writes mixed with recomputes.
  await Promise.all([
    ...Array.from({ length: 10 }, (_, i) => line(db, 'd1', `C${i}_trip_earning`, 'trip_earning', 500)),
    ...Array.from({ length: 5 }, () => recomputeWallet(db, 'd1', NOW)),
  ]);
  const final = await recomputeWallet(db, 'd1', NOW);
  assert.equal(final.lines, 40);
  assert.equal(final.availablePaise, 30 * 1000 + 435 + 5000);
});

test('running the recompute twice gives the same document', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 1234);
  const a = await recomputeWallet(db, 'd1', NOW);
  const b = await recomputeWallet(db, 'd1', NOW);
  assert.deepEqual(a, b);
});

async function request(db, id, uid, amount) {
  await db.collection('payouts').doc(id).set({ driverId: uid, amountPaise: amount, status: 'requested', createdAt: Timestamp.fromMillis(NOW) });
  return (await db.collection('payouts').doc(id).get()).data();
}

test('a request within what is available is left alone', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  const p = await request(db, 'p1', 'd1', 100000);
  assert.deepEqual(await validatePayout(db, 'p1', p, NOW), { action: 'ok' });
  assert.equal((await db.collection('payouts').doc('p1').get()).data().status, 'requested');
  const s = await wallet(db, 'd1');
  assert.equal(s.heldPaise, 100000);
  assert.equal(s.availablePaise, 0);
});

test('a request for more than is available is rejected by the server with a reason and an audit line', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  const p = await request(db, 'p1', 'd1', 100001);
  assert.deepEqual(await validatePayout(db, 'p1', p, NOW), { action: 'rejected', reason: 'over_available' });
  const d = (await db.collection('payouts').doc('p1').get()).data();
  assert.equal(d.status, 'rejected');
  assert.equal(d.reason, 'server:over_available');
  assert.equal(d.handledBy, 'server');
  assert.equal((await db.collection('audit_events').get()).docs[0].data().data.action, 'payout_auto_reject');
  assert.equal((await wallet(db, 'd1')).heldPaise, 0);
});

test('a second open request is rejected; money already asked for is not available again', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  await db.collection('payouts').doc('first').set({ driverId: 'd1', amountPaise: 60000, status: 'approved' });
  const p = await request(db, 'second', 'd1', 10000);
  assert.deepEqual(await validatePayout(db, 'second', p, NOW), { action: 'rejected', reason: 'another_open_request' });
});

test('two requests at once: at most one stays open', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  const a = await request(db, 'pa', 'd1', 80000);
  const b = await request(db, 'pb', 'd1', 80000);
  await Promise.all([validatePayout(db, 'pa', a, NOW), validatePayout(db, 'pb', b, NOW)]);
  const statuses = [(await db.collection('payouts').doc('pa').get()).data().status, (await db.collection('payouts').doc('pb').get()).data().status];
  assert.ok(statuses.filter((s) => s === 'requested').length <= 1, statuses.join());
  assert.ok(statuses.includes('rejected') || statuses.filter((s) => s === 'requested').length === 1);
});

test('odd payouts are skipped or rejected, never crash', async () => {
  const db = getDb();
  assert.equal((await validatePayout(db, 'x', null, NOW)).action, 'skipped');
  assert.equal((await validatePayout(db, 'x', { status: 'paid', driverId: 'd1' }, NOW)).action, 'skipped');
  assert.equal((await validatePayout(db, 'a/b', { status: 'requested', driverId: 'd1' }, NOW)).action, 'skipped');
  await db.collection('payouts').doc('bad').set({ driverId: 'd1', amountPaise: -5, status: 'requested' });
  assert.deepEqual(await validatePayout(db, 'bad', { status: 'requested', driverId: 'd1' }, NOW), { action: 'rejected', reason: 'bad_amount' });
});

test('the daily check writes a report and lists an overdrawn person', async () => {
  const db = getDb();
  await line(db, 'good', 'G1_trip_earning', 'trip_earning', 5000);
  await line(db, 'bad', 'X1_trip_earning', 'trip_earning', 1000);
  await db.collection('payouts').doc('p1').set({ driverId: 'bad', amountPaise: 5000, status: 'paid' });
  await db.collection('payouts').doc('p2').set({ driverId: 'only-payout', amountPaise: 100, status: 'requested' });
  const r = await reconcileAll(db, NOW);
  assert.equal(r.day, '20261015');
  assert.equal(r.checked, 3);
  assert.deepEqual(r.problems.map((p) => p.uid).sort(), ['bad', 'only-payout']);
  const stored = (await db.collection('reconciliation_reports').doc('20261015').get()).data();
  assert.equal(stored.checked, 3);
  assert.equal((await wallet(db, 'good')).availablePaise, 5000);
  const again = await reconcileAll(db, NOW);
  assert.equal(again.checked, 3, 'a second run overwrites the same day');
  assert.equal((await db.collection('reconciliation_reports').get()).size, 1);
});

async function denied(promise, code) {
  await assert.rejects(promise, (e) => e instanceof ActionError && e.code === code, `expected ${code}`);
}

test('maker-checker through the server: approve, a different admin pays with a reference, the summary follows', async () => {
  const db = getDb();
  await line(db, 'd1', 'B1_trip_earning', 'trip_earning', 100000);
  await db.collection('payouts').doc('p1').set({ driverId: 'd1', amountPaise: 60000, status: 'requested' });
  await denied(decidePayout(db, 'sup1', { payoutId: 'p1', action: 'approve' }, NOW), 'permission-denied');
  await denied(decidePayout(db, 'fin1', { payoutId: 'p1', action: 'pay', reference: 'UTR1234' }, NOW), 'failed-precondition');
  await decidePayout(db, 'fin1', { payoutId: 'p1', action: 'approve' }, NOW);
  assert.equal((await db.collection('payouts').doc('p1').get()).data().approvedBy, 'fin1');
  await denied(decidePayout(db, 'fin1', { payoutId: 'p1', action: 'pay', reference: 'UTR1234' }, NOW), 'permission-denied');
  await denied(decidePayout(db, 'fin2', { payoutId: 'p1', action: 'pay', reference: 'ab' }, NOW), 'invalid-argument');
  await decidePayout(db, 'fin2', { payoutId: 'p1', action: 'pay', reference: ' UTR1234 ' }, NOW);
  const p = (await db.collection('payouts').doc('p1').get()).data();
  assert.equal(p.status, 'paid');
  assert.equal(p.paidBy, 'fin2');
  assert.equal(p.reference, 'UTR1234');
  const s = await wallet(db, 'd1');
  assert.equal(s.paidOutPaise, 60000);
  assert.equal(s.heldPaise, 0);
  assert.equal(s.availablePaise, 40000);
  const audits = (await db.collection('audit_events').get()).docs.map((d) => d.data());
  assert.deepEqual(audits.map((a) => a.data.action).sort(), ['approve', 'pay']);
  assert.ok(audits.every((a) => a.type === 'payout_decision' && a.data.via === 'server'));
});

test('super may approve and a finance admin pay; reject and reverse need reasons; settled payouts cannot move', async () => {
  const db = getDb();
  await db.collection('payouts').doc('p1').set({ driverId: 'd1', amountPaise: 1000, status: 'requested' });
  await decidePayout(db, 'boss', { payoutId: 'p1', action: 'approve' }, NOW);
  await decidePayout(db, 'fin1', { payoutId: 'p1', action: 'pay', reference: 'UTR9999' }, NOW);
  await denied(decidePayout(db, 'fin2', { payoutId: 'p1', action: 'reject', reason: 'late' }, NOW), 'failed-precondition');
  await denied(decidePayout(db, 'fin2', { payoutId: 'p1', action: 'reverse' }, NOW), 'invalid-argument');
  await denied(decidePayout(db, 'fin2', { payoutId: 'p1', action: 'reverse', reason: 'oops' }, NOW), 'invalid-argument');
  await decidePayout(db, 'fin2', { payoutId: 'p1', action: 'reverse', reason: 'Bank returned it' }, NOW);
  assert.equal((await db.collection('payouts').doc('p1').get()).data().status, 'reversed');
  await denied(decidePayout(db, 'fin2', { payoutId: 'p1', action: 'approve' }, NOW), 'failed-precondition');
  await db.collection('payouts').doc('p2').set({ driverId: 'd1', amountPaise: 1000, status: 'requested' });
  await denied(decidePayout(db, 'fin1', { payoutId: 'p2', action: 'reject' }, NOW), 'invalid-argument');
  await decidePayout(db, 'fin1', { payoutId: 'p2', action: 'reject', reason: 'Name does not match' }, NOW);
  assert.equal((await db.collection('payouts').doc('p2').get()).data().reason, 'Name does not match');
});

test('bad input and unknown payouts', async () => {
  const db = getDb();
  await denied(decidePayout(db, 'fin1', { payoutId: 'a/b', action: 'approve' }, NOW), 'invalid-argument');
  await denied(decidePayout(db, 'fin1', { payoutId: 'p1', action: 'steal' }, NOW), 'invalid-argument');
  await denied(decidePayout(db, 'fin1', null, NOW), 'invalid-argument');
  await denied(decidePayout(db, 'fin1', { payoutId: 'ghost', action: 'approve' }, NOW), 'not-found');
  await denied(decidePayout(db, null, { payoutId: 'p1', action: 'approve' }, NOW), 'unauthenticated');
});

test('two admins approve the same payout at the same time: only one wins', async () => {
  const db = getDb();
  await db.collection('payouts').doc('p1').set({ driverId: 'd1', amountPaise: 1000, status: 'requested' });
  const results = await Promise.allSettled([decidePayout(db, 'fin1', { payoutId: 'p1', action: 'approve' }, NOW), decidePayout(db, 'fin2', { payoutId: 'p1', action: 'approve' }, NOW)]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const audits = (await db.collection('audit_events').get()).docs.filter((d) => d.data().data.action === 'approve');
  assert.equal(audits.length, 1);
});
