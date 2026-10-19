'use strict';
// Part 5 (H7): hostile-input fuzz of every server action that takes data from a caller.
// Rule: whatever arrives (wrong type, huge, NaN, prototype tricks, someone else's uid, a path in an id),
// the action either finishes or refuses with a TYPED error (a string `code`). It never crashes with a
// TypeError, never writes outside what it should, and never leaks an internal message. Emulator only.
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { setRiskTier, decideDriver, serverStatus } = require('../../src/adminActions');
const { decidePayout } = require('../../src/wallet');
const kyc = require('../../src/kyc');
const sms = require('../../src/sms');
const maps = require('../../src/maps');
const razorpay = require('../../src/razorpay');

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('admins').doc('boss').set({ createdBy: 'console' });
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('users').doc('d1').set({ driverName: 'Ravi', verified: false });
  await db.collection('payouts').doc('p1').set({ driverId: 'd1', amountPaise: 5000, status: 'requested' });
});

const deep = (n) => { let o = {}; for (let i = 0; i < n; i++) o = { a: o }; return o; };
const proto = JSON.parse('{"__proto__": {"admin": true}, "uid": "d1"}');
const HOSTILE = [
  undefined, null, 0, -1, 1.5, NaN, Infinity, -Infinity, 2 ** 53, true, '', ' ', 'x', 'x'.repeat(200000), '../admin', 'a/b', '<script>alert(1)</script>',
  "' OR 1=1 --", '${7*7}', '\u0000', [], [1, 2], ['uid'], {}, { uid: {} }, { uid: ['d1'] }, { uid: 'a/b' }, { uid: '../users/d1' }, { uid: 'd1', tier: ['banned'] },
  { uid: 'd1', tier: { toString: () => 'banned' } }, { constructor: { prototype: {} } }, proto, deep(500), { uid: 'd1', amountPaise: NaN },
  { amountPaise: -5, kind: 'x', number: {}, orderId: [], paymentId: 1 }, Object.create(null), () => 1,
];
const CALLERS = [undefined, null, '', 'nobody', 'a/b', {}, [], 5, 'boss', 'fin1', 'd1'];

// An outcome is fine when it resolves, or throws an error carrying a string `code` (our typed errors) and no stack-like message.
function acceptable(e) {
  assert.ok(e && typeof e === 'object', `thrown value is not an error: ${String(e)}`);
  assert.ok(!(e instanceof TypeError) && !(e instanceof RangeError) && !(e instanceof ReferenceError), `crash: ${e && e.stack}`);
  assert.equal(typeof e.code, 'string', `untyped error: ${e && e.message}`);
  assert.ok(!/at .*\.js:\d+/.test(String(e.message)), 'a stack line leaked into the message');
}
async function neverCrashes(fn) {
  try {
    await fn();
  } catch (e) {
    acceptable(e);
  }
}

test('admin actions: any caller x any input never crash and never change a user they should not', async () => {
  const db = getDb();
  for (const caller of CALLERS) {
    for (const input of HOSTILE) {
      await neverCrashes(() => setRiskTier(db, caller, input));
      await neverCrashes(() => decideDriver(db, caller, input));
      await neverCrashes(() => decidePayout(db, caller, input));
      await neverCrashes(() => serverStatus(db, caller));
    }
  }
  // Only the permitted caller with valid input may have changed anything; nobody banned the driver or approved the payout through junk.
  const u = (await db.collection('users').doc('d1').get()).data();
  assert.notEqual(u.riskTier, 'banned');
  const p = (await db.collection('payouts').doc('p1').get()).data();
  assert.equal(p.status, 'requested');
  assert.equal((await db.collection('admins').doc('d1').get()).exists, false, 'a junk call created an admin');
});

test('admin actions: a non-admin with perfect input is refused', async () => {
  const db = getDb();
  await assert.rejects(setRiskTier(db, 'd1', { uid: 'd1', tier: 'banned', reason: 'x' }), { code: 'permission-denied' });
  await assert.rejects(decideDriver(db, 'd1', { uid: 'd1', status: 'approved' }), { code: 'permission-denied' });
  await assert.rejects(decidePayout(db, 'd1', { payoutId: 'p1', action: 'approve' }), { code: 'permission-denied' });
});

test('payout decisions: replay and double calls give one result', async () => {
  const db = getDb();
  await db.collection('admins').doc('fin2').set({ role: 'finance' });
  const first = await decidePayout(db, 'fin1', { payoutId: 'p1', action: 'approve' });
  assert.equal(first.ok, true);
  await assert.rejects(decidePayout(db, 'fin1', { payoutId: 'p1', action: 'approve' }), { code: 'failed-precondition' });
  await assert.rejects(decidePayout(db, 'fin1', { payoutId: 'p1', action: 'pay', reference: 'UTR123456' }), { code: 'permission-denied' }); // the approver cannot pay
  // two finance people pay at the same moment: exactly one wins
  await db.collection('admins').doc('fin3').set({ role: 'finance' });
  const settled = await Promise.allSettled([
    decidePayout(db, 'fin2', { payoutId: 'p1', action: 'pay', reference: 'UTR111111' }),
    decidePayout(db, 'fin3', { payoutId: 'p1', action: 'pay', reference: 'UTR222222' }),
  ]);
  assert.equal(settled.filter((s) => s.status === 'fulfilled').length, 1);
  const audits = (await db.collection('audit_events').where('type', '==', 'payout_decision').get()).size;
  assert.equal(audits, 2, 'one line for the approval and one for the single payment');
});

test('kyc, sms, maps, payments: hostile input is refused with typed errors', async () => {
  const db = getDb();
  const http = async () => { throw new Error('the network must not be reached by junk input'); };
  const secret = 'fuzz-secret';
  await db.collection('config').doc('kyc').set({ provider: 'sandbox' });
  for (const caller of [undefined, 'u1', 'a/b', {}]) {
    for (const input of HOSTILE) {
      await neverCrashes(() => kyc.verify(db, caller, input));
      await neverCrashes(() => sms.emergencySms(db, http, caller, input));
      await neverCrashes(() => maps.route(db, http, caller, input));
      await neverCrashes(() => razorpay.createOrder(db, http, caller, input, Date.now(), 'key'));
      await neverCrashes(() => razorpay.verifyPayment(db, secret, caller, input));
      await neverCrashes(() => razorpay.refundPayment(db, http, caller, input, async () => { const e = new Error('no'); e.code = 'permission-denied'; throw e; }));
    }
  }
  assert.equal((await db.collection('payments').get().catch(() => ({ size: 0 }))).size || 0, 0, 'junk created a payment');
});

test('webhook: junk bodies, bad or missing signatures, wrong secrets, replays', async () => {
  const db = getDb();
  const secret = 'fuzz-webhook-secret';
  const bodies = [undefined, null, '', 'x', '{', '[]', '{}', 'null', '{"event":"payment.captured"}', 'x'.repeat(500000), Buffer.from([0, 255, 1])];
  for (const rawBody of bodies) {
    for (const signature of [undefined, null, '', 'abc', 'x'.repeat(5000), 'zz', 12]) {
      for (const eventId of [undefined, '', 'e1', '../e', 'x'.repeat(500)]) {
        let r;
        try {
          r = await razorpay.handleWebhook(db, { rawBody, signature, eventId, secret });
        } catch (e) {
          acceptable(e);
          continue;
        }
        assert.ok(r && typeof r.status === 'number', 'the answer has a status');
        assert.ok(r.status >= 400 || r.status === 200, `strange status ${r.status}`);
        assert.ok([400, 401, 403, 200].includes(r.status) || r.status >= 400);
      }
    }
  }
  // Nothing was recorded for any of the junk.
  assert.equal((await db.collection('payments').get().catch(() => ({ size: 0 }))).size || 0, 0);
});

test('parallel calls: ten risk-tier changes at once leave one consistent state and ten audit lines', async () => {
  const db = getDb();
  await Promise.all(Array.from({ length: 10 }, (_, i) => setRiskTier(db, 'boss', { uid: 'd1', tier: i % 2 ? 'review' : 'restricted', reason: `r${i}` })));
  const u = (await db.collection('users').doc('d1').get()).data();
  assert.ok(['review', 'restricted'].includes(u.riskTier));
  assert.equal((await db.collection('audit_events').where('type', '==', 'risk_change').get()).size, 10);
});
