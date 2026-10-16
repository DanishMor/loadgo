'use strict';
// F34: Razorpay on the server (sandbox first). The key id and key secret are
// Firebase secrets (RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET); they are never in this
// repository and the app never sees the secret. The signature check is plain
// HMAC-SHA256 and is tested here without any network. Calls to Razorpay go through
// an injected `http(method, path, body)` function so tests use a fake.

const crypto = require('node:crypto');
const { FieldValue } = require('firebase-admin/firestore');
const { safeId, flagOn } = require('./common');
const { consume } = require('./quota');

const ID = /^[A-Za-z0-9_]{1,64}$/;

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
async function createOrder(db, http, callerUid, input, nowMs = Date.now(), keyId = undefined) {
  if (!safeId(callerUid)) throw new PaymentError('unauthenticated', 'sign in first');
  const bookingId = safeId(input && input.bookingId);
  if (!bookingId) throw new PaymentError('invalid-argument', 'bookingId');
  const snap = await db.collection('bookings').doc(bookingId).get();
  if (!snap.exists) throw new PaymentError('not-found', 'booking');
  const b = snap.data();
  if (b.customerId !== callerUid) throw new PaymentError('permission-denied', 'not your booking');
  const amount = [b.agreedFarePaise, b.fareEstimate].find(validPaise);
  if (!amount) throw new PaymentError('failed-precondition', 'no amount to pay');
  // Pressing "Pay" again must not pile up orders: an unpaid order of the same amount made in the last
  // 30 minutes is given back. (Equality filters only, so no composite index is needed.)
  const open = await db.collection('payment_orders').where('bookingId', '==', bookingId).where('status', '==', 'created').limit(5).get();
  for (const d of open.docs) {
    const o = d.data();
    const madeMs = o.createdAt && typeof o.createdAt.toMillis === 'function' ? o.createdAt.toMillis() : o.createdAt instanceof Date ? o.createdAt.getTime() : 0;
    if (o.customerId === callerUid && o.amountPaise === amount && nowMs - madeMs < 30 * 60 * 1000) return { orderId: d.id, amountPaise: amount, reference: bookingId, again: true, ...(keyId ? { keyId } : {}) };
  }
  // G17: a person can start only so many new orders a day, and everybody so many (config/paymentLimits). An open order
  // given back above does not use a turn.
  await consume(db, 'payorder', callerUid, { perUser: 30, total: 1000 }, (await db.collection('config').doc('paymentLimits').get()).data(), nowMs);
  const order = await http('POST', '/orders', { amount, currency: 'INR', receipt: bookingId.slice(0, 40) });
  if (!order || typeof order.id !== 'string' || order.amount !== amount) throw new PaymentError('unavailable', 'odd answer');
  await db.collection('payment_orders').doc(order.id).set({ bookingId, customerId: callerUid, amountPaise: amount, status: 'created', createdAt: new Date() });
  return { orderId: order.id, amountPaise: amount, reference: bookingId, ...(keyId ? { keyId } : {}) };
}

// ---- G9: money records ----
// Platform commission in paise: integer basis points, half rounded up, like Money.applyBp in the app.
function commissionPaise(amount, bps) {
  return Math.floor((amount * bps + 5000) / 10000);
}

function toMs(v) {
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return 0;
}

// The commission in basis points for this driver today: config/pricing, the lower Pro rate while the plan lasts
// (the same rule as PaymentService.commissionFor in the app).
async function commissionBpsFor(db, driverId, nowMs) {
  const cfg = ((await db.collection('config').doc('pricing').get()).data()) || {};
  const free = typeof cfg.commissionPercent === 'number' ? cfg.commissionPercent : 5;
  const pro = typeof cfg.proCommissionPercent === 'number' ? cfg.proCommissionPercent : 2;
  let pct = free;
  if (driverId) {
    const u = ((await db.collection('users').doc(driverId).get()).data()) || {};
    if (u.plan === 'pro' && (!u.planUntil || toMs(u.planUntil) > nowMs)) pct = pro;
  }
  return Math.max(0, Math.min(10000, Math.round(pct * 100)));
}

// One place marks an order paid: the phone's verify call and the webhook both come here, so a payment
// counted by one is never counted again by the other. In ONE transaction it
//   * marks the order paid (only when the amount matches the order),
//   * marks the booking paid (driver_confirmed, via 'razorpay'), unless it was already settled by hand,
//   * writes the driver's two ledger lines (trip earning, commission) with the ids the app uses, once.
// The wallet summary is recomputed by the server's own wallet job from those lines.
async function settleOrder(db, orderId, paymentId, paidPaise, nowMs = Date.now()) {
  const orderRef = db.collection('payment_orders').doc(orderId);
  const first = await orderRef.get();
  if (!first.exists) throw new PaymentError('not-found', 'order');
  const bookingSnap0 = await db.collection('bookings').doc(first.data().bookingId).get();
  const bps = await commissionBpsFor(db, bookingSnap0.exists ? bookingSnap0.data().driverId : null, nowMs);
  // G21: with the payHold switch on, money paid before delivery is held: the order is paid but the driver's ledger lines
  // are written when the trip is delivered (releaseHeld).
  const hold = await flagOn(db, 'payHold', nowMs);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) throw new PaymentError('not-found', 'order');
    const o = snap.data();
    if (o.status === 'paid') {
      if (o.paymentId === paymentId) return { ok: true, again: true };
      throw new PaymentError('failed-precondition', 'already paid with another payment');
    }
    if (paidPaise !== undefined && paidPaise !== o.amountPaise) {
      tx.update(orderRef, { status: 'mismatch', paymentId, mismatchPaise: paidPaise, updatedAt: new Date() });
      return { ok: false, mismatch: true };
    }
    const bRef = db.collection('bookings').doc(o.bookingId);
    const bSnap = await tx.get(bRef);
    const b = bSnap.exists ? bSnap.data() : null;
    const earnRef = db.collection('ledger').doc(`${o.bookingId}_trip_earning`);
    const commRef = db.collection('ledger').doc(`${o.bookingId}_platform_commission`);
    const earn = b && b.driverId ? await tx.get(earnRef) : null;
    const settleByServer = !!(b && b.driverId && b.paymentStatus !== 'driver_confirmed' && earn && !earn.exists);
    tx.update(orderRef, { status: 'paid', paymentId, paidAt: new Date() });
    const held = !!(settleByServer && hold && b.status !== 'delivered');
    if (held) {
      tx.update(bRef, { paymentHold: { orderId, paise: o.amountPaise }, onlinePaidPaise: o.amountPaise, paymentVia: 'razorpay', updatedAt: new Date() });
    } else if (settleByServer) {
      const commission = commissionPaise(o.amountPaise, bps);
      tx.update(bRef, { paymentStatus: 'driver_confirmed', paidAmountPaise: o.amountPaise, paymentVia: 'razorpay', paymentConfirmedAt: new Date(), updatedAt: new Date() });
      tx.set(earnRef, { driverId: b.driverId, bookingId: o.bookingId, type: 'trip_earning', amountPaise: o.amountPaise, createdAt: new Date() });
      tx.set(commRef, { driverId: b.driverId, bookingId: o.bookingId, type: 'platform_commission', amountPaise: -commission, createdAt: new Date() });
    } else if (b) {
      // Paid by hand already, or no driver yet: only the order is marked; nothing is counted twice.
      tx.update(bRef, { onlinePaidPaise: o.amountPaise, updatedAt: new Date() });
    }
    return { ok: true, ledger: settleByServer && !held, held };
  });
}

// G21: the trip was delivered. A held payment now becomes the driver's earning (minus what was refunded meanwhile) and
// the booking counts as paid. Safe to run twice: the hold is cleared in the same transaction, and a ledger line that
// already exists is never written again.
async function releaseHeld(db, bookingId, nowMs = Date.now()) {
  if (!safeId(bookingId)) return { action: 'skipped' };
  const bRef = db.collection('bookings').doc(bookingId);
  const first = await bRef.get();
  const hold0 = first.exists ? first.data().paymentHold : null;
  if (!hold0 || typeof hold0.orderId !== 'string' || first.data().status !== 'delivered') return { action: 'skipped' };
  const bps = await commissionBpsFor(db, first.data().driverId, nowMs);
  return db.runTransaction(async (tx) => {
    const bSnap = await tx.get(bRef);
    const b = bSnap.exists ? bSnap.data() : null;
    if (!b || !b.paymentHold || b.status !== 'delivered' || !b.driverId) return { action: 'skipped' };
    const oRef = db.collection('payment_orders').doc(b.paymentHold.orderId);
    const oSnap = await tx.get(oRef);
    const earnRef = db.collection('ledger').doc(`${bookingId}_trip_earning`);
    const commRef = db.collection('ledger').doc(`${bookingId}_platform_commission`);
    const earn = await tx.get(earnRef);
    const o = oSnap.exists ? oSnap.data() : null;
    const refunded = o && Number.isSafeInteger(o.refundedPaise) ? o.refundedPaise : 0;
    const net = o && o.status === 'paid' ? o.amountPaise - refunded : 0;
    if (net <= 0 || earn.exists) {
      tx.update(bRef, { paymentHold: FieldValue.delete(), updatedAt: new Date() });
      return { action: 'cleared' };
    }
    tx.update(bRef, { paymentHold: FieldValue.delete(), paymentStatus: 'driver_confirmed', paidAmountPaise: net, paymentVia: 'razorpay', paymentConfirmedAt: new Date(), updatedAt: new Date() });
    tx.set(earnRef, { driverId: b.driverId, bookingId, type: 'trip_earning', amountPaise: net, createdAt: new Date() });
    tx.set(commRef, { driverId: b.driverId, bookingId, type: 'platform_commission', amountPaise: -commissionPaise(net, bps), createdAt: new Date() });
    return { action: 'released', paise: net };
  });
}

// The phone tells us the payment finished; only a good signature on an order we made counts.
async function verifyPayment(db, secret, callerUid, input, nowMs = Date.now()) {
  if (!safeId(callerUid)) throw new PaymentError('unauthenticated', 'sign in first');
  const orderId = input && input.orderId;
  const paymentId = input && input.paymentId;
  const signature = input && input.signature;
  if (typeof orderId !== 'string' || typeof paymentId !== 'string' || !ID.test(orderId) || !ID.test(paymentId)) {
    throw new PaymentError('invalid-argument', 'ids');
  }
  const snap = await db.collection('payment_orders').doc(orderId).get();
  if (!snap.exists) throw new PaymentError('not-found', 'order');
  if (snap.data().customerId !== callerUid) throw new PaymentError('permission-denied', 'not your order');
  if (!verifySignature(orderId, paymentId, signature, secret)) throw new PaymentError('permission-denied', 'bad signature');
  const r = await settleOrder(db, orderId, paymentId, undefined, nowMs);
  return r.again ? { ok: true, again: true } : { ok: true };
}

// A refund takes back from the driver what the customer got back, and gives back the commission share.
// One adjustment line per refund, with an id made from the order and the running total, so a retry or a
// webhook for the same refund writes nothing twice.
function refundLine(o, driverId, refundPaise, totalAfter, commissionOnOrder) {
  if (!driverId) return null;
  const commShare = Math.floor((commissionOnOrder * refundPaise * 2 + o.amountPaise) / (2 * o.amountPaise));
  const net = -(refundPaise - commShare);
  if (net === 0) return null;
  return {
    id: `adj_rf_${o.orderId}_${totalAfter}`,
    data: { driverId, type: 'adjustment', amountPaise: net, reason: `Online refund ${refundPaise} paise on ${o.bookingId}`, by: 'system_razorpay', createdAt: new Date() },
  };
}

// Applies one refund (made by us or seen in the webhook) to the order and the books. Idempotent on refundKey.
async function applyRefund(db, orderId, refundPaise, refundKey) {
  const ref = db.collection('payment_orders').doc(orderId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new PaymentError('not-found', 'order');
    const o = { ...snap.data(), orderId };
    const keys = Array.isArray(o.refundKeys) ? o.refundKeys : [];
    if (refundKey && keys.includes(refundKey)) return { ok: true, again: true, refundedPaise: o.refundedPaise || 0 };
    const already = Number.isSafeInteger(o.refundedPaise) ? o.refundedPaise : 0;
    const add = Math.min(refundPaise, o.amountPaise - already);
    if (add <= 0) return { ok: true, refundedPaise: already };
    const total = already + add;
    const bSnap = await tx.get(db.collection('bookings').doc(o.bookingId));
    const b = bSnap.exists ? bSnap.data() : null;
    const hasDriver = !!(b && b.driverId);
    const commSnap = hasDriver ? await tx.get(db.collection('ledger').doc(`${o.bookingId}_platform_commission`)) : null;
    const earnSnap = hasDriver ? await tx.get(db.collection('ledger').doc(`${o.bookingId}_trip_earning`)) : null;
    const comm = commSnap && commSnap.exists ? Math.abs(commSnap.data().amountPaise || 0) : 0;
    tx.update(ref, { refundedPaise: total, refundedAt: new Date(), refundKeys: refundKey ? [...keys, refundKey].slice(-20) : keys });
    // Only a payment that was counted in the driver's ledger is taken back from it.
    const line = earnSnap && earnSnap.exists ? refundLine(o, b.driverId, add, total, comm) : null;
    if (line) tx.set(db.collection('ledger').doc(line.id), line.data);
    return { ok: true, refundedPaise: total };
  });
}

// A finance or super admin refunds up to what was paid, in total (never more). The amount is reserved first,
// so two refunds at the same moment cannot both pass the check; if the gateway refuses, the reservation is undone.
async function refundPayment(db, http, callerUid, input, staffCheck) {
  await staffCheck(db, callerUid);
  const orderId = input && input.orderId;
  if (typeof orderId !== 'string' || !ID.test(orderId)) throw new PaymentError('invalid-argument', 'orderId');
  if (!validPaise(input.amountPaise)) throw new PaymentError('invalid-argument', 'amountPaise');
  const ref = db.collection('payment_orders').doc(orderId);
  const release = () => db.runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const p = (s.data() || {}).refundPendingPaise || 0;
    tx.update(ref, { refundPendingPaise: Math.max(0, p - input.amountPaise) });
  });
  const paymentId = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new PaymentError('not-found', 'order');
    const o = snap.data();
    if (o.status !== 'paid' || typeof o.paymentId !== 'string') throw new PaymentError('failed-precondition', 'not paid');
    const already = Number.isSafeInteger(o.refundedPaise) ? o.refundedPaise : 0;
    // A reservation older than 5 minutes is a call that died half way (the gateway answered or not, we never learned):
    // it stops blocking, and finance checks the gateway's list before refunding again.
    const reservedAt = o.refundPendingAt && typeof o.refundPendingAt.toMillis === 'function' ? o.refundPendingAt.toMillis() : 0;
    const stale = reservedAt > 0 && Date.now() - reservedAt > 5 * 60 * 1000;
    const pending = !stale && Number.isSafeInteger(o.refundPendingPaise) ? o.refundPendingPaise : 0;
    if (already >= o.amountPaise) throw new PaymentError('failed-precondition', 'already refunded');
    if (already + pending + input.amountPaise > o.amountPaise) throw new PaymentError('failed-precondition', 'more than was paid');
    tx.update(ref, { refundPendingPaise: pending + input.amountPaise, refundPendingAt: new Date() });
    return o.paymentId;
  });
  let answer;
  try {
    answer = await http('POST', `/payments/${paymentId}/refund`, { amount: input.amountPaise });
  } catch (e) {
    await release();
    throw e;
  }
  const refundKey = answer && typeof answer.id === 'string' && ID.test(answer.id) ? answer.id : undefined;
  await release();
  return applyRefund(db, orderId, input.amountPaise, refundKey);
}

// ---- G9: webhook ----
// Razorpay signs the raw body: hex(HMAC_SHA256(body, webhook_secret)) in X-Razorpay-Signature. The webhook
// secret is its own Firebase secret (RAZORPAY_WEBHOOK_SECRET). Each event carries a unique id in
// X-Razorpay-Event-Id: it is claimed once in payment_events, so a replay or a retry does nothing.
function verifyWebhookSignature(rawBody, signature, secret) {
  if (!Buffer.isBuffer(rawBody) && typeof rawBody !== 'string') return false;
  if (typeof signature !== 'string' || !secret) return false;
  const want = Buffer.from(crypto.createHmac('sha256', secret).update(rawBody).digest('hex'), 'utf8');
  const got = Buffer.from(signature, 'utf8');
  return want.length === got.length && crypto.timingSafeEqual(want, got);
}

async function handleWebhook(db, { rawBody, signature, eventId, secret }, nowMs = Date.now()) {
  if (!verifyWebhookSignature(rawBody, signature, secret)) return { status: 400, body: 'bad signature' };
  if (typeof eventId !== 'string' || !/^[A-Za-z0-9_.-]{1,64}$/.test(eventId)) return { status: 400, body: 'no event id' };
  let event;
  try {
    event = JSON.parse(Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : rawBody);
  } catch {
    return { status: 400, body: 'bad body' };
  }
  const claim = db.collection('payment_events').doc(eventId.replace(/\./g, '_'));
  try {
    await claim.create({ type: String((event && event.event) || '').slice(0, 40), at: new Date(nowMs) });
  } catch (e) {
    if (e && (e.code === 6 || /already exists/i.test(e.message || ''))) return { status: 200, body: 'duplicate' };
    throw e;
  }
  try {
    const type = event && event.event;
    const pay = event && event.payload && event.payload.payment && event.payload.payment.entity;
    const rf = event && event.payload && event.payload.refund && event.payload.refund.entity;
    if ((type === 'payment.captured' || type === 'order.paid') && pay && ID.test(pay.order_id || '') && ID.test(pay.id || '')) {
      const r = await settleOrder(db, pay.order_id, pay.id, pay.amount, nowMs).catch((e) => {
        if (e instanceof PaymentError) return { ok: false, why: e.message };
        throw e;
      });
      return { status: 200, body: r.ok ? 'paid' : 'ignored' };
    }
    if (type === 'payment.failed' && pay && ID.test(pay.order_id || '')) {
      const o = db.collection('payment_orders').doc(pay.order_id);
      if ((await o.get()).exists) await o.update({ lastFailureAt: new Date(nowMs) });
      return { status: 200, body: 'noted' };
    }
    if (type === 'refund.processed' && rf && ID.test(rf.payment_id || '') && ID.test(rf.id || '') && Number.isSafeInteger(rf.amount) && rf.amount > 0) {
      const q = await db.collection('payment_orders').where('paymentId', '==', rf.payment_id).limit(1).get();
      if (q.empty) return { status: 200, body: 'unknown payment' };
      await applyRefund(db, q.docs[0].id, rf.amount, rf.id);
      return { status: 200, body: 'refund' };
    }
    return { status: 200, body: 'ignored' };
  } catch (e) {
    await claim.delete().catch(() => {}); // let Razorpay retry
    throw e;
  }
}

module.exports = {
  refundPayment, PaymentError, MAX_PAISE, validPaise, expectedSignature, verifySignature, razorpayHttp, createOrder, verifyPayment,
  settleOrder, releaseHeld, applyRefund, handleWebhook, verifyWebhookSignature, commissionPaise,
};
