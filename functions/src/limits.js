'use strict';
// F16: server-side limits. The Firestore rules already make every counted
// create bump an hourly counter, but rules cannot see bursts (many creates in
// one minute) and cannot cross-check the counter against what was really
// written. This module counts the real documents of the creator in the last
// minute and the last hour and removes the new document when the limit is
// passed. Plain functions: the Firestore handle is an argument.

const { Timestamp } = require('firebase-admin/firestore');
const { safeId } = require('./common');

// hour limits equal the rules (rateLimitFor in firestore.rules and RateLimit.limits in the app);
// minute limits are new (burst protection).
const SPECS = Object.freeze({
  load: { collection: 'loads', group: false, creator: 'shipperId', hour: 30, minute: 5 },
  offer: { collection: 'offers', group: false, creator: 'driverId', hour: 60, minute: 10 },
  message: { collection: 'messages', group: true, creator: 'senderId', hour: 120, minute: 20 },
  call: { collection: 'calls', group: false, creator: 'callerId', hour: 20, minute: 3 },
  ticket: { collection: 'tickets', group: false, creator: 'userId', hour: 10, minute: 3 },
});

const WINDOWS = Object.freeze({ minute: 60 * 1000, hour: 60 * 60 * 1000 });

async function countSince(db, kind, uid, sinceMs) {
  const spec = SPECS[kind];
  const base = spec.group ? db.collectionGroup(spec.collection) : db.collection(spec.collection);
  const snap = await base
    .where(spec.creator, '==', uid)
    .where('createdAt', '>=', Timestamp.fromMillis(sinceMs))
    .count()
    .get();
  return snap.data().count;
}

// Which windows are over the limit, counting the document that was just created.
async function check(db, kind, uid, nowMs = Date.now()) {
  const spec = SPECS[kind];
  if (!spec || !safeId(uid)) return { over: [], counts: {} };
  const over = [];
  const counts = {};
  for (const w of ['minute', 'hour']) {
    const count = await countSince(db, kind, uid, nowMs - WINDOWS[w]);
    counts[w] = count;
    if (count > spec[w]) over.push({ window: w, count, limit: spec[w] });
  }
  return { over, counts };
}

// The creator of a new document (null when the document has no usable creator).
function creatorOf(kind, data) {
  const spec = SPECS[kind];
  if (!spec || !data || typeof data !== 'object') return null;
  return safeId(data[spec.creator]);
}

// Called for a created document. Removes it when the creator is over a limit
// and writes one audit line. Returns what happened (for tests and logs).
async function enforce(db, kind, ref, data, nowMs = Date.now()) {
  const uid = creatorOf(kind, data);
  if (!uid) return { action: 'skipped' };
  const { over, counts } = await check(db, kind, uid, nowMs);
  if (over.length === 0) return { action: 'none', counts };
  await ref.delete();
  await db.collection('audit_events').add({
    type: 'user_action',
    actorId: 'server',
    targetId: uid,
    data: { action: 'server_limit', kind, window: over[0].window, count: over[0].count, limit: over[0].limit },
    createdAt: Timestamp.fromMillis(nowMs),
  });
  return { action: 'removed', over, counts };
}

module.exports = { SPECS, WINDOWS, check, enforce, creatorOf, countSince };
