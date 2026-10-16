'use strict';
// F17: the second scan of every chat message, on the server. The phone checks
// a message before sending it (lib/core/comm), the rules refuse the simplest
// cases, and a modified app could skip both. This scan runs for every created
// message: if it carries contact or payment details the message is removed and
// the sender gets a strike by the same ladder as the app (chat_strikes.dart).

const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { check } = require('./contactFilter');
const { safeId, text } = require('./common');

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

// Strike 1 and 2: a warning. 3: 24 hours. 4: 3 days. 5 and more: 7 days and an admin review.
function blockFor(strikes) {
  if (strikes >= 5) return 7 * DAY;
  if (strikes === 4) return 3 * DAY;
  if (strikes === 3) return DAY;
  return null;
}

function needsReview(strikes) {
  return strikes >= 5;
}

async function recentTexts(ref, senderId, createdAt) {
  let q = ref.parent.where('senderId', '==', senderId);
  if (createdAt) q = q.where('createdAt', '<', createdAt);
  const snap = await q.orderBy('createdAt', 'desc').limit(3).get();
  return snap.docs.map((d) => text(d.data().text, 600));
}

// Scans one created message. Returns what happened (for tests and logs).
async function scanMessage(db, ref, data, nowMs = Date.now()) {
  if (!data || typeof data !== 'object') return { action: 'skipped' };
  const uid = safeId(data.senderId);
  const body = text(data.text, 2000);
  if (!uid || body.trim().length === 0) return { action: 'skipped' };

  const createdAt = data.createdAt instanceof Timestamp ? data.createdAt : null;
  const recent = await recentTexts(ref, uid, createdAt);
  const kind = check(body, recent);
  if (kind === null) return { action: 'clean' };

  const parentId = ref.parent.parent ? ref.parent.parent.id : '';
  const userRef = db.collection('users').doc(uid);
  return db.runTransaction(async (tx) => {
    const msg = await tx.get(ref);
    if (!msg.exists) return { action: 'skipped' }; // already handled (a retry)
    const user = await tx.get(userRef);
    const u = user.exists ? user.data() : {};
    const strikes = (Number.isSafeInteger(u.chatStrikes) ? u.chatStrikes : 0) + 1;
    const seq = (Number.isSafeInteger(u.chatSeq) ? u.chatSeq : 0) + 1;
    const block = blockFor(strikes);
    const until = block === null ? null : Timestamp.fromMillis(nowMs + block);
    const excerpt = body.trim().replace(/\s+/g, ' ').slice(0, 120);
    tx.set(db.collection('violations').doc(`${uid}_${seq}`), {
      userId: uid,
      bookingId: parentId,
      kind,
      excerpt,
      source: 'server',
      createdAt: Timestamp.fromMillis(nowMs),
    });
    tx.set(
      userRef,
      {
        chatStrikes: strikes,
        chatSeq: seq,
        chatStrikeAt: Timestamp.fromMillis(nowMs),
        ...(until ? { chatBlockedUntil: until } : {}),
        ...(needsReview(strikes) ? { chatReview: true } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.delete(ref);
    return { action: 'violation', kind, strikes, blockedUntil: until ? until.toMillis() : null };
  });
}

module.exports = { scanMessage, blockFor, needsReview };
