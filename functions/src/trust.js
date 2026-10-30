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

// E34: the reliability tier customers see as a badge (never the numbers). Same formula as the app
// (lib/core/trust/reliability.dart) and docs/RELIABILITY.md:
//   finished = delivered + cancelled by the driver, over the driver's newest 100 finished trips;
//   completion = delivered / finished; onTime = on time / pickups with a known time (completion stands in
//   when fewer than 5 are known); stars = rating / 5 (0.9 stands in below 5 ratings);
//   score = 60 * completion + 25 * onTime + 15 * stars, rounded; 'top' at 92+, 'good' at 82+,
//   nothing below 10 finished trips.
const RELIABILITY_MIN_TRIPS = 10;
function reliabilityTier({ delivered = 0, driverCancelled = 0, onTimeKnown = 0, onTimeOk = 0, rating = null, ratingCount = 0 }) {
  const n = (x) => (Number.isFinite(x) && x >= 0 ? x : 0);
  const d = n(delivered), c = n(driverCancelled), known = n(onTimeKnown), ok = Math.min(n(onTimeOk), known);
  const finished = d + c;
  if (finished < RELIABILITY_MIN_TRIPS) return null;
  const completion = d / finished;
  const onTime = known >= 5 ? ok / known : completion;
  const stars = n(ratingCount) >= 5 && Number.isFinite(rating) ? Math.max(0, Math.min(5, rating)) / 5 : 0.9;
  const score = Math.round(60 * completion + 25 * onTime + 15 * stars);
  return score >= 92 ? 'top' : score >= 82 ? 'good' : null;
}

// On time: picked up within an hour of the scheduled time, else on the pickup day (as the app's TrustBadges).
function onTimeOf(b) {
  const tl = b.timeline || {};
  const at = tl.picked_up instanceof Timestamp ? tl.picked_up.toMillis() : null;
  if (at === null) return null;
  if (b.scheduledAt instanceof Timestamp) return at <= b.scheduledAt.toMillis() + 60 * 60 * 1000;
  if (b.pickupDate instanceof Timestamp) {
    const d = new Date(b.pickupDate.toMillis());
    const end = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
    return at < end;
  }
  return null;
}

function reliabilityCounts(bookings) {
  let delivered = 0, driverCancelled = 0, onTimeKnown = 0, onTimeOk = 0;
  for (const b of bookings) {
    if (b.status === 'delivered') {
      delivered++;
      const t = onTimeOf(b);
      if (t !== null) {
        onTimeKnown++;
        if (t) onTimeOk++;
      }
    } else if (b.status === 'cancelled' && b.cancellation && b.cancellation.by === 'driver') {
      driverCancelled++;
    }
  }
  return { delivered, driverCancelled, onTimeKnown, onTimeOk };
}

// Writes public_trust/{uid} from the real data: trips, rating, verified, since.
async function refreshSummary(db, uid, nowMs = Date.now()) {
  if (!safeId(uid)) return null;
  const [counts, user, rating, recent] = await Promise.all([
    db.collection('trip_counts').doc(uid).get(),
    db.collection('users').doc(uid).get(),
    db
      .collection('ratings')
      .where('ratedId', '==', uid)
      .aggregate({ count: AggregateField.count(), avg: AggregateField.average('stars') })
      .get(),
    // E34: the newest 100 finished trips of this driver for the reliability tier (bounded read).
    db.collection('bookings').where('driverId', '==', uid).where('status', 'in', ['delivered', 'cancelled']).orderBy('createdAt', 'desc').limit(100).get(),
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
    reliability: reliabilityTier({
      ...reliabilityCounts(recent.docs.map((d) => d.data())),
      rating: r.count > 0 && typeof r.avg === 'number' ? r.avg : null,
      ratingCount: r.count,
    }),
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

module.exports = { monthKey, countTrip, refreshSummary, onDelivered, reliabilityTier, reliabilityCounts, onTimeOf, RELIABILITY_MIN_TRIPS };
