'use strict';
// F22: account deletion on the server. The person asks (deletion_requests/{uid},
// status pending); an admin sets the status to "approved"; this function then
// removes the person's data in a fixed order and marks the request "done".
// Every step can be run again: a half-finished deletion is finished by the next run.
//
// What goes:   the user document and everything under it, the sign-in, the
//              person's files (users/{uid}/ in Storage), the identity index, the
//              referral code, notifications, rate counters, server summaries.
// What stays:  bookings, loads and chats the other side still needs (the person's
//              name and phone in them are cleared), and the money records
//              (ledger, payouts, wallet_freezes), which the tax rules may require
//              (docs/WALLET_LEGAL.md). Their ids are the only link left.
// What blocks: an open payout (requested or approved), or an admin account.

const { Timestamp, FieldPath } = require('firebase-admin/firestore');
const { safeId } = require('./common');

// [collection, field] pairs whose documents belong to the person.
const DELETE_BY_FIELD = Object.freeze([
  ['identity_index', 'uid'],
  ['referral_codes', 'uid'],
  ['notifications', 'userId'],
  ['truck_posts', 'driverId'],
]);

// Documents whose id starts with the uid (uid_kind, uid_seq).
const DELETE_BY_ID_PREFIX = Object.freeze(['rate_limits']);

// Single documents named by the uid.
const DELETE_SINGLE = Object.freeze(['credit_balances', 'public_trust', 'trip_counts', 'driver_presence', 'referrals']);

const ANON_FIELDS = Object.freeze({ driverName: '', driverPhone: '', vehicleNumber: '' });

async function deleteQuery(query) {
  let n = 0;
  for (;;) {
    const snap = await query.limit(300).get();
    if (snap.empty) return n;
    const batch = query.firestore.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    n += snap.size;
    if (snap.size < 300) return n;
  }
}

async function openPayouts(db, uid) {
  const snap = await db.collection('payouts').where('driverId', '==', uid).where('status', 'in', ['requested', 'approved']).limit(1).get();
  return !snap.empty;
}

async function anonymiseBookings(db, uid) {
  let n = 0;
  for (const field of ['driverId', 'customerId']) {
    let last = null;
    for (;;) {
      let q = db.collection('bookings').where(field, '==', uid).orderBy(FieldPath.documentId()).limit(300);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      const batch = db.batch();
      let writes = 0;
      for (const d of snap.docs) {
        const data = d.data();
        if (data.anonymised === true) continue;
        const clear = field === 'driverId' ? ANON_FIELDS : { customerName: '', customerPhone: '' };
        // Only fields that exist are touched.
        const patch = Object.fromEntries(Object.entries(clear).filter(([k]) => k in data));
        batch.update(d.ref, { ...patch, anonymised: true });
        writes++;
      }
      if (writes > 0) await batch.commit();
      n += writes;
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 300) break;
    }
  }
  return n;
}

// auth: { deleteUser(uid) }, storage: { deleteFiles({prefix}) } (the Admin SDK objects, or fakes in tests).
async function deleteAccount(db, auth, storage, uid, nowMs = Date.now()) {
  if (!safeId(uid)) return { action: 'skipped' };
  const reqRef = db.collection('deletion_requests').doc(uid);
  const req = await reqRef.get();
  if (!req.exists || req.data().status !== 'approved') return { action: 'skipped' };
  if ((await db.collection('admins').doc(uid).get()).exists) {
    await reqRef.update({ status: 'pending', blockedReason: 'admin_account', blockedAt: Timestamp.fromMillis(nowMs) });
    return { action: 'blocked', reason: 'admin_account' };
  }
  if (await openPayouts(db, uid)) {
    await reqRef.update({ status: 'pending', blockedReason: 'open_payout', blockedAt: Timestamp.fromMillis(nowMs) });
    return { action: 'blocked', reason: 'open_payout' };
  }

  const counts = {};
  counts.bookings = await anonymiseBookings(db, uid);
  for (const [col, field] of DELETE_BY_FIELD) counts[col] = await deleteQuery(db.collection(col).where(field, '==', uid));
  for (const col of DELETE_BY_ID_PREFIX) {
    counts[col] = await deleteQuery(db.collection(col).where(FieldPath.documentId(), '>=', `${uid}_`).where(FieldPath.documentId(), '<', `${uid}_￿`));
  }
  for (const col of DELETE_SINGLE) {
    const ref = db.collection(col).doc(uid);
    if (col === 'trip_counts') await db.recursiveDelete(ref);
    else await ref.delete();
  }
  await storage.deleteFiles({ prefix: `users/${uid}/` });
  try {
    await auth.deleteUser(uid);
  } catch (e) {
    if (!(e && e.code === 'auth/user-not-found')) throw e;
  }
  await db.recursiveDelete(db.collection('users').doc(uid));
  await reqRef.update({ status: 'done', completedAt: Timestamp.fromMillis(nowMs), deletedBy: 'server', blockedReason: null });
  return { action: 'deleted', counts };
}

module.exports = { deleteAccount, DELETE_BY_FIELD, DELETE_BY_ID_PREFIX, DELETE_SINGLE };
