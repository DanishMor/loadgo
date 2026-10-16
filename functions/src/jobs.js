'use strict';
// F20: scheduled jobs. Each job is a plain function with the Firestore handle
// and the time as arguments; the schedules are wired in index.js behind the
// serverJobs switch.
//
//  * expireOpenLoads  : an open load nobody took is closed after its pickup day
//                       passed, or after 30 days with no pickup date.
//  * holdScheduled    : an accepted booking with a pickup time gets its vehicle
//                       marked "on trip" one lead time before (the same step the
//                       driver's phone does when it starts the trip).
//  * suspendExpiredDocs: a free vehicle with an expired insurance, permit or
//                       fitness paper is held back (doc_expired) and lifted when the
//                       paper is renewed; a driver with an expired licence is marked
//                       docSuspended and lifted on renewal. An admin override
//                       (docOverrideUntil in the future) always wins.

const { Timestamp, FieldPath } = require('firebase-admin/firestore');
const { safeId } = require('./common');

const DAY = 24 * 3600 * 1000;
const PAGE = 400;

const AVAILABLE = 'available';
const ON_TRIP = 'on_trip';
const DOC_EXPIRED = 'doc_expired';
const BLOCKING_DOCS = ['insurance', 'permit', 'fitness'];

function startOfDayMs(ms) {
  // India has no daylight saving: a day is a day in IST.
  const IST = 5.5 * 3600 * 1000;
  return Math.floor((ms + IST) / DAY) * DAY - IST;
}

// Firestore wants the first sort to be the field of a range filter, so the caller names it.
async function eachPage(query, field, fn) {
  let last = null;
  for (;;) {
    let q = (field ? query.orderBy(field) : query).orderBy(FieldPath.documentId()).limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    for (const doc of snap.docs) await fn(doc);
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE) return;
  }
}

async function audit(db, targetId, data, nowMs) {
  await db.collection('audit_events').add({
    type: 'user_action',
    actorId: 'server',
    targetId,
    data,
    createdAt: Timestamp.fromMillis(nowMs),
  });
}

async function expireOpenLoads(db, nowMs = Date.now(), { maxAgeDays = 30 } = {}) {
  const expired = new Map();
  const dayStart = Timestamp.fromMillis(startOfDayMs(nowMs));
  await eachPage(db.collection('loads').where('status', '==', 'open').where('pickupDate', '<', dayStart), 'pickupDate', (d) => expired.set(d.id, d));
  await eachPage(db.collection('loads').where('status', '==', 'open').where('createdAt', '<', Timestamp.fromMillis(nowMs - maxAgeDays * DAY)), 'createdAt', (d) => {
    const data = d.data();
    if (data.pickupDate === undefined || data.pickupDate === null) expired.set(d.id, d); // a dated load is judged by its date
  });
  let closed = 0;
  for (const d of expired.values()) {
    const res = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(d.ref);
      if (!fresh.exists || fresh.data().status !== 'open') return false; // taken or cancelled meanwhile
      tx.update(d.ref, { status: 'closed', closedReason: 'expired', closedAt: Timestamp.fromMillis(nowMs) });
      return true;
    });
    if (res) closed++;
  }
  if (closed > 0) await audit(db, 'loads', { action: 'expire_loads', count: closed }, nowMs);
  return { closed };
}

async function holdScheduled(db, nowMs = Date.now(), { leadMinutes = 60 } = {}) {
  const until = Timestamp.fromMillis(nowMs + leadMinutes * 60 * 1000);
  let held = 0;
  await eachPage(db.collection('bookings').where('status', '==', 'accepted').where('scheduledAt', '<=', until), 'scheduledAt', async (b) => {
    const vehicleId = safeId(b.data().vehicleId);
    if (!vehicleId) return;
    const vref = db.collection('vehicles').doc(vehicleId);
    const done = await db.runTransaction(async (tx) => {
      const v = await tx.get(vref);
      if (!v.exists || v.data().availability !== AVAILABLE) return false;
      tx.update(vref, { availability: ON_TRIP, updatedAt: Timestamp.fromMillis(nowMs) });
      return true;
    });
    if (done) held++;
  });
  return { held };
}

function overrideActive(data, nowMs) {
  const t = data && data.docOverrideUntil;
  return t instanceof Timestamp && t.toMillis() > nowMs;
}

function expiredBlockingDocs(vehicle, nowMs) {
  const today = startOfDayMs(nowMs);
  const docs = vehicle && typeof vehicle.docs === 'object' && vehicle.docs ? vehicle.docs : {};
  return BLOCKING_DOCS.filter((k) => {
    const e = docs[k] && docs[k].expiry;
    return e instanceof Timestamp && e.toMillis() < today;
  });
}

async function suspendExpiredDocs(db, nowMs = Date.now()) {
  const result = { vehiclesHeld: 0, vehiclesLifted: 0, driversSuspended: 0, driversLifted: 0 };

  await eachPage(db.collection('vehicles').where('availability', 'in', [AVAILABLE, DOC_EXPIRED]), null, async (v) => {
    const data = v.data();
    const blocked = expiredBlockingDocs(data, nowMs).length > 0 && !overrideActive(data, nowMs);
    if (data.availability === AVAILABLE && blocked) {
      await v.ref.update({ availability: DOC_EXPIRED, updatedAt: Timestamp.fromMillis(nowMs) });
      result.vehiclesHeld++;
    } else if (data.availability === DOC_EXPIRED && !blocked) {
      await v.ref.update({ availability: AVAILABLE, updatedAt: Timestamp.fromMillis(nowMs) });
      result.vehiclesLifted++;
    }
  });

  const today = Timestamp.fromMillis(startOfDayMs(nowMs));
  await eachPage(db.collection('users').where('driverKyc.dlExpiry', '<', today), 'driverKyc.dlExpiry', async (u) => {
    const data = u.data();
    if (data.docSuspended === true || overrideActive(data, nowMs)) return;
    await u.ref.update({ docSuspended: true, docSuspendedAt: Timestamp.fromMillis(nowMs) });
    result.driversSuspended++;
  });
  await eachPage(db.collection('users').where('docSuspended', '==', true), null, async (u) => {
    const data = u.data();
    const exp = data.driverKyc && data.driverKyc.dlExpiry;
    const expired = exp instanceof Timestamp && exp.toMillis() < startOfDayMs(nowMs);
    if (expired && !overrideActive(data, nowMs)) return;
    await u.ref.update({ docSuspended: false, docSuspendedAt: null });
    result.driversLifted++;
  });

  const total = Object.values(result).reduce((a, b) => a + b, 0);
  if (total > 0) await audit(db, 'documents', { action: 'doc_suspend_job', ...result }, nowMs);
  return result;
}

module.exports = { expireOpenLoads, holdScheduled, suspendExpiredDocs, startOfDayMs, expiredBlockingDocs, overrideActive };
