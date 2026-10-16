'use strict';
// G20: what trips on a route really cost. When a booking is delivered, its final amount is added to
// route_rates/{from}_{to}_{vehicleType}: the last 30 amounts (paise) and a running count. Only the Admin SDK writes
// it; a signed-in person reads ONE document by its id (no list). No booking id, name or phone is stored, and a
// number is only shown to people once at least 5 trips exist (the app decides that).
// The place names come from the same offline city table as the app (cities.js).

const { safeId } = require('./common');
const { findCity } = require('./cities');

const KEEP = 30;
const MAX_PAISE = 1000000000; // ten million rupees: anything above is a typo, not a freight rate

function slug(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '').slice(0, 24);
}

function billAmount(b) {
  for (const v of [b.paidAmountPaise, b.agreedFarePaise, b.fareEstimate]) {
    if (Number.isSafeInteger(v) && v > 0 && v <= MAX_PAISE) return v;
  }
  return 0;
}

// The document id for a route and truck type, or null when a place is not in the city table.
function routeKey(pickup, drop, vehicleType) {
  const a = findCity(String(pickup || ''));
  const b = findCity(String(drop || ''));
  const v = slug(vehicleType || '');
  if (!a || !b || !v || a.name === b.name) return null;
  return `${slug(a.name)}_${slug(b.name)}_${v}`;
}

async function recordTrip(db, bookingId, booking, nowMs = Date.now()) {
  if (!safeId(bookingId) || !booking || booking.status !== 'delivered') return { action: 'skipped' };
  const amount = billAmount(booking);
  const key = routeKey(booking.pickup, booking.drop, booking.vehicleType);
  if (!amount || !key) return { action: 'skipped' };
  const seen = db.collection('route_rates_seen').doc(bookingId);
  const ref = db.collection('route_rates').doc(key);
  return db.runTransaction(async (tx) => {
    const [s, r] = await Promise.all([tx.get(seen), tx.get(ref)]);
    if (s.exists) return { action: 'again' };
    const old = r.exists ? r.data() : {};
    const recent = (Array.isArray(old.recent) ? old.recent.filter((n) => Number.isSafeInteger(n) && n > 0) : []).concat([amount]).slice(-KEEP);
    tx.set(ref, { n: (Number.isSafeInteger(old.n) ? old.n : 0) + 1, recent, updatedAt: new Date(nowMs) });
    tx.set(seen, { at: new Date(nowMs), expireAt: new Date(nowMs + 90 * 86400000) });
    return { action: 'recorded', key };
  });
}

module.exports = { recordTrip, routeKey, billAmount, KEEP };
