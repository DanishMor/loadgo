'use strict';
// F25 and F26: push messages. Every message goes through sendPush, which
//   * honours the person's notification switches (users.notificationPrefs) - a
//     safety alert cannot be switched off,
//   * keeps quiet hours (22:00 to 07:00 India time) for offers, ratings and reminders,
//   * limits how many a person gets in an hour (the in-app list still gets everything),
//   * sends a short fixed text in the person's language and only ids as data
//     (never a phone number, a name or the text of a chat message),
//   * removes tokens that Firebase says are dead.
// The Firebase Messaging object is an argument, so tests use a recording fake.

const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { safeId, text } = require('./common');
const { titleFor, bodyFor } = require('./pushText');
const geo = require('./geo');

// type -> prefs key, channel, urgent (cannot be switched off, ignores quiet hours and the hourly limit)
const TYPES = Object.freeze({
  load_accepted: { cat: 'bookingUpdates', ch: 'bookings' },
  status_changed: { cat: 'bookingUpdates', ch: 'bookings' },
  trip_status: { cat: 'bookingUpdates', ch: 'bookings' },
  booking_cancelled: { cat: 'bookingUpdates', ch: 'bookings' },
  bid_accepted: { cat: 'bookingUpdates', ch: 'offers' },
  bid_received: { cat: 'bookingUpdates', ch: 'offers' },
  new_load: { cat: 'bookingUpdates', ch: 'offers' },
  chat_message: { cat: 'bookingUpdates', ch: 'chat' },
  inspection_request: { cat: 'bookingUpdates', ch: 'bookings' },
  inspection_approved: { cat: 'bookingUpdates', ch: 'bookings' },
  inspection_denied: { cat: 'bookingUpdates', ch: 'bookings' },
  rating_received: { cat: 'ratings', ch: 'bookings' },
  payment_marked: { cat: 'payments', ch: 'payments' },
  payment_confirmed: { cat: 'payments', ch: 'payments' },
  payout_status: { cat: 'payments', ch: 'payments' },
  doc_expiry: { cat: 'reminders', ch: 'bookings' },
  announcement: { cat: 'promotions', ch: 'admin' },
  accident_reported: { cat: 'bookingUpdates', ch: 'bookings', urgent: true },
  breakdown_reported: { cat: 'bookingUpdates', ch: 'bookings', urgent: true },
  sos: { cat: 'bookingUpdates', ch: 'admin', urgent: true },
});

const QUIET_CATEGORIES = ['promotions', 'ratings', 'reminders'];
const HOURLY_LIMIT = 20;
const IST_MS = 5.5 * 3600 * 1000;
const HOUR = 3600 * 1000;

function istHour(nowMs) {
  return new Date(nowMs + IST_MS).getUTCHours();
}

function inQuietHours(nowMs) {
  const h = istHour(nowMs);
  return h >= 22 || h < 7;
}

// prefs: users.notificationPrefs (missing keys mean on).
function decide({ prefs, type, nowMs, sentLastHour = 0 }) {
  const spec = TYPES[type];
  if (!spec) return { send: true, spec: { cat: 'bookingUpdates', ch: 'bookings' } };
  if (spec.urgent) return { send: true, spec };
  if (prefs && typeof prefs === 'object' && prefs[spec.cat] === false) return { send: false, reason: 'switched_off', spec };
  if (QUIET_CATEGORIES.includes(spec.cat) && inQuietHours(nowMs)) return { send: false, reason: 'quiet_hours', spec };
  if (sentLastHour >= HOURLY_LIMIT) return { send: false, reason: 'hourly_limit', spec };
  return { send: true, spec };
}

// Only these keys and only safe ids ever go into the data of a push.
function cleanData(type, data) {
  const out = { type: TYPES[type] || type === 'default' ? type : 'status_changed' };
  for (const k of ['bookingId', 'loadId']) {
    const v = data && safeId(data[k]);
    if (v) out[k] = v;
  }
  return out;
}

async function tokensOf(db, uid, userData) {
  const set = new Set();
  if (Array.isArray(userData.fcmTokens)) for (const t of userData.fcmTokens) if (typeof t === 'string' && t.length > 20 && t.length < 4096) set.add(t);
  const devs = await db.collection('users').doc(uid).collection('devices').get();
  for (const d of devs.docs) {
    const x = d.data();
    if (x.revoked !== true && typeof x.fcmToken === 'string' && x.fcmToken.length > 20) set.add(x.fcmToken);
  }
  return [...set];
}

async function bumpHourly(db, uid, nowMs) {
  const key = `${uid}_${Math.floor(nowMs / HOUR)}`;
  const ref = db.collection('push_log').doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists && Number.isSafeInteger(snap.data().count) ? snap.data().count : 0;
    tx.set(ref, { uid, count: count + 1, expireAt: Timestamp.fromMillis(nowMs + 3 * HOUR) });
    return count;
  });
}

async function readHourly(db, uid, nowMs) {
  const snap = await db.collection('push_log').doc(`${uid}_${Math.floor(nowMs / HOUR)}`).get();
  return snap.exists && Number.isSafeInteger(snap.data().count) ? snap.data().count : 0;
}

async function dropTokens(db, uid, dead) {
  if (dead.length === 0) return;
  await db.collection('users').doc(uid).set({ fcmTokens: FieldValue.arrayRemove(...dead) }, { merge: true });
  const devs = await db.collection('users').doc(uid).collection('devices').get();
  for (const d of devs.docs) if (dead.includes(d.data().fcmToken)) await d.ref.update({ fcmToken: FieldValue.delete() });
}

// Sends one push to one person. Returns { sent, reason? }.
async function sendPush(db, messaging, uid, type, data = {}, { nowMs = Date.now(), title, body } = {}) {
  if (!safeId(uid)) return { sent: 0, reason: 'bad_uid' };
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) return { sent: 0, reason: 'no_user' };
  const user = snap.data();
  const verdict = decide({ prefs: user.notificationPrefs, type, nowMs, sentLastHour: await readHourly(db, uid, nowMs) });
  if (!verdict.send) return { sent: 0, reason: verdict.reason };
  const tokens = await tokensOf(db, uid, user);
  if (tokens.length === 0) return { sent: 0, reason: 'no_token' };
  const language = typeof user.language === 'string' ? user.language : 'english';
  const message = {
    tokens,
    notification: { title: title ? text(title, 80) : titleFor(type, language), body: body ? text(body, 160) : bodyFor(language) },
    data: { ...cleanData(type, data), channel: verdict.spec.ch },
    android: { priority: 'high', notification: { channelId: verdict.spec.ch } },
  };
  const res = await messaging.sendEachForMulticast(message);
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') dead.push(tokens[i]);
  });
  await dropTokens(db, uid, dead);
  if (!TYPES[type] || !TYPES[type].urgent) await bumpHourly(db, uid, nowMs);
  return { sent: res.successCount, failed: res.failureCount, dead: dead.length };
}

// ---- events ----

// A new in-app notification document becomes a push.
async function onNotification(db, messaging, n, nowMs) {
  if (!n || !safeId(n.userId)) return { sent: 0, reason: 'skipped' };
  const type = typeof n.type === 'string' ? n.type : 'status_changed';
  return sendPush(db, messaging, n.userId, type, { bookingId: n.relatedId }, { nowMs });
}

// A new offer: tell the load's owner.
async function onOffer(db, messaging, offer, nowMs) {
  if (!offer || !safeId(offer.loadId)) return { sent: 0, reason: 'skipped' };
  const load = await db.collection('loads').doc(offer.loadId).get();
  const shipper = load.exists ? safeId(load.data().shipperId) : null;
  if (!shipper) return { sent: 0, reason: 'no_owner' };
  return sendPush(db, messaging, shipper, 'bid_received', { loadId: offer.loadId }, { nowMs });
}

// An offer turned "selected": tell the driver who made it.
async function onOfferSelected(db, messaging, before, after, nowMs) {
  if (!after || after.status !== 'selected' || (before && before.status === 'selected')) return { sent: 0, reason: 'skipped' };
  if (!safeId(after.driverId)) return { sent: 0, reason: 'skipped' };
  return sendPush(db, messaging, after.driverId, 'bid_accepted', { loadId: after.loadId }, { nowMs });
}

// A chat message: tell the other side (no text, no name).
async function onChatMessage(db, messaging, bookingId, message, nowMs) {
  const sender = message && safeId(message.senderId);
  if (!sender || !safeId(bookingId)) return { sent: 0, reason: 'skipped' };
  const b = await db.collection('bookings').doc(bookingId).get();
  if (!b.exists) return { sent: 0, reason: 'no_booking' };
  const d = b.data();
  const others = [d.customerId, d.driverId, d.assignedDriverId].map(safeId).filter((x) => x && x !== sender);
  const unique = [...new Set(others)];
  let sent = 0;
  for (const uid of unique) sent += (await sendPush(db, messaging, uid, 'chat_message', { bookingId }, { nowMs })).sent || 0;
  return { sent };
}

// SOS: every admin gets it at once.
async function onSos(db, messaging, nowMs) {
  const admins = await db.collection('admins').get();
  let sent = 0;
  for (const a of admins.docs) sent += (await sendPush(db, messaging, a.id, 'sos', {}, { nowMs })).sent || 0;
  return { sent, admins: admins.size };
}

// A payout changed state: tell the driver.
async function onPayoutChange(db, messaging, before, after, nowMs) {
  if (!after || !before || before.status === after.status || !safeId(after.driverId)) return { sent: 0, reason: 'skipped' };
  if (!['approved', 'paid', 'rejected', 'reversed'].includes(after.status)) return { sent: 0, reason: 'skipped' };
  return sendPush(db, messaging, after.driverId, 'payout_status', {}, { nowMs });
}

// An admin announcement (flag adminBroadcast): to a role or to everyone. Returns how many people were tried.
async function broadcast(db, messaging, { title, body, role }, nowMs) {
  const t = text(title, 80).trim();
  const b = text(body, 160).trim();
  if (t.length < 3 || b.length < 3) return { people: 0, sent: 0, reason: 'bad_text' };
  let q = db.collection('users');
  if (role === 'driver' || role === 'customer' || role === 'fleet') q = q.where('role', '==', role);
  const snap = await q.limit(5000).get();
  let sent = 0;
  for (const u of snap.docs) sent += (await sendPush(db, messaging, u.id, 'announcement', {}, { nowMs, title: t, body: b })).sent || 0;
  return { people: snap.size, sent };
}

// ---- wave dispatch (new open load -> drivers near the pickup) ----

const WAVES = Object.freeze([
  { km: 3, afterMs: 0 },
  { km: 7, afterMs: 3 * 60 * 1000 },
  { km: 15, afterMs: 6 * 60 * 1000 },
]);
const MAX_PER_WAVE = 50;
const FRESH_MS = 2 * HOUR;

function fresh(user, nowMs) {
  const t = user.lastLocation && user.lastLocation.updatedAt;
  return t instanceof Timestamp && nowMs - t.toMillis() <= FRESH_MS;
}

function mayDrive(user) {
  const tier = user.riskTier || 'normal';
  return (tier === 'normal' || tier === 'review') && user.docSuspended !== true;
}

async function driversNear(db, lat, lng, km, nowMs) {
  const precision = geo.precisionForKm(km);
  const found = new Map();
  for (const cell of geo.cells(lat, lng, precision)) {
    const snap = await db
      .collection('users')
      .where('role', '==', 'driver')
      .where('lastLocation.geohash', '>=', cell)
      .where('lastLocation.geohash', '<', `${cell}`)
      .limit(300)
      .get();
    for (const d of snap.docs) {
      const u = d.data();
      const loc = u.lastLocation;
      if (!loc || !(u.consents && u.consents.location === true) || !fresh(u, nowMs) || !mayDrive(u)) continue;
      if (![loc.lat, loc.lng].every(Number.isFinite)) continue;
      const dist = geo.haversineKm(lat, lng, loc.lat, loc.lng);
      if (dist <= km) found.set(d.id, dist);
    }
  }
  return [...found.entries()].sort((a, b) => a[1] - b[1]).map(([uid]) => uid);
}

// One step for one load: sends the next wave if it is due. State: dispatch/{loadId}.
async function dispatchLoad(db, messaging, loadId, nowMs = Date.now()) {
  const loadRef = db.collection('loads').doc(loadId);
  const load = await loadRef.get();
  if (!load.exists) return { action: 'skipped' };
  const l = load.data();
  // The pickup place is stored as a geohash of its city (7 characters); its centre is the place.
  let lat = null;
  let lng = null;
  if (typeof l.pickupGeohash === 'string' && /^[0-9b-hjkmnp-z]{4,12}$/.test(l.pickupGeohash)) {
    ({ lat, lng } = geo.decode(l.pickupGeohash));
  }
  if (l.status !== 'open' || lat === null || lng === null) return { action: 'skipped' };

  const stateRef = db.collection('dispatch').doc(loadId);
  const state = (await stateRef.get()).data() || { wave: 0, startedAt: Timestamp.fromMillis(nowMs), notified: [] };
  const startedMs = state.startedAt instanceof Timestamp ? state.startedAt.toMillis() : nowMs;
  const next = WAVES[state.wave];
  if (!next) return { action: 'done' };
  if (nowMs - startedMs < next.afterMs) return { action: 'waiting', wave: state.wave };

  const skip = new Set(state.notified || []);
  const owner = safeId(l.shipperId);
  const candidates = (await driversNear(db, lat, lng, next.km, nowMs)).filter((uid) => !skip.has(uid) && uid !== owner).slice(0, MAX_PER_WAVE);
  let sent = 0;
  for (const uid of candidates) {
    const r = await sendPush(db, messaging, uid, 'new_load', { loadId }, { nowMs });
    if (r.sent) sent++;
    skip.add(uid);
  }
  await stateRef.set({ wave: state.wave + 1, startedAt: Timestamp.fromMillis(startedMs), lastAt: Timestamp.fromMillis(nowMs), notified: [...skip].slice(0, 500) });
  return { action: 'wave', wave: state.wave + 1, km: next.km, tried: candidates.length, sent };
}

// Runs every few minutes: loads opened in the last 30 minutes that still have waves left.
async function dispatchRecent(db, messaging, nowMs = Date.now()) {
  const since = Timestamp.fromMillis(nowMs - 30 * 60 * 1000);
  const snap = await db.collection('loads').where('status', '==', 'open').where('createdAt', '>=', since).limit(200).get();
  const results = [];
  for (const d of snap.docs) results.push({ id: d.id, ...(await dispatchLoad(db, messaging, d.id, nowMs)) });
  return results;
}

// Daily: drivers whose licence or a vehicle paper expires in 7 days or tomorrow get one reminder per day.
async function docExpiryReminders(db, messaging, nowMs = Date.now()) {
  const day = new Date(nowMs + IST_MS).toISOString().slice(0, 10);
  const from = Timestamp.fromMillis(nowMs);
  const to = Timestamp.fromMillis(nowMs + 7 * 24 * HOUR);
  const snap = await db.collection('users').where('driverKyc.dlExpiry', '>=', from).where('driverKyc.dlExpiry', '<=', to).limit(2000).get();
  let sent = 0;
  for (const d of snap.docs) {
    if (d.data().docExpiryPushDay === day) continue;
    const r = await sendPush(db, messaging, d.id, 'doc_expiry', {}, { nowMs });
    if (r.sent) {
      sent++;
      await d.ref.update({ docExpiryPushDay: day });
    }
  }
  return { checked: snap.size, sent };
}

module.exports = {
  TYPES,
  HOURLY_LIMIT,
  WAVES,
  istHour,
  inQuietHours,
  decide,
  cleanData,
  sendPush,
  onNotification,
  onOffer,
  onOfferSelected,
  onChatMessage,
  onSos,
  onPayoutChange,
  broadcast,
  dispatchLoad,
  dispatchRecent,
  docExpiryReminders,
  driversNear,
};
