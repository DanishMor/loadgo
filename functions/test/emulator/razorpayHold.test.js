'use strict';
// G21: payments held until the trip is delivered (switch payHold).
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { clearFlagCache } = require('../../src/common');
const { createOrder, verifyPayment, refundPayment, releaseHeld, expectedSignature, handleWebhook } = require('../../src/razorpay');
const { requireStaff } = require('../../src/adminActions');
const crypto = require('node:crypto');

const SECRET = 'test_secret_not_real';
const staff = (d, u) => requireStaff(d, u, ['super', 'finance']);

test.beforeEach(async () => {
  await clearDb();
  clearFlagCache();
  const db = getDb();
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('config').doc('features').set({ flags: { payHold: true } });
  await db.collection('bookings').doc('B1').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 1000000, paymentStatus: 'pending', status: 'in_transit' });
  await db.collection('bookings').doc('B2').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 500000, paymentStatus: 'pending', status: 'delivered' });
});

const fakeHttp = async (method, path, body) => ({ id: `order_${Math.random().toString(36).slice(2, 10)}`, amount: body.amount });
async function pay(bookingId, paymentId = 'pay_1') {
  const { orderId } = await createOrder(getDb(), fakeHttp, 'cust1', { bookingId });
  await verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId, signature: expectedSignature(orderId, paymentId, SECRET) });
  return orderId;
}
const ledger = async () => (await getDb().collection('ledger').get()).docs.map((d) => ({ id: d.id, ...d.data() }));
const booking = async (id) => (await getDb().collection('bookings').doc(id).get()).data();

test('before delivery the order is paid but the driver gets no ledger line; the booking records the hold', async () => {
  const oid = await pay('B1');
  assert.equal((await getDb().collection('payment_orders').doc(oid).get()).data().status, 'paid');
  assert.equal((await ledger()).length, 0);
  const b = await booking('B1');
  assert.deepEqual(b.paymentHold, { orderId: oid, paise: 1000000 });
  assert.equal(b.paymentStatus, 'pending', 'the driver cannot confirm a payment by hand and double count it');
  assert.equal(b.onlinePaidPaise, 1000000);
});

test('on delivery the held money becomes the earning and the commission, once', async () => {
  await pay('B1');
  await getDb().collection('bookings').doc('B1').update({ status: 'delivered' });
  assert.deepEqual(await releaseHeld(getDb(), 'B1'), { action: 'released', paise: 1000000 });
  const lines = await ledger();
  assert.deepEqual(lines.map((l) => l.id).sort(), ['B1_platform_commission', 'B1_trip_earning']);
  assert.equal(lines.find((l) => l.type === 'trip_earning').amountPaise, 1000000);
  assert.equal(lines.find((l) => l.type === 'platform_commission').amountPaise, -50000);
  const b = await booking('B1');
  assert.equal(b.paymentStatus, 'driver_confirmed');
  assert.equal(b.paymentHold, undefined);
  assert.equal((await releaseHeld(getDb(), 'B1')).action, 'skipped', 'a second run does nothing');
  assert.equal((await ledger()).length, 2);
});

test('not delivered yet: nothing is released', async () => {
  await pay('B1');
  assert.equal((await releaseHeld(getDb(), 'B1')).action, 'skipped');
  assert.equal((await ledger()).length, 0);
  assert.ok((await booking('B1')).paymentHold);
});

test('a refund before delivery lowers what is released; a full refund releases nothing', async () => {
  const oid = await pay('B1');
  await refundPayment(getDb(), async () => ({ id: 'rf1' }), 'fin1', { orderId: oid, amountPaise: 400000 }, staff);
  assert.equal((await ledger()).length, 0, 'there was nothing in the ledger to take back');
  await getDb().collection('bookings').doc('B1').update({ status: 'delivered' });
  assert.deepEqual(await releaseHeld(getDb(), 'B1'), { action: 'released', paise: 600000 });
  assert.equal((await ledger()).find((l) => l.type === 'trip_earning').amountPaise, 600000);

  await getDb().collection('bookings').doc('B3').set({ customerId: 'cust1', driverId: 'drv1', agreedFarePaise: 300000, paymentStatus: 'pending', status: 'in_transit' });
  const o3 = await pay('B3', 'pay_3');
  await refundPayment(getDb(), async () => ({ id: 'rf3' }), 'fin1', { orderId: o3, amountPaise: 300000 }, staff);
  await getDb().collection('bookings').doc('B3').update({ status: 'delivered' });
  assert.equal((await releaseHeld(getDb(), 'B3')).action, 'cleared');
  assert.ok(!(await ledger()).some((l) => l.bookingId === 'B3'));
  assert.equal((await booking('B3')).paymentHold, undefined);
});

test('G38: a booking cancelled while the money is held is noted once for finance, and nothing is paid out', async () => {
  const { noteCancelledHold } = require('../../src/razorpay');
  const oid = await pay('B1');
  await getDb().collection('bookings').doc('B1').update({ status: 'cancelled' });
  const b = await booking('B1');
  assert.equal((await noteCancelledHold(getDb(), 'B1', b)).action, 'noted');
  assert.equal((await noteCancelledHold(getDb(), 'B1', b)).action, 'again');
  const line = (await getDb().collection('audit_events').doc('hold_cancelled_B1').get()).data();
  assert.equal(line.targetId, 'B1');
  assert.equal(line.data.orderId, oid);
  assert.equal(line.data.paise, 1000000);
  assert.equal((await ledger()).length, 0);
  assert.equal((await noteCancelledHold(getDb(), 'B2', await booking('B2'))).action, 'skipped', 'no hold, nothing to note');
  // finance can still refund the held order
  const r = await refundPayment(getDb(), async () => ({ id: 'rfc' }), 'fin1', { orderId: oid, amountPaise: 1000000 }, staff);
  assert.equal(r.refundedPaise, 1000000);
});

test('payment after delivery, or with the switch off, is not held', async () => {
  await pay('B2', 'pay_2');
  assert.equal((await ledger()).filter((l) => l.bookingId === 'B2').length, 2);
  assert.equal((await booking('B2')).paymentHold, undefined);

  await getDb().collection('config').doc('features').set({ flags: { payHold: false } });
  clearFlagCache();
  await pay('B1', 'pay_1');
  assert.equal((await ledger()).filter((l) => l.bookingId === 'B1').length, 2, 'switch off: the driver is credited at once, as before');
});

test('the webhook holds the same way and verify then webhook counts once', async () => {
  const { orderId } = await createOrder(getDb(), fakeHttp, 'cust1', { bookingId: 'B1' });
  const body = JSON.stringify({ event: 'payment.captured', payload: { payment: { entity: { id: 'pay_w', order_id: orderId, amount: 1000000 } } } });
  const sig = crypto.createHmac('sha256', 'wh').update(body).digest('hex');
  const r = await handleWebhook(getDb(), { rawBody: Buffer.from(body), signature: sig, eventId: 'evh1', secret: 'wh' });
  assert.equal(r.body, 'paid');
  assert.ok((await booking('B1')).paymentHold);
  await verifyPayment(getDb(), SECRET, 'cust1', { orderId, paymentId: 'pay_w', signature: expectedSignature(orderId, 'pay_w', SECRET) });
  assert.equal((await ledger()).length, 0);
});
