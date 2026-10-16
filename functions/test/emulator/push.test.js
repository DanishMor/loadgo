'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const push = require('../../src/push');
const geo = require('../../src/geo');

const NOON = Date.UTC(2026, 9, 15, 6, 30, 0); // 12:00 India time
const NIGHT = Date.UTC(2026, 9, 15, 18, 0, 0); // 23:30 India time
const TOKEN = (n) => `token-${n}-`.padEnd(40, 'x');

function fakeMessaging({ dead = [] } = {}) {
  const sent = [];
  return {
    sent,
    sendEachForMulticast: async (message) => {
      sent.push(message);
      const responses = message.tokens.map((t) => (dead.includes(t) ? { success: false, error: { code: 'messaging/registration-token-not-registered' } } : { success: true }));
      return { responses, successCount: responses.filter((r) => r.success).length, failureCount: responses.filter((r) => !r.success).length };
    },
  };
}

test.beforeEach(clearDb);

async function user(db, uid, extra = {}) {
  await db.collection('users').doc(uid).set({ role: 'customer', language: 'english', fcmTokens: [TOKEN(uid)], ...extra });
}

test('a push has a short fixed text in the person language and only ids as data', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'c1', { language: 'hindi' });
  const r = await push.sendPush(db, m, 'c1', 'chat_message', { bookingId: 'B1', text: 'call me 9876543210', phone: '9876543210' }, { nowMs: NOON });
  assert.equal(r.sent, 1);
  const msg = m.sent[0];
  assert.deepEqual(msg.tokens, [TOKEN('c1')]);
  assert.equal(msg.notification.title, 'नया संदेश');
  assert.deepEqual(msg.data, { type: 'chat_message', bookingId: 'B1', channel: 'chat' });
  assert.equal(msg.android.notification.channelId, 'chat');
  assert.equal(JSON.stringify(msg).includes('9876543210'), false);
});

test('tokens come from the profile and from each device; revoked devices and short junk are left out', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'c1', { fcmTokens: [TOKEN('a'), 'short', 5] });
  await db.collection('users').doc('c1').collection('devices').doc('d1').set({ fcmToken: TOKEN('b') });
  await db.collection('users').doc('c1').collection('devices').doc('d2').set({ fcmToken: TOKEN('c'), revoked: true });
  await db.collection('users').doc('c1').collection('devices').doc('d3').set({ label: 'no token' });
  await push.sendPush(db, m, 'c1', 'trip_status', { bookingId: 'B1' }, { nowMs: NOON });
  assert.deepEqual(m.sent[0].tokens.sort(), [TOKEN('a'), TOKEN('b')]);
});

test('dead tokens are removed from the profile and from the device', async () => {
  const db = getDb();
  await user(db, 'c1', { fcmTokens: [TOKEN('a'), TOKEN('b')] });
  await db.collection('users').doc('c1').collection('devices').doc('d1').set({ fcmToken: TOKEN('b'), label: 'Phone' });
  const m = fakeMessaging({ dead: [TOKEN('b')] });
  const r = await push.sendPush(db, m, 'c1', 'trip_status', {}, { nowMs: NOON });
  assert.equal(r.dead, 1);
  assert.deepEqual((await db.collection('users').doc('c1').get()).data().fcmTokens, [TOKEN('a')]);
  const dev = (await db.collection('users').doc('c1').collection('devices').doc('d1').get()).data();
  assert.equal(dev.fcmToken, undefined);
  assert.equal(dev.label, 'Phone');
});

test('switches, quiet hours and the hourly limit are honoured; nothing is sent and nothing breaks', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'c1', { notificationPrefs: { payments: false } });
  assert.equal((await push.sendPush(db, m, 'c1', 'payout_status', {}, { nowMs: NOON })).reason, 'switched_off');
  assert.equal((await push.sendPush(db, m, 'c1', 'announcement', {}, { nowMs: NIGHT, title: 'Diwali offer', body: 'Free pickup' })).reason, 'quiet_hours');
  assert.equal((await push.sendPush(db, m, 'nobody', 'chat_message', {}, { nowMs: NOON })).reason, 'no_user');
  assert.equal((await push.sendPush(db, m, 'a/b', 'chat_message', {}, { nowMs: NOON })).reason, 'bad_uid');
  await db.collection('users').doc('notoken').set({ role: 'customer' });
  assert.equal((await push.sendPush(db, m, 'notoken', 'chat_message', {}, { nowMs: NOON })).reason, 'no_token');
  assert.equal(m.sent.length, 0);
  // the hourly limit
  for (let i = 0; i < push.HOURLY_LIMIT; i++) assert.equal((await push.sendPush(db, m, 'c1', 'chat_message', { bookingId: 'B1' }, { nowMs: NOON })).sent, 1, `message ${i}`);
  assert.equal((await push.sendPush(db, m, 'c1', 'chat_message', { bookingId: 'B1' }, { nowMs: NOON })).reason, 'hourly_limit');
  assert.equal((await push.sendPush(db, m, 'c1', 'sos', {}, { nowMs: NOON })).sent, 1, 'safety is not limited');
  assert.equal((await push.sendPush(db, m, 'c1', 'chat_message', { bookingId: 'B1' }, { nowMs: NOON + 3600 * 1000 })).sent, 1, 'a new hour starts again');
});

test('an admin announcement uses the admin text, trimmed, and only with a title and a body', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'd1', { role: 'driver' });
  await user(db, 'c1', { role: 'customer' });
  await user(db, 'd2', { role: 'driver', notificationPrefs: { promotions: false } });
  const r = await push.broadcast(db, m, { title: ' Diwali offer ', body: 'Free pickup this week', role: 'driver' }, NOON);
  assert.equal(r.people, 2);
  assert.equal(r.sent, 1);
  assert.equal(m.sent[0].notification.title, 'Diwali offer');
  assert.equal((await push.broadcast(db, m, { title: 'x', body: 'hello there' }, NOON)).reason, 'bad_text');
  assert.equal((await push.broadcast(db, m, { title: 'Hello', body: '' }, NOON)).reason, 'bad_text');
});

test('a new notification, a new offer, a selected offer and a chat message reach the right people', async () => {
  const db = getDb();
  const m = fakeMessaging();
  for (const u of ['cust', 'drv', 'other']) await user(db, u);
  await db.collection('loads').doc('L1').set({ shipperId: 'cust', status: 'open' });
  await db.collection('bookings').doc('B1').set({ customerId: 'cust', driverId: 'drv' });

  await push.onNotification(db, m, { userId: 'cust', type: 'load_accepted', relatedId: 'B1' }, NOON);
  assert.equal(m.sent.at(-1).data.type, 'load_accepted');
  assert.equal(m.sent.at(-1).data.bookingId, 'B1');

  await push.onOffer(db, m, { loadId: 'L1', driverId: 'drv' }, NOON);
  assert.deepEqual(m.sent.at(-1).tokens, [TOKEN('cust')]);
  assert.equal(m.sent.at(-1).data.type, 'bid_received');

  await push.onOfferSelected(db, m, { status: 'pending' }, { status: 'selected', driverId: 'drv', loadId: 'L1' }, NOON);
  assert.deepEqual(m.sent.at(-1).tokens, [TOKEN('drv')]);
  assert.equal(m.sent.at(-1).data.type, 'bid_accepted');
  const before = m.sent.length;
  await push.onOfferSelected(db, m, { status: 'selected' }, { status: 'selected', driverId: 'drv', loadId: 'L1' }, NOON);
  assert.equal(m.sent.length, before, 'no second push for the same state');

  await push.onChatMessage(db, m, 'B1', { senderId: 'drv', text: 'secret 9876543210' }, NOON);
  assert.deepEqual(m.sent.at(-1).tokens, [TOKEN('cust')]);
  assert.equal(JSON.stringify(m.sent.at(-1)).includes('secret'), false);
  assert.equal((await push.onChatMessage(db, m, 'nope', { senderId: 'drv' }, NOON)).reason, 'no_booking');

  assert.equal((await push.onNotification(db, m, null, NOON)).reason, 'skipped');
  assert.equal((await push.onOffer(db, m, { loadId: 'ghost' }, NOON)).reason, 'no_owner');
});

test('SOS goes to every admin; a payout change goes to the driver once per change', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'a1');
  await user(db, 'a2');
  await user(db, 'drv', { role: 'driver' });
  await db.collection('admins').doc('a1').set({ role: 'super' });
  await db.collection('admins').doc('a2').set({ role: 'support' });
  const r = await push.onSos(db, m, NIGHT);
  assert.equal(r.sent, 2);
  assert.equal(r.admins, 2);

  await push.onPayoutChange(db, m, { status: 'requested', driverId: 'drv' }, { status: 'approved', driverId: 'drv' }, NOON);
  assert.equal(m.sent.at(-1).data.type, 'payout_status');
  const n = m.sent.length;
  await push.onPayoutChange(db, m, { status: 'approved', driverId: 'drv' }, { status: 'approved', driverId: 'drv' }, NOON);
  await push.onPayoutChange(db, m, { status: 'requested', driverId: 'drv' }, { status: 'requested', driverId: 'drv' }, NOON);
  assert.equal(m.sent.length, n);
});

// ---- waves ----

const DELHI = { lat: 28.6139, lng: 77.209 };
const near = (km) => ({ lat: DELHI.lat + km / 111, lng: DELHI.lng });

async function driver(db, uid, where, extra = {}) {
  await user(db, uid, {
    role: 'driver',
    consents: { location: true },
    lastLocation: { lat: where.lat, lng: where.lng, geohash: geo.encode(where.lat, where.lng, 9), updatedAt: Timestamp.fromMillis(NOON - 10 * 60 * 1000) },
    ...extra,
  });
}

async function openLoad(db, id, createdMs = NOON) {
  await db.collection('loads').doc(id).set({ status: 'open', shipperId: 'cust', pickupGeohash: geo.encode(DELHI.lat, DELHI.lng, 7), createdAt: Timestamp.fromMillis(createdMs) });
}

test('wave 1 reaches drivers within 3 km, wave 2 within 7 km after a few minutes, wave 3 within 15 km; nobody twice', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'cust');
  await driver(db, 'd1', near(1));
  await driver(db, 'd5', near(5));
  await driver(db, 'd12', near(12));
  await driver(db, 'd40', near(40));
  await openLoad(db, 'L1');

  let r = await push.dispatchLoad(db, m, 'L1', NOON);
  assert.equal(r.action, 'wave');
  assert.equal(r.km, 3);
  assert.equal(r.sent, 1);
  assert.deepEqual(m.sent.map((x) => x.tokens[0]), [TOKEN('d1')]);

  assert.equal((await push.dispatchLoad(db, m, 'L1', NOON + 60 * 1000)).action, 'waiting');
  r = await push.dispatchLoad(db, m, 'L1', NOON + 3 * 60 * 1000);
  assert.equal(r.km, 7);
  assert.deepEqual(m.sent.slice(1).map((x) => x.tokens[0]), [TOKEN('d5')]);

  r = await push.dispatchLoad(db, m, 'L1', NOON + 6 * 60 * 1000);
  assert.equal(r.km, 15);
  assert.deepEqual(m.sent.slice(2).map((x) => x.tokens[0]), [TOKEN('d12')]);

  assert.equal((await push.dispatchLoad(db, m, 'L1', NOON + 9 * 60 * 1000)).action, 'done');
  assert.equal(m.sent.length, 3);
  assert.equal(JSON.stringify(m.sent).includes(TOKEN('d40')), false);
});

test('only drivers who agreed to share their place, with a fresh position and a clean account, get a wave', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'cust');
  await driver(db, 'ok', near(1));
  await driver(db, 'noConsent', near(1), { consents: { location: false } });
  await driver(db, 'stale', near(1), { lastLocation: { lat: near(1).lat, lng: near(1).lng, geohash: geo.encode(near(1).lat, near(1).lng, 9), updatedAt: Timestamp.fromMillis(NOON - 5 * 3600 * 1000) } });
  await driver(db, 'banned', near(1), { riskTier: 'banned' });
  await driver(db, 'docs', near(1), { docSuspended: true });
  await driver(db, 'switchedOff', near(1), { notificationPrefs: { bookingUpdates: false } });
  await openLoad(db, 'L1');
  await push.dispatchLoad(db, m, 'L1', NOON);
  assert.deepEqual(m.sent.map((x) => x.tokens[0]), [TOKEN('ok')]);
});

test('closed, missing or place-less loads are skipped; the recent run handles only fresh open loads', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await user(db, 'cust');
  await driver(db, 'd1', near(1));
  await db.collection('loads').doc('closed').set({ status: 'closed', pickupGeohash: geo.encode(DELHI.lat, DELHI.lng, 7), createdAt: Timestamp.fromMillis(NOON) });
  await db.collection('loads').doc('noplace').set({ status: 'open', createdAt: Timestamp.fromMillis(NOON) });
  await openLoad(db, 'fresh', NOON - 5 * 60 * 1000);
  await openLoad(db, 'old', NOON - 5 * 3600 * 1000);
  assert.equal((await push.dispatchLoad(db, m, 'closed', NOON)).action, 'skipped');
  assert.equal((await push.dispatchLoad(db, m, 'noplace', NOON)).action, 'skipped');
  assert.equal((await push.dispatchLoad(db, m, 'ghost', NOON)).action, 'skipped');
  const runs = await push.dispatchRecent(db, m, NOON);
  assert.deepEqual(runs.filter((x) => x.action !== 'skipped').map((x) => x.id), ['fresh']);
  assert.equal(m.sent.length, 1);
});

test('a driver is never told about their own load', async () => {
  const db = getDb();
  const m = fakeMessaging();
  await driver(db, 'cust', near(1));
  await openLoad(db, 'L1');
  await push.dispatchLoad(db, m, 'L1', NOON);
  assert.equal(m.sent.length, 0);
});

test('document reminders: one per driver per day, only for papers that end within 7 days', async () => {
  const db = getDb();
  const m = fakeMessaging();
  const day = 24 * 3600 * 1000;
  await user(db, 'soon', { role: 'driver', driverKyc: { dlExpiry: Timestamp.fromMillis(NOON + 3 * day) } });
  await user(db, 'later', { role: 'driver', driverKyc: { dlExpiry: Timestamp.fromMillis(NOON + 40 * day) } });
  await user(db, 'past', { role: 'driver', driverKyc: { dlExpiry: Timestamp.fromMillis(NOON - 3 * day) } });
  const a = await push.docExpiryReminders(db, m, NOON);
  assert.equal(a.sent, 1);
  assert.equal(m.sent[0].data.type, 'doc_expiry');
  const b = await push.docExpiryReminders(db, m, NOON + 3600 * 1000);
  assert.equal(b.sent, 0);
});
