'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const geo = require('../../src/geo');
const { TYPES, HOURLY_LIMIT, WAVES, istHour, inQuietHours, decide, cleanData } = require('../../src/push');
const { LANGS, TITLES, BODY, titleFor, bodyFor } = require('../../src/pushText');

const at = (h, m = 0) => Date.UTC(2026, 9, 15, h, m) - 5.5 * 3600 * 1000; // h:m India time

test('geohash: the well known test point and the round trip', () => {
  assert.equal(geo.encode(57.64911, 10.40744, 11), 'u4pruydqqvj');
  const c = geo.decode('u4pruydqqvj');
  assert.ok(Math.abs(c.lat - 57.64911) < 0.0001 && Math.abs(c.lng - 10.40744) < 0.0001);
  const delhi = geo.encode(28.6139, 77.209, 7);
  const back = geo.decode(delhi);
  assert.ok(geo.haversineKm(28.6139, 77.209, back.lat, back.lng) < 0.2);
  assert.throws(() => geo.decode('abc!'));
  assert.throws(() => geo.encode(91, 0));
  assert.throws(() => geo.encode(NaN, 0));
});

test('cells: 9 neighbours around a point, no duplicates, the point is in one of them', () => {
  const cells = geo.cells(28.6139, 77.209, 5);
  assert.equal(cells.length, 9);
  assert.equal(new Set(cells).size, 9);
  assert.ok(cells.includes(geo.encode(28.6139, 77.209, 5)));
  assert.equal(geo.cells(89.99, 0, 5).length < 9, true, 'near the pole the missing row is skipped');
});

test('distance and the cell length for a radius follow the app', () => {
  assert.ok(Math.abs(geo.haversineKm(28.6139, 77.209, 19.076, 72.8777) - 1150) < 20);
  assert.equal(geo.haversineKm(1, 1, 1, 1), 0);
  assert.equal(geo.precisionForKm(3), 5);
  assert.equal(geo.precisionForKm(7), 4);
  assert.equal(geo.precisionForKm(15), 4);
  assert.equal(geo.precisionForKm(100), 3);
});

test('the waves are 3, 7 and 15 km, a few minutes apart', () => {
  assert.deepEqual(WAVES.map((w) => w.km), [3, 7, 15]);
  assert.equal(WAVES[0].afterMs, 0);
  assert.ok(WAVES[1].afterMs > 0 && WAVES[2].afterMs > WAVES[1].afterMs);
});

test('India time and quiet hours (22:00 to 07:00)', () => {
  assert.equal(istHour(at(0, 30)), 0);
  assert.equal(istHour(at(23, 59)), 23);
  for (const h of [22, 23, 0, 3, 6]) assert.equal(inQuietHours(at(h, 15)), true, String(h));
  for (const h of [7, 12, 21]) assert.equal(inQuietHours(at(h, 15)), false, String(h));
});

test('switches: a category that is off sends nothing; missing means on; safety cannot be switched off', () => {
  const noon = at(12);
  assert.equal(decide({ prefs: { payments: false }, type: 'payout_status', nowMs: noon }).send, false);
  assert.equal(decide({ prefs: { payments: false }, type: 'payout_status', nowMs: noon }).reason, 'switched_off');
  assert.equal(decide({ prefs: {}, type: 'payout_status', nowMs: noon }).send, true);
  assert.equal(decide({ prefs: null, type: 'chat_message', nowMs: noon }).send, true);
  assert.equal(decide({ prefs: { bookingUpdates: false, payments: false, ratings: false, promotions: false, reminders: false }, type: 'accident_reported', nowMs: noon }).send, true);
  assert.equal(decide({ prefs: { bookingUpdates: false }, type: 'sos', nowMs: noon }).send, true);
  assert.equal(decide({ prefs: { bookingUpdates: false }, type: 'trip_status', nowMs: noon }).send, false);
});

test('quiet hours hold back offers, ratings and reminders only; trips and safety always come', () => {
  const night = at(23);
  assert.equal(decide({ prefs: {}, type: 'announcement', nowMs: night }).reason, 'quiet_hours');
  assert.equal(decide({ prefs: {}, type: 'rating_received', nowMs: night }).reason, 'quiet_hours');
  assert.equal(decide({ prefs: {}, type: 'doc_expiry', nowMs: night }).reason, 'quiet_hours');
  for (const type of ['trip_status', 'chat_message', 'payout_status', 'new_load', 'bid_accepted', 'sos', 'accident_reported']) {
    assert.equal(decide({ prefs: {}, type, nowMs: night }).send, true, type);
  }
});

test('the hourly limit stops ordinary messages, not safety ones', () => {
  const noon = at(12);
  assert.equal(decide({ prefs: {}, type: 'chat_message', nowMs: noon, sentLastHour: HOURLY_LIMIT - 1 }).send, true);
  assert.equal(decide({ prefs: {}, type: 'chat_message', nowMs: noon, sentLastHour: HOURLY_LIMIT }).reason, 'hourly_limit');
  assert.equal(decide({ prefs: {}, type: 'sos', nowMs: noon, sentLastHour: 999 }).send, true);
});

test('an unknown type is sent as an ordinary booking update', () => {
  const v = decide({ prefs: { bookingUpdates: true }, type: 'brand_new', nowMs: at(12) });
  assert.equal(v.send, true);
  assert.equal(v.spec.ch, 'bookings');
});

test('the data of a push holds only the type and safe ids: no phone, no name, no text', () => {
  const d = cleanData('chat_message', { bookingId: 'B1', loadId: 'L1', phone: '9876543210', text: 'call me', name: 'Asha', senderPhone: '98' });
  assert.deepEqual(d, { type: 'chat_message', bookingId: 'B1', loadId: 'L1' });
  assert.deepEqual(cleanData('chat_message', { bookingId: '../x', loadId: 5 }), { type: 'chat_message' });
  assert.deepEqual(cleanData('made_up', { bookingId: 'B1' }), { type: 'status_changed', bookingId: 'B1' });
  assert.deepEqual(cleanData('chat_message', null), { type: 'chat_message' });
});

test('every type has a title in all 12 languages; no title or body has a digit run that looks like a number', () => {
  assert.equal(LANGS.length, 12);
  assert.equal(BODY.length, 12);
  for (const [type, row] of Object.entries(TITLES)) {
    assert.equal(row.length, 12, type);
    for (const t of row) {
      assert.ok(t.trim().length > 0);
      assert.equal(/\d{5,}/.test(t), false, `${type}: ${t}`);
    }
  }
  for (const type of Object.keys(TYPES)) {
    if (!['accident_reported', 'breakdown_reported', 'inspection_approved', 'inspection_denied', 'announcement'].includes(type)) {
      assert.ok(TITLES[type], `no title for ${type}`);
    }
  }
});

test('titles follow the language and fall back to English', () => {
  assert.equal(titleFor('chat_message', 'english'), 'New message');
  assert.equal(titleFor('chat_message', 'hindi'), 'नया संदेश');
  assert.equal(titleFor('chat_message', 'klingon'), 'New message');
  assert.equal(titleFor('no_such_type', 'english'), 'Load 20');
  assert.equal(bodyFor('urdu').length > 5, true);
  assert.equal(bodyFor(undefined), BODY[0]);
});
