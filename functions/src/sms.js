'use strict';
// G12: transactional SMS through MSG91 (India needs DLT-registered templates). Two uses:
//   * a short trip-status SMS to a customer who cannot get push (no phone token), from the same
//     notification that would have been the push;
//   * "I need help" SMS from the app to the person's OWN saved emergency contacts (never to any number).
// The login code is NOT sent here: Firebase Auth does that (docs/OTP_SECURITY.md).
// The auth key is a Firebase secret (MSG91_AUTH_KEY). Template ids live in config/sms (not secret).
// Limits: config/sms.perUserPerDay (default 10) and totalPerDay (default 500), see quota.js.
// The HTTP call is injected so tests use a fake. Request shape follows MSG91's Flow API; check the current
// MSG91 documentation before going live (UNVERIFIED here, no account was used).

const { safeId, text } = require('./common');
const { consume } = require('./quota');

class SmsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // 'invalid-argument' | 'unauthenticated' | 'permission-denied' | 'failed-precondition' | 'unavailable'
  }
}

const DEFAULTS = Object.freeze({ perUser: 10, total: 500 });
const TRIP_TYPES = Object.freeze({
  load_accepted: 'Your truck is booked',
  trip_status: 'Your trip has moved to the next step',
  booking_cancelled: 'Your booking was cancelled',
});

// +91 and ten digits starting 6 to 9, or null. India only for now.
function msisdn(e164) {
  if (typeof e164 !== 'string') return null;
  const m = /^\+91([6-9]\d{9})$/.exec(e164.replace(/\s/g, ''));
  return m ? `91${m[1]}` : null;
}

function msg91Http(authKey, fetchImpl = fetch) {
  return async ({ mobile, templateId, vars }) => {
    let res;
    try {
      res = await fetchImpl('https://control.msg91.com/api/v5/flow/', {
        method: 'POST',
        headers: { authkey: authKey, 'Content-Type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ template_id: templateId, short_url: '0', recipients: [{ mobiles: mobile, ...vars }] }),
      });
    } catch {
      throw new SmsError('unavailable', 'sms not reachable');
    }
    if (res.status >= 500 || res.status === 429) throw new SmsError('unavailable', 'sms busy');
    const json = await res.json().catch(() => ({}));
    if (!res.ok || (json && json.type === 'error')) throw new SmsError('failed-precondition', 'sms refused');
    const id = json && typeof json.message === 'string' ? json.message : 'sent';
    return { messageId: id.slice(0, 80) };
  };
}

async function config(db) {
  return ((await db.collection('config').doc('sms').get()).data()) || {};
}

// Sends one templated SMS, after the daily quota. Variables are plain short text (var1, var2).
async function sendTemplate(db, http, { uid, to, template, vars }, nowMs = Date.now()) {
  const mobile = msisdn(to);
  if (!mobile) throw new SmsError('invalid-argument', 'number');
  const cfg = await config(db);
  const templateId = cfg.templates && typeof cfg.templates[template] === 'string' ? cfg.templates[template] : '';
  if (!/^[A-Za-z0-9_-]{6,64}$/.test(templateId)) throw new SmsError('failed-precondition', 'template not set');
  await consume(db, 'sms', uid, DEFAULTS, cfg, nowMs);
  const clean = {};
  for (const k of Object.keys(vars || {})) {
    if (/^var[1-5]$/.test(k)) clean[k] = text(String(vars[k]), 160).replace(/[\r\n]+/g, ' ');
  }
  return http({ mobile, templateId, vars: clean });
}

// The app's own "help" SMS: only to a number the caller saved as an emergency contact.
async function emergencySms(db, http, callerUid, input, nowMs = Date.now()) {
  if (!safeId(callerUid)) throw new SmsError('unauthenticated', 'sign in first');
  const to = input && input.to;
  const body = input && typeof input.text === 'string' ? input.text.trim() : '';
  if (!msisdn(to) || body.length === 0 || body.length > 480) throw new SmsError('invalid-argument', 'input');
  const user = ((await db.collection('users').doc(callerUid).get()).data()) || {};
  const saved = (Array.isArray(user.emergencyContacts) ? user.emergencyContacts : []).map((c) => msisdn(c && c.phone)).filter(Boolean);
  if (!saved.includes(msisdn(to))) throw new SmsError('permission-denied', 'not one of your emergency contacts');
  return sendTemplate(db, http, { uid: callerUid, to, template: 'sos', vars: { var1: body.slice(0, 160) } }, nowMs);
}

async function hasPushToken(db, uid, user) {
  if (Array.isArray(user.fcmTokens) && user.fcmTokens.some((t) => typeof t === 'string' && t.length > 20)) return true;
  const devs = await db.collection('users').doc(uid).collection('devices').get();
  return devs.docs.some((d) => d.data().revoked !== true && typeof d.data().fcmToken === 'string' && d.data().fcmToken.length > 20);
}

// A new in-app notification: an SMS only for the few trip types, only when the person has no push token,
// only if they have not switched booking updates off, and only within the daily quota.
async function onNotificationSms(db, http, n, nowMs = Date.now()) {
  if (!n || !safeId(n.userId) || !TRIP_TYPES[n.type]) return { sent: false, reason: 'skipped' };
  const user = ((await db.collection('users').doc(n.userId).get()).data()) || {};
  const prefs = user.notificationPrefs;
  if (prefs && typeof prefs === 'object' && prefs.bookingUpdates === false) return { sent: false, reason: 'switched_off' };
  if (typeof user.phone !== 'string' || !msisdn(user.phone)) return { sent: false, reason: 'no_phone' };
  if (await hasPushToken(db, n.userId, user)) return { sent: false, reason: 'has_push' };
  // A notification is a document any signed-in person can address to somebody else. A text message costs money and can
  // annoy, so it goes out only when the notification is about a booking of which this person is the customer.
  if (!safeId(n.relatedId)) return { sent: false, reason: 'no_booking' };
  const booking = (await db.collection('bookings').doc(n.relatedId).get()).data();
  if (!booking || booking.customerId !== n.userId) return { sent: false, reason: 'not_their_booking' };
  const ref = safeId(n.relatedId) ? n.relatedId.slice(-6).toUpperCase() : '';
  try {
    await sendTemplate(db, http, { uid: n.userId, to: user.phone, template: 'tripStatus', vars: { var1: TRIP_TYPES[n.type], var2: ref } }, nowMs);
    return { sent: true };
  } catch (e) {
    if (e && (e.code === 'resource-exhausted' || e.code === 'failed-precondition' || e.code === 'unavailable')) return { sent: false, reason: e.code };
    throw e;
  }
}

module.exports = { SmsError, msisdn, msg91Http, sendTemplate, emergencySms, onNotificationSms, TRIP_TYPES, DEFAULTS };
