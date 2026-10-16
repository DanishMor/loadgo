'use strict';
// F19: trip counts for incentives and the public trust summary. The app shows a
// driver's own numbers computed on the phone; showing them to other people
// needs numbers the driver cannot change. This module counts delivered trips
// once each (trip_counts/{uid}, with a create-only marker per booking) and
// writes public_trust/{uid} with safe fields only: no phone, no name, no
// documents. Clients read both and write neither.

const { Timestamp, FieldValue, AggregateField } = require('firebase-admin/firestore');
const { safeId, paise } = require('./common');

function monthKey(ms) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

// Counts one delivered booking for one driver, once. Returns true when it was new.
async function countTrip(db, uid, bookingId, deliveredMs, nowMs = Date.now()) {
  if (!safeId(uid) || !safeId(bookingId)) return false;
  const counts = db.collection('trip_counts').doc(uid);
  const seen = counts.collection('seen').doc(bookingId);
  const month = monthKey(Number.isSafeInteger(deliveredMs) ? deliveredMs : nowMs);
  return db.runTransaction(async (tx) => {
    if ((await tx.get(seen)).exists) return false;
    tx.set(seen, { month, at: Timestamp.fromMillis(nowMs) });
    tx.set(
      counts,
      { total: FieldValue.increment(1), months: { [month]: FieldValue.increment(1) }, updatedAt: Timestamp.fromMillis(nowMs) },
      { merge: true },
    );
    return true;
  });
}

// Writes public_trust/{uid} from the real data: trips, rating, verified, since.
async function refreshSummary(db, uid, nowMs = Date.now()) {
  if (!safeId(uid)) return null;
  const [counts, user, rating] = await Promise.all([
    db.collection('trip_counts').doc(uid).get(),
    db.collection('users').doc(uid).get(),
    db
      .collection('ratings')
      .where('ratedId', '==', uid)
      .aggregate({ count: AggregateField.count(), avg: AggregateField.average('stars') })
      .get(),
  ]);
  const trips = counts.exists ? paise(counts.data().total) : 0;
  const r = rating.data();
  const u = user.exists ? user.data() : {};
  const created = u.createdAt instanceof Timestamp ? monthKey(u.createdAt.toMillis()) : null;
  const summary = {
    trips: Math.max(0, trips),
    ratingCount: r.count,
    rating: r.count > 0 && typeof r.avg === 'number' ? Math.round(r.avg * 10) / 10 : null,
    verified: u.verified === true,
    since: created,
    updatedAt: Timestamp.fromMillis(nowMs),
  };
  await db.collection('public_trust').doc(uid).set(summary);
  return summary;
}

// A booking became delivered: count it for the holder and for the assigned driver.
async function onDelivered(db, bookingId, booking, nowMs = Date.now()) {
  if (!booking || typeof booking !== 'object') return { action: 'skipped' };
  const t = booking.timeline && booking.timeline.delivered;
  const deliveredMs = t instanceof Timestamp ? t.toMillis() : nowMs;
  const people = [...new Set([safeId(booking.driverId), safeId(booking.assignedDriverId)].filter(Boolean))];
  const counted = [];
  for (const uid of people) {
    if (await countTrip(db, uid, bookingId, deliveredMs, nowMs)) counted.push(uid);
    await refreshSummary(db, uid, nowMs);
  }
  return { action: 'counted', counted, people };
}

module.exports = { monthKey, countTrip, refreshSummary, onDelivered };
