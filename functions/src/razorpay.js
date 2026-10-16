'use strict';
// F34: Razorpay on the server (sandbox first). The key id and key secret are
// Firebase secrets (RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET); they are never in this
// repository and the app never sees the secret. The signature check is plain
// HMAC-SHA256 and is tested here without any network. Calls to Razorpay go through
// an injected `http(method, path, body)` function so tests use a fake.

const crypto = require('node:crypto');
const { safeId } = require('./common');

const MAX_PAISE = 100 * 1000 * 1000 * 100; // 1 crore rupees, the same cap as the app

class PaymentError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // 'invalid-argument' | 'permission-denied' | 'unauthenticated' | 'not-found' | 'failed-precondition' | 'unavailable'
  }
}

function validPaise(n) {
  return Number.isSafeInteger(n) && n > 0 && n <= MAX_PAISE;
}

// Razorpay's rule: hex(HMAC_SHA256(order_id + "|" + payment_id, key_secret)).
function expectedSignature(orderId, paymentId, secret) {
  return crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');
}

function verifySignature(orderId, paymentId, signature, secret) {
  if (typeof orderId !== 'string' || typeof paymentId !== 'string' || typeof signature !== 'string' || !secret) return false;
  const a = Buffer.from(expectedSignature(orderId, paymentId, secret), 'utf8');
  const b = Buffer.from(signature, 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// The real HTTP call (Node 22 has fetch). Basic auth with the key pair.
function razorpayHttp(keyId, keySecret, fetchImpl = fetch) {
  const auth = 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64');
  return async (method, path, body) => {
    let res;
    try {
      res = await fetchImpl(`https://api.razorpay.com/v1${path}`, {
        method,
        headers: { Authorization: auth, 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined,
      });
    } catch {
      throw new PaymentError('unavailable', 'gateway not reachable');
    }
    if (res.status >= 500) throw new PaymentError('unavailable', 'gateway error');
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new PaymentError('failed-precondition', (json && json.error && json.error.description) || 'refused');
    return json;
  };
}

// A customer pays for a booking. The amount is the booking's own amount, never what the phone says.
async function createOrder(db, http, callerUid, input) {
  if (!safeId(callerUid)) throw new PaymentError('unauthenticated', 'sign in first');
  const bookingId = safeId(input && input.bookingId);
  if (!bookingId) throw new PaymentError('invalid-argument', 'bookingId');
  const snap = await db.collection('bookings').doc(bookingId).get();
  if (!snap.exists) throw new PaymentError('not-found', 'booking');
  const b = snap.data();
  if (b.customerId !== callerUid) throw new PaymentError('permission-denied', 'not your booking');
  const amount = [b.agreedFarePaise, b.fareEstimate].find(validPaise);
  if (!amount) throw new PaymentError('failed-precondition', 'no amount to pay');
  const order = await http('POST', '/orders', { amount, currency: 'INR', receipt: bookingId.slice(0, 40) });
  if (!order || typeof order.id !== 'string' || order.amount !== amount) throw new PaymentError('unavailable', 'odd answer');
  await db.collection('payment_orders').doc(order.id).set({ bookingId, customerId: callerUid, amountPaise: amount, status: 'created', createdAt: new Date() });
  return { orderId: order.id, amountPaise: amount, reference: bookingId };
}

// The phone tells us the payment finished; only a good signature on an order we made counts.
async function verifyPayment(db, secret, callerUid, input) {
  if (!safeId(callerUid)) throw new PaymentError('unauthenticated', 'sign in first');
  const orderId = input && input.orderId;
  const paymentId = input && input.paymentId;
  const signature = input && input.signature;
  if (typeof orderId !== 'string' || typeof paymentId !== 'string' || !/^[A-Za-z0-9_]{1,64}$/.test(orderId) || !/^[A-Za-z0-9_]{1,64}$/.test(paymentId)) {
    throw new PaymentError('invalid-argument', 'ids');
  }
  const ref = db.collection('payment_orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) throw new PaymentError('not-found', 'order');
  const o = snap.data();
  if (o.customerId !== callerUid) throw new PaymentError('permission-denied', 'not your order');
  if (!verifySignature(orderId, paymentId, signature, secret)) throw new PaymentError('permission-denied', 'bad signature');
  if (o.status === 'paid' && o.paymentId === paymentId) return { ok: true, again: true };
  if (o.status === 'paid') throw new PaymentError('failed-precondition', 'already paid with another payment');
  await ref.update({ status: 'paid', paymentId, paidAt: new Date() });
  return { ok: true };
}

// A finance or super admin refunds up to what was paid, in total (never more).
async function refundPayment(db, http, callerUid, input, staffCheck) {
  await staffCheck(db, callerUid);
  const orderId = input && input.orderId;
  if (typeof orderId !== 'string' || !/^[A-Za-z0-9_]{1,64}$/.test(orderId)) throw new PaymentError('invalid-argument', 'orderId');
  if (!validPaise(input.amountPaise)) throw new PaymentError('invalid-argument', 'amountPaise');
  const ref = db.collection('payment_orders').doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) throw new PaymentError('not-found', 'order');
  const o = snap.data();
  if (o.status !== 'paid' || typeof o.paymentId !== 'string') throw new PaymentError('failed-precondition', 'not paid');
  const already = Number.isSafeInteger(o.refundedPaise) ? o.refundedPaise : 0;
  if (already >= o.amountPaise) throw new PaymentError('failed-precondition', 'already refunded');
  if (already + input.amountPaise > o.amountPaise) throw new PaymentError('failed-precondition', 'more than was paid');
  await http('POST', `/payments/${o.paymentId}/refund`, { amount: input.amountPaise });
  await ref.update({ refundedPaise: already + input.amountPaise, refundedAt: new Date() });
  return { ok: true, refundedPaise: already + input.amountPaise };
}

module.exports = { refundPayment, PaymentError, MAX_PAISE, validPaise, expectedSignature, verifySignature, razorpayHttp, createOrder, verifyPayment };
