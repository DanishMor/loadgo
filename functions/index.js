// Cloud Functions of Load 20 (region asia-south1). Every feature sits behind a switch in config/features (all OFF).
// See docs/FUNCTIONS.md. Deploying needs the Firebase Blaze plan; Claude never deploys.
const { setGlobalOptions } = require('firebase-functions/v2');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { REGION, flagOn } = require('./src/common');
const limits = require('./src/limits');
const chatScan = require('./src/chatScan');
const credits = require('./src/credits');
const trust = require('./src/trust');
const jobs = require('./src/jobs');
const adminActions = require('./src/adminActions');
const deletion = require('./src/deletion');
const wallet = require('./src/wallet');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const push = require('./src/push');

initializeApp();
setGlobalOptions({ region: REGION, maxInstances: 10 });

// ---- F16: server-side limits (switch: serverLimits) ----
function limitTrigger(kind, path) {
  return onDocumentCreated(path, async (event) => {
    const db = getFirestore();
    if (!(await flagOn(db, 'serverLimits'))) return;
    const snap = event.data;
    if (!snap) return;
    await limits.enforce(db, kind, snap.ref, snap.data());
  });
}

exports.limitLoad = limitTrigger('load', 'loads/{id}');
exports.limitOffer = limitTrigger('offer', 'offers/{id}');
exports.limitBookingMessage = limitTrigger('message', 'bookings/{bookingId}/messages/{id}');
exports.limitLinkMessage = limitTrigger('message', 'driver_links/{linkId}/messages/{id}');
exports.limitGroupMessage = limitTrigger('message', 'driver_groups/{groupId}/messages/{id}');
exports.limitCall = limitTrigger('call', 'calls/{id}');
exports.limitTicket = limitTrigger('ticket', 'tickets/{id}');

// ---- F17: second scan of chat messages (switch: serverChatScan) ----
function chatScanTrigger(path) {
  return onDocumentCreated(path, async (event) => {
    const db = getFirestore();
    if (!(await flagOn(db, 'serverChatScan'))) return;
    const snap = event.data;
    if (!snap) return;
    await chatScan.scanMessage(db, snap.ref, snap.data());
  });
}

exports.scanBookingMessage = chatScanTrigger('bookings/{bookingId}/messages/{id}');
exports.scanLinkMessage = chatScanTrigger('driver_links/{linkId}/messages/{id}');
exports.scanGroupMessage = chatScanTrigger('driver_groups/{groupId}/messages/{id}');

// ---- F18: credits and referral settlement (switch: serverCredits) ----
const { onDocumentWritten, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');

exports.creditsBalance = onDocumentWritten('users/{uid}/credits/{lineId}', async (event) => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverCredits'))) return;
  const after = event.data && event.data.after;
  if (after && after.exists && !(event.data.before && event.data.before.exists)) {
    await credits.onCreditLine(db, event.params.uid, event.params.lineId, after.data());
  } else {
    await credits.recomputeBalance(db, event.params.uid);
  }
});

exports.referralCheck = onDocumentCreated('referrals/{uid}', async (event) => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverCredits'))) return;
  const snap = event.data;
  if (!snap) return;
  await credits.onReferral(db, event.params.uid, snap.data());
});

// ---- F19: trip counts and the public trust summary (switch: serverTrust) ----
exports.tripDelivered = onDocumentUpdated('bookings/{bookingId}', async (event) => {
  const before = event.data && event.data.before && event.data.before.data();
  const after = event.data && event.data.after && event.data.after.data();
  if (!after || after.status !== 'delivered' || (before && before.status === 'delivered')) return;
  const db = getFirestore();
  if (!(await flagOn(db, 'serverTrust'))) return;
  await trust.onDelivered(db, event.params.bookingId, after);
});

exports.ratingAdded = onDocumentCreated('ratings/{ratingId}', async (event) => {
  const data = event.data && event.data.data();
  if (!data || typeof data.ratedId !== 'string') return;
  const db = getFirestore();
  if (!(await flagOn(db, 'serverTrust'))) return;
  await trust.refreshSummary(db, data.ratedId);
});

// ---- F20: scheduled jobs (switch: serverJobs) ----
const IST = 'Asia/Kolkata';

exports.jobExpireLoads = onSchedule({ schedule: 'every day 03:00', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverJobs'))) return;
  await jobs.expireOpenLoads(db);
});

exports.jobHoldScheduled = onSchedule({ schedule: 'every 15 minutes', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverJobs'))) return;
  await jobs.holdScheduled(db);
});

exports.jobSuspendExpiredDocs = onSchedule({ schedule: 'every day 03:30', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverJobs'))) return;
  await jobs.suspendExpiredDocs(db);
});

// ---- F21: admin actions (switch: serverAdminActions) ----
// A callable turns an ActionError into the matching HttpsError; any other error is logged and hidden.
function adminCallable(action, flag = 'serverAdminActions') {
  return onCall(async (request) => {
    const db = getFirestore();
    if (!(await flagOn(db, flag))) throw new HttpsError('failed-precondition', 'disabled');
    try {
      return await action(db, request.auth && request.auth.uid, request.data);
    } catch (e) {
      if (e instanceof adminActions.ActionError) throw new HttpsError(e.code, e.message);
      console.error('admin action failed', e && e.message);
      throw new HttpsError('internal', 'failed');
    }
  });
}

exports.adminSetRiskTier = adminCallable(adminActions.setRiskTier);
exports.adminDecideDriver = adminCallable(adminActions.decideDriver);

// ---- F22: account deletion (switch: serverDeletion) ----
// The admin sets the request to "approved" (Admin > Deletion requests); this removes the data and the sign-in.
exports.deleteApprovedAccount = onDocumentUpdated('deletion_requests/{uid}', async (event) => {
  const before = event.data && event.data.before && event.data.before.data();
  const after = event.data && event.data.after && event.data.after.data();
  if (!after || after.status !== 'approved' || (before && before.status === 'approved')) return;
  const db = getFirestore();
  if (!(await flagOn(db, 'serverDeletion'))) return;
  await deletion.deleteAccount(db, getAuth(), getStorage().bucket(), event.params.uid);
});

// ---- F23: earnings and accounts on the server (switch: serverWallet) ----
exports.walletOnLedger = onDocumentWritten('ledger/{id}', async (event) => {
  const data = (event.data && event.data.after && event.data.after.exists ? event.data.after : event.data && event.data.before);
  const driverId = data && data.exists ? data.data().driverId : null;
  if (typeof driverId !== 'string') return;
  const db = getFirestore();
  if (!(await flagOn(db, 'serverWallet'))) return;
  await wallet.recomputeWallet(db, driverId);
});

exports.walletOnPayout = onDocumentWritten('payouts/{id}', async (event) => {
  const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const db = getFirestore();
  if (!(await flagOn(db, 'serverWallet'))) return;
  if (!before && after) {
    await wallet.validatePayout(db, event.params.id, after);
  } else if (after || before) {
    await wallet.recomputeWallet(db, (after || before).driverId);
  }
});

exports.walletReconcile = onSchedule({ schedule: 'every day 04:00', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await flagOn(db, 'serverWallet'))) return;
  await wallet.reconcileAll(db);
});

exports.adminPayoutDecision = adminCallable((db, uid, data) => wallet.decidePayout(db, uid, data), 'serverWallet');

// ---- F25 to F27: push messages (switch: pushNotifications; announcements: adminBroadcast) ----
function pushOn(db) {
  return flagOn(db, 'pushNotifications');
}

// Every new in-app notification also becomes a push (trip steps, ratings, payments, inspections ...).
exports.pushOnNotification = onDocumentCreated('notifications/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  const n = event.data && event.data.data();
  await push.onNotification(db, getMessaging(), n);
});

exports.pushOnOffer = onDocumentCreated('offers/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.onOffer(db, getMessaging(), event.data && event.data.data());
});

exports.pushOnOfferSelected = onDocumentUpdated('offers/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  const before = event.data && event.data.before && event.data.before.data();
  const after = event.data && event.data.after && event.data.after.data();
  await push.onOfferSelected(db, getMessaging(), before, after);
});

exports.pushOnChat = onDocumentCreated('bookings/{bookingId}/messages/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.onChatMessage(db, getMessaging(), event.params.bookingId, event.data && event.data.data());
});

exports.pushOnSos = onDocumentCreated('sos_alerts/{id}', async () => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.onSos(db, getMessaging());
});

exports.pushOnPayout = onDocumentUpdated('payouts/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  const before = event.data && event.data.before && event.data.before.data();
  const after = event.data && event.data.after && event.data.after.data();
  await push.onPayoutChange(db, getMessaging(), before, after);
});

// Wave dispatch: the first wave goes out when the load is posted, the later ones from the schedule.
exports.pushNewLoad = onDocumentCreated('loads/{id}', async (event) => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.dispatchLoad(db, getMessaging(), event.params.id);
});

exports.pushWaves = onSchedule({ schedule: 'every 2 minutes', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.dispatchRecent(db, getMessaging());
});

exports.pushDocExpiry = onSchedule({ schedule: 'every day 09:00', timeZone: IST }, async () => {
  const db = getFirestore();
  if (!(await pushOn(db))) return;
  await push.docExpiryReminders(db, getMessaging());
});

// F27: an announcement from the admin panel to a role or to everyone (super, support, ops).
exports.adminBroadcast = adminCallable(async (db, uid, data) => {
  await adminActions.requireStaff(db, uid, ['super', 'support', 'ops']);
  if (!(await pushOn(db))) throw new adminActions.ActionError('failed-precondition', 'push is off');
  const result = await push.broadcast(db, getMessaging(), { title: data && data.title, body: data && data.body, role: data && data.role });
  if (result.reason === 'bad_text') throw new adminActions.ActionError('invalid-argument', 'title and body');
  await db.collection('audit_events').add({ type: 'user_action', actorId: uid, targetId: 'broadcast', data: { action: 'broadcast', role: (data && data.role) || 'all', people: result.people, sent: result.sent }, createdAt: new Date() });
  return result;
}, 'adminBroadcast');
