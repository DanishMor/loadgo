'use strict';
// G9: the money records behind Razorpay: ledger lines, the webhook, refunds and replays.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { getDb, clearDb } = require('../helpers');
const {
  createOrder, verifyPayment, refundPayment, expectedSignature, handleWebhook, applyRefund, commissionPaise,
} = require('../../src/razorpay');
const { requireStaff } = require('../../src/adminActions');

const SECRET = 'test_secret_not_real';
const WH = 'test_webhook_secret_not_real';
const staff = (d, u) => requireStaff(d, u, ['super', 'finance']);

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('bookings').doc('B1').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 1000000, paymentStatus: 'pending' });
  await db.collection('bookings').doc('B2').set({ customerId: 'cust1', agreedFarePaise: 500000 });
  await db.collection('bookings').doc('B3').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 400000, paymentStatus: 'driver_confirmed' });
});

const fakeHttp = async (method, path, body) => ({ id: `order_${Math.random().toString(36).slice(2, 10)}`, amount: body.amount });
const sign = (body) => crypto.createHmac('sha256', WH).update(body).digest('hex');

async function order(bookingId = 'B1') {
  return (await createOrder(getDb(), fakeHttp, 'cust1', { bookingId })).orderId;
}
async function pay(orderId, paymentId = 'pay_1') {
  return verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId, signature: expectedSignature(orderId, paymentId, SECRET) });
}
const ledger = async () => (await getDb().collection('ledger').get()).docs.map((d) => ({ id: d.id, ...d.data() }));

test('commission is integer basis points, half rounded up', () => {
  assert.equal(commissionPaise(1000000, 500), 50000);
  assert.equal(commissionPaise(333, 500), 17); // 16.65
  assert.equal(commissionPaise(10, 500), 1); // 0.5 rounds up
  assert.equal(commissionPaise(9, 500), 0);
});

test('a verified payment marks the booking paid and writes both ledger lines once', async () => {
  const id = await order();
  await pay(id);
  const lines = await ledger();
  assert.deepEqual(lines.map((l) => l.id).sort(), ['B1_platform_commission', 'B1_trip_earning']);
  assert.equal(lines.find((l) => l.type === 'trip_earning').amountPaise, 1000000);
  assert.equal(lines.find((l) => l.type === 'platform_commission').amountPaise, -50000);
  const b = (await getDb().collection('bookings').doc('B1').get()).data();
  assert.equal(b.paymentStatus, 'driver_confirmed');
  assert.equal(b.paidAmountPaise, 1000000);
  assert.equal(b.paymentVia, 'razorpay');
  assert.ok(lines.every((l) => l.driverId === 'drv1' && l.bookingId === 'B1'));
  await pay(id); // the same payment again: nothing new
  assert.equal((await ledger()).length, 2);
});

test('a Pro driver pays the lower commission', async () => {
  await getDb().collection('users').doc('drv1').set({ plan: 'pro', planUntil: new Date(Date.now() + 86400000) });
  await pay(await order());
  assert.equal((await ledger()).find((l) => l.type === 'platform_commission').amountPaise, -20000);
});

test('config/pricing sets the commission', async () => {
  await getDb().collection('config').doc('pricing').set({ commissionPercent: 10 });
  await pay(await order());
  assert.equal((await ledger()).find((l) => l.type === 'platform_commission').amountPaise, -100000);
});

test('a booking already confirmed by hand, or without a driver, gets no ledger line from the server', async () => {
  await pay(await order('B3'));
  await pay(await order('B2'), 'pay_2');
  assert.equal((await ledger()).length, 0);
  assert.equal((await getDb().collection('bookings').doc('B3').get()).data().onlinePaidPaise, 400000);
});

function event(type, entity) {
  const key = type.startsWith('refund') ? 'refund' : 'payment';
  return JSON.stringify({ event: type, payload: { [key]: { entity } } });
}
async function hook(body, id, secretSig) {
  return handleWebhook(getDb(), { rawBody: Buffer.from(body), signature: secretSig === undefined ? sign(body) : secretSig, eventId: id, secret: WH });
}

test('webhook: a bad or missing signature is refused and nothing changes', async () => {
  const oid = await order();
  const body = event('payment.captured', { id: 'pay_9', order_id: oid, amount: 1000000 });
  assert.equal((await hook(body, 'ev1', 'abc')).status, 400);
  assert.equal((await hook(body, 'ev1', '')).status, 400);
  assert.equal((await hook(body, 'ev1', sign(body + ' '))).status, 400);
  assert.equal((await handleWebhook(getDb(), { rawBody: Buffer.from(body), signature: sign(body), eventId: 'ev1', secret: '' })).status, 400);
  assert.equal((await getDb().collection('payment_orders').doc(oid).get()).data().status, 'created');
  assert.equal((await getDb().collection('payment_events').get()).size, 0);
});

test('webhook: payment.captured settles the order and the books; a replay does nothing more', async () => {
  const oid = await order();
  const body = event('payment.captured', { id: 'pay_9', order_id: oid, amount: 1000000 });
  assert.deepEqual(await hook(body, 'ev1'), { status: 200, body: 'paid' });
  assert.equal((await getDb().collection('payment_orders').doc(oid).get()).data().status, 'paid');
  assert.equal((await ledger()).length, 2);
  assert.deepEqual(await hook(body, 'ev1'), { status: 200, body: 'duplicate' });
  // the phone's verify arriving later with the same payment is also safe
  assert.deepEqual(await pay(oid, 'pay_9'), { ok: true, again: true });
  assert.equal((await ledger()).length, 2);
});

test('webhook: verify first, then the webhook, counts once', async () => {
  const oid = await order();
  await pay(oid, 'pay_5');
  const body = event('payment.captured', { id: 'pay_5', order_id: oid, amount: 1000000 });
  await hook(body, 'ev2');
  assert.equal((await ledger()).length, 2);
});

test('webhook: an amount that differs from the order is flagged, not paid', async () => {
  const oid = await order();
  const body = event('payment.captured', { id: 'pay_9', order_id: oid, amount: 1 });
  assert.equal((await hook(body, 'ev3')).body, 'ignored');
  const o = (await getDb().collection('payment_orders').doc(oid).get()).data();
  assert.equal(o.status, 'mismatch');
  assert.equal(o.mismatchPaise, 1);
  assert.equal((await ledger()).length, 0);
});

test('webhook: unknown order, odd ids, other events and broken bodies are harmless', async () => {
  assert.equal((await hook(event('payment.captured', { id: 'pay_1', order_id: 'order_none', amount: 5 }), 'ev4')).body, 'ignored');
  assert.equal((await hook(event('payment.captured', { id: '../x', order_id: 'o', amount: 5 }), 'ev5')).body, 'ignored');
  assert.equal((await hook(JSON.stringify({ event: 'subscription.charged' }), 'ev6')).body, 'ignored');
  assert.equal((await hook('not json', 'ev7')).status, 400);
  assert.equal((await hook(event('payment.captured', {}), '')).status, 400);
  assert.equal((await ledger()).length, 0);
});

test('webhook: payment.failed only notes the time', async () => {
  const oid = await order();
  await hook(event('payment.failed', { id: 'pay_f', order_id: oid }), 'ev8');
  const o = (await getDb().collection('payment_orders').doc(oid).get()).data();
  assert.equal(o.status, 'created');
  assert.ok(o.lastFailureAt);
});

test('refund: takes back from the driver and returns the commission share, once per refund', async () => {
  const oid = await order();
  await pay(oid);
  const http = async () => ({ id: 'rfnd_1' });
  const r = await refundPayment(getDb(), http, 'fin1', { orderId: oid, amountPaise: 400000 }, staff);
  assert.equal(r.refundedPaise, 400000);
  const adj = (await ledger()).filter((l) => l.type === 'adjustment');
  assert.equal(adj.length, 1);
  // 400000 back to the customer; the driver loses 400000 - 5% commission share (20000) = 380000
  assert.equal(adj[0].amountPaise, -380000);
  assert.equal(adj[0].by, 'system_razorpay');
  // the webhook for the same refund changes nothing
  const body = event('refund.processed', { id: 'rfnd_1', payment_id: 'pay_1', amount: 400000 });
  await hook(body, 'ev9');
  assert.equal((await ledger()).filter((l) => l.type === 'adjustment').length, 1);
  assert.equal((await getDb().collection('payment_orders').doc(oid).get()).data().refundedPaise, 400000);
});

test('refund: the gateway refusing leaves the order untouched and frees the reserved amount', async () => {
  const oid = await order();
  await pay(oid);
  const boom = async () => { throw new Error('gateway down'); };
  await assert.rejects(refundPayment(getDb(), boom, 'fin1', { orderId: oid, amountPaise: 1000000 }, staff));
  const o = (await getDb().collection('payment_orders').doc(oid).get()).data();
  assert.equal(o.refundedPaise, undefined);
  assert.equal(o.refundPendingPaise, 0);
  const ok = await refundPayment(getDb(), async () => ({ id: 'rfnd_2' }), 'fin1', { orderId: oid, amountPaise: 1000000 }, staff);
  assert.equal(ok.refundedPaise, 1000000);
});

test('refund: two at the same moment cannot pass the total together', async () => {
  const oid = await order();
  await pay(oid);
  const slow = async () => { await new Promise((r) => setTimeout(r, 50)); return { id: 'r' + Math.random().toString(36).slice(2, 8) }; };
  const results = await Promise.allSettled([
    refundPayment(getDb(), slow, 'fin1', { orderId: oid, amountPaise: 700000 }, staff),
    refundPayment(getDb(), slow, 'fin1', { orderId: oid, amountPaise: 700000 }, staff),
  ]);
  // Never both. (On a very busy emulator both may be aborted; then nothing is refunded and nothing is left reserved.)
  const done = results.filter((r) => r.status === 'fulfilled').length;
  assert.ok(done <= 1, 'two refunds passed the total together');
  const o = (await getDb().collection('payment_orders').doc(oid).get()).data();
  assert.equal(o.refundedPaise || 0, 700000 * done);
  assert.ok(done === 1 || (o.refundPendingPaise || 0) === 0 || o.refundPendingAt, 'a reservation left behind carries its time');
});

test('refund started outside our app (webhook only) is applied and capped at the payment', async () => {
  const oid = await order();
  await pay(oid);
  await hook(event('refund.processed', { id: 'rfnd_x', payment_id: 'pay_1', amount: 999999999 }), 'ev10');
  assert.equal((await getDb().collection('payment_orders').doc(oid).get()).data().refundedPaise, 1000000);
  assert.equal((await applyRefund(getDb(), oid, 5, 'rfnd_y')).refundedPaise, 1000000);
});

test('refund of a payment that was never put in the ledger writes no adjustment', async () => {
  const oid = await order('B3');
  await pay(oid, 'pay_b3');
  await refundPayment(getDb(), async () => ({ id: 'rfnd_3' }), 'fin1', { orderId: oid, amountPaise: 1000 }, staff);
  assert.equal((await ledger()).length, 0);
});

test('G17: a person can start only so many new orders a day; giving back an open order does not use a turn', async () => {
  await getDb().collection('config').doc('paymentLimits').set({ perUserPerDay: 2, totalPerDay: 100 });
  await getDb().collection('bookings').doc('B4').set({ customerId: 'cust1', agreedFarePaise: 111100 });
  await getDb().collection('bookings').doc('B5').set({ customerId: 'cust1', agreedFarePaise: 222200 });
  await createOrder(getDb(), fakeHttp, 'cust1', { bookingId: 'B1' });
  await createOrder(getDb(), fakeHttp, 'cust1', { bookingId: 'B1' }); // the same open order: free
  await createOrder(getDb(), fakeHttp, 'cust1', { bookingId: 'B4' });
  await assert.rejects(createOrder(getDb(), fakeHttp, 'cust1', { bookingId: 'B5' }), (e) => e.code === 'resource-exhausted');
  assert.equal((await getDb().collection('payment_orders').get()).size, 2);
});
