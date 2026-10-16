'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { createOrder, verifyPayment, refundPayment, expectedSignature, PaymentError } = require('../../src/razorpay');
const { requireStaff } = require('../../src/adminActions');

const SECRET = 'test_secret_not_real';

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('admins').doc('sup1').set({ role: 'support' });
  await db.collection('bookings').doc('B1').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 1250000, fareEstimate: 900000 });
  await db.collection('bookings').doc('B2').set({ customerId: 'cust1', fareEstimate: 500000 });
  await db.collection('bookings').doc('B3').set({ customerId: 'cust1' });
});

const fakeHttp = (calls = []) => async (method, path, body) => {
  calls.push({ method, path, body });
  return { id: `order_${calls.length}`, amount: body.amount };
};
async function denied(p, code) {
  await assert.rejects(p, (e) => e instanceof PaymentError && e.code === code, `expected ${code}`);
}

test('createOrder: the amount comes from the booking, not from the phone', async () => {
  const calls = [];
  const r = await createOrder(getDb(), fakeHttp(calls), 'cust1', { bookingId: 'B1', amountPaise: 1 });
  assert.equal(r.amountPaise, 1250000);
  assert.equal(calls[0].body.amount, 1250000);
  assert.equal(calls[0].body.currency, 'INR');
  const saved = (await getDb().collection('payment_orders').doc(r.orderId).get()).data();
  assert.equal(saved.status, 'created');
  assert.equal(saved.customerId, 'cust1');
  const r2 = await createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B2' });
  assert.equal(r2.amountPaise, 500000, 'falls back to the estimate');
});

test('createOrder: pressing Pay again gives the same open order; a paid or changed one makes a new order', async () => {
  const calls = [];
  const a = await createOrder(getDb(), fakeHttp(calls), 'cust1', { bookingId: 'B1' });
  const b = await createOrder(getDb(), fakeHttp(calls), 'cust1', { bookingId: 'B1' });
  assert.equal(b.orderId, a.orderId);
  assert.equal(b.again, true);
  assert.equal(calls.length, 1, 'the gateway was asked once');
  assert.equal((await getDb().collection('payment_orders').get()).size, 1);
  // a different amount (the fare changed) is a new order
  await getDb().collection('bookings').doc('B1').update({ agreedFarePaise: 1300000 });
  const c = await createOrder(getDb(), fakeHttp(calls), 'cust1', { bookingId: 'B1' });
  assert.notEqual(c.orderId, a.orderId);
  // after the half hour it is also a new order
  const later = await createOrder(getDb(), fakeHttp(calls), 'cust1', { bookingId: 'B1' }, Date.now() + 31 * 60 * 1000);
  assert.notEqual(later.orderId, c.orderId);
});

test('createOrder: only the booking customer; no amount, no booking and bad input are refused', async () => {
  await denied(createOrder(getDb(), fakeHttp(), 'cust2', { bookingId: 'B1' }), 'permission-denied');
  await denied(createOrder(getDb(), fakeHttp(), 'drv1', { bookingId: 'B1' }), 'permission-denied');
  await denied(createOrder(getDb(), fakeHttp(), undefined, { bookingId: 'B1' }), 'unauthenticated');
  await denied(createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B3' }), 'failed-precondition');
  await denied(createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'NOPE' }), 'not-found');
  await denied(createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: '../x' }), 'invalid-argument');
  await denied(createOrder(getDb(), fakeHttp(), 'cust1', {}), 'invalid-argument');
});

test('createOrder: an odd answer from the gateway is not stored', async () => {
  const odd = async () => ({ id: 'order_x', amount: 1 });
  await denied(createOrder(getDb(), odd, 'cust1', { bookingId: 'B1' }), 'unavailable');
  assert.equal((await getDb().collection('payment_orders').get()).size, 0);
});

test('verifyPayment: a good signature marks the order paid once; again is safe', async () => {
  const { orderId } = await createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B1' });
  const sig = expectedSignature(orderId, 'pay_1', SECRET);
  assert.deepEqual(await verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_1', signature: sig }), { ok: true });
  assert.equal((await getDb().collection('payment_orders').doc(orderId).get()).data().status, 'paid');
  assert.deepEqual(await verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_1', signature: sig }), { ok: true, again: true });
  await denied(verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_2', signature: expectedSignature(orderId, 'pay_2', SECRET) }), 'failed-precondition');
});

test('verifyPayment: bad signature, other person, unknown order, bad ids are refused and nothing changes', async () => {
  const { orderId } = await createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B1' });
  await denied(verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_1', signature: 'abc' }), 'permission-denied');
  await denied(verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_1', signature: expectedSignature(orderId, 'pay_1', 'wrong') }), 'permission-denied');
  await denied(verifyPayment(getDb(), SECRET, 'cust2', { orderId, paymentId: 'pay_1', signature: expectedSignature(orderId, 'pay_1', SECRET) }), 'permission-denied');
  await denied(verifyPayment(getDb(), SECRET, 'cust1', { orderId: 'order_none', paymentId: 'p', signature: 's' }), 'not-found');
  await denied(verifyPayment(getDb(), SECRET, 'cust1', { orderId: '../x', paymentId: 'p', signature: 's' }), 'invalid-argument');
  await denied(verifyPayment(getDb(), SECRET, undefined, { orderId, paymentId: 'p', signature: 's' }), 'unauthenticated');
  assert.equal((await getDb().collection('payment_orders').doc(orderId).get()).data().status, 'created');
});

const staff = (d, u) => requireStaff(d, u, ['super', 'finance']);

test('refund: finance may refund up to what was paid, in total, and not more', async () => {
  const { orderId } = await createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B1' });
  await verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_1', signature: expectedSignature(orderId, 'pay_1', SECRET) });
  const calls = [];
  const http = async (m, p, b) => { calls.push({ m, p, b }); return {}; };
  assert.deepEqual(await refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 1000000 }, staff), { ok: true, refundedPaise: 1000000 });
  assert.equal(calls[0].p, '/payments/pay_1/refund');
  assert.equal(calls[0].b.amount, 1000000);
  await denied(refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 250001 }, staff), 'failed-precondition');
  assert.equal((await refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 250000 }, staff)).refundedPaise, 1250000);
  await denied(refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 1 }, staff), 'failed-precondition');
  assert.equal(calls.length, 2, 'nothing is sent for a refused refund');
});

test('refund: other staff, customers, unpaid orders and bad amounts are refused', async () => {
  const { orderId } = await createOrder(getDb(), fakeHttp(), 'cust1', { bookingId: 'B1' });
  const http = async () => ({});
  await assert.rejects(refundPayment(getDb(), http, 'sup1', { orderId, amountPaise: 1 }, staff), (e) => e.code === 'permission-denied');
  await assert.rejects(refundPayment(getDb(), http, 'cust1', { orderId, amountPaise: 1 }, staff), (e) => e.code === 'permission-denied');
  await denied(refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 1 }, staff), 'failed-precondition');
  await denied(refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 0 }, staff), 'invalid-argument');
  await denied(refundPayment(getDb(), http, 'fin1', { orderId, amountPaise: 1.5 }, staff), 'invalid-argument');
  await denied(refundPayment(getDb(), http, 'fin1', { orderId: '../x', amountPaise: 1 }, staff), 'invalid-argument');
});
