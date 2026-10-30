'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { reliabilityTier, reliabilityCounts, onTimeOf, RELIABILITY_MIN_TRIPS } = require('../../src/trust');

// E34: the reliability tier written to public_trust (the same formula as lib/core/trust/reliability.dart).
test('no tier below the minimum number of finished trips', () => {
  assert.equal(reliabilityTier({ delivered: RELIABILITY_MIN_TRIPS - 1, rating: 5, ratingCount: 50 }), null);
});

test('top, good and none from completion, on time and stars', () => {
  assert.equal(reliabilityTier({ delivered: 40, driverCancelled: 0, onTimeKnown: 30, onTimeOk: 29, rating: 4.8, ratingCount: 20 }), 'top');
  assert.equal(reliabilityTier({ delivered: 18, driverCancelled: 2, onTimeKnown: 10, onTimeOk: 8, rating: 4.5, ratingCount: 10 }), 'good');
  assert.equal(reliabilityTier({ delivered: 14, driverCancelled: 6, onTimeKnown: 10, onTimeOk: 5, rating: 3.5, ratingCount: 10 }), null);
});

test('few on-time or rating facts fall back calmly; junk counts as zero', () => {
  // completion stands in for on time, 0.9 for stars: 60 + 25 + 13.5 = 98.5 -> top
  assert.equal(reliabilityTier({ delivered: 12, onTimeKnown: 2, onTimeOk: 0, ratingCount: 1, rating: 1 }), 'top');
  assert.equal(reliabilityTier({ delivered: 'x', driverCancelled: -4 }), null);
  assert.equal(reliabilityTier({ delivered: 20, onTimeKnown: 10, onTimeOk: 99, rating: 9, ratingCount: 10 }), 'top', 'on time capped at known, stars at 5');
});

test('counts: delivered, driver cancellations, on-time pickups', () => {
  const ts = (ms) => Timestamp.fromMillis(ms);
  const sched = Date.UTC(2027, 4, 20, 10);
  const c = reliabilityCounts([
    { status: 'delivered', scheduledAt: ts(sched), timeline: { picked_up: ts(sched + 30 * 60000) } },
    { status: 'delivered', scheduledAt: ts(sched), timeline: { picked_up: ts(sched + 3 * 3600000) } },
    { status: 'delivered' },
    { status: 'cancelled', cancellation: { by: 'driver' } },
    { status: 'cancelled', cancellation: { by: 'customer' } },
  ]);
  assert.deepEqual(c, { delivered: 3, driverCancelled: 1, onTimeKnown: 2, onTimeOk: 1 });
  assert.equal(onTimeOf({ timeline: {} }), null);
});
