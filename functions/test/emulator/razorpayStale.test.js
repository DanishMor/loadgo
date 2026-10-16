'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { refundPayment } = require('../../src/razorpay');
const { requireStaff } = require('../../src/adminActions');

const staff = (d, u) => requireStaff(d, u, ['super', 'finance']);

test.beforeEach(async () => {
  await clearDb();
  await getDb().collection('admins').doc('fin1').set({ role: 'finance' });
});

const order = (extra) => ({ bookingId: 'B1', customerId: 'c1', amountPaise: 1000000, status: 'paid', paymentId: 'pay_1', ...extra });

test('a fresh reservation blocks more than the total; a reservation older than 5 minutes does not', async () => {
  const db = getDb();
  const http = async () => ({ id: 'rf' + Math.random().toString(36).slice(2, 8) });
  await db.collection('payment_orders').doc('o1').set(order({ refundPendingPaise: 800000, refundPendingAt: Timestamp.now() }));
  await assert.rejects(refundPayment(db, http, 'fin1', { orderId: 'o1', amountPaise: 500000 }, staff), (e) => e.code === 'failed-precondition');

  await db.collection('payment_orders').doc('o2').set(order({ refundPendingPaise: 800000, refundPendingAt: Timestamp.fromMillis(Date.now() - 6 * 60 * 1000) }));
  const r = await refundPayment(db, http, 'fin1', { orderId: 'o2', amountPaise: 500000 }, staff);
  assert.equal(r.refundedPaise, 500000);
});
