'use strict';
// F21: admin actions as server functions. Risk tier and driver approval were
// done by the admin's phone writing straight to the user's document. Here the
// server checks the caller is an admin with the right staff role, makes the
// same change the rules allow, and writes the audit line itself, so the line
// cannot be skipped or forged. The functions take the Firestore handle and the
// caller's uid as arguments; index.js wraps them as callables.

const { Timestamp } = require('firebase-admin/firestore');
const { safeId, text, readFlags, FLAGS, REGION } = require('./common');

const TIERS = Object.freeze(['normal', 'review', 'restricted', 'suspended', 'banned']);
const STATUSES = Object.freeze(['pending', 'approved', 'rejected']);
const REJECT_REASONS = Object.freeze(['docs_unclear', 'name_mismatch', 'licence_expired', 'rc_mismatch', 'other']);
const STAFF_ROLES = Object.freeze(['super', 'support', 'verifier', 'ops', 'finance']);

// Who may do what (the same as adminRiskUpdate and adminVerificationUpdate in the rules).
const RISK_ROLES = Object.freeze(['super', 'ops']);
const VERIFY_ROLES = Object.freeze(['super', 'verifier']);

class ActionError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // 'unauthenticated' | 'permission-denied' | 'invalid-argument' | 'not-found'
  }
}

async function requireStaff(db, uid, allowed) {
  if (!safeId(uid)) throw new ActionError('unauthenticated', 'sign in first');
  const snap = await db.collection('admins').doc(uid).get();
  if (!snap.exists) throw new ActionError('permission-denied', 'not an admin');
  const role = STAFF_ROLES.includes(snap.data().role) ? snap.data().role : 'super';
  if (!allowed.includes(role)) throw new ActionError('permission-denied', `role ${role} may not do this`);
  return role;
}

async function setRiskTier(db, callerUid, input, nowMs = Date.now()) {
  const role = await requireStaff(db, callerUid, RISK_ROLES);
  const target = safeId(input && input.uid);
  if (!target) throw new ActionError('invalid-argument', 'uid');
  if (!TIERS.includes(input.tier)) throw new ActionError('invalid-argument', 'tier');
  const reason = text(input.reason, 400).trim();
  if (reason.length > 200) throw new ActionError('invalid-argument', 'reason is longer than 200 characters');
  const ref = db.collection('users').doc(target);
  const when = Timestamp.fromMillis(nowMs);
  await db.runTransaction(async (tx) => {
    const u = await tx.get(ref);
    if (!u.exists) throw new ActionError('not-found', 'user');
    tx.update(ref, { riskTier: input.tier, riskReason: reason, riskUpdatedAt: when });
    tx.set(db.collection('audit_events').doc(), {
      type: 'risk_change',
      actorId: callerUid,
      targetId: target,
      data: { tier: input.tier, reason, via: 'server', role },
      createdAt: when,
    });
  });
  return { ok: true, uid: target, tier: input.tier };
}

async function decideDriver(db, callerUid, input, nowMs = Date.now()) {
  const role = await requireStaff(db, callerUid, VERIFY_ROLES);
  const target = safeId(input && input.uid);
  if (!target) throw new ActionError('invalid-argument', 'uid');
  if (!STATUSES.includes(input.status)) throw new ActionError('invalid-argument', 'status');
  const reason = input.reason === undefined || input.reason === null ? null : input.reason;
  if (reason !== null && (input.status !== 'rejected' || !REJECT_REASONS.includes(reason))) throw new ActionError('invalid-argument', 'reason');
  const note = text(input.note, 400).trim();
  if (note.length > 120 || (note.length > 0 && reason === null)) throw new ActionError('invalid-argument', 'note');
  const ref = db.collection('users').doc(target);
  const when = Timestamp.fromMillis(nowMs);
  await db.runTransaction(async (tx) => {
    const u = await tx.get(ref);
    if (!u.exists) throw new ActionError('not-found', 'user');
    tx.update(ref, {
      verificationStatus: input.status,
      verified: input.status === 'approved',
      verificationMeta: {
        source: 'manual_review',
        by: callerUid,
        status: input.status,
        at: when,
        ...(reason !== null ? { reason } : {}),
        ...(reason !== null && note.length > 0 ? { note } : {}),
      },
      updatedAt: when,
    });
    tx.set(db.collection('audit_events').doc(), {
      type: 'verification',
      actorId: callerUid,
      targetId: target,
      data: { status: input.status, ...(reason !== null ? { reason } : {}), via: 'server', role },
      createdAt: when,
    });
  });
  return { ok: true, uid: target, status: input.status };
}

// F33: "is the server there?" Any admin may ask; it works with every switch off, so it is the
// first thing to try after a deploy. Returns which server switches are on, nothing about people.
async function serverStatus(db, callerUid, nowMs = Date.now()) {
  await requireStaff(db, callerUid, STAFF_ROLES);
  const flags = await readFlags(db);
  const switches = {};
  for (const name of FLAGS) switches[name] = flags[name] === true;
  return { ok: true, region: REGION, at: nowMs, switches };
}

module.exports = { ActionError, requireStaff, serverStatus, setRiskTier, decideDriver, TIERS, STATUSES, REJECT_REASONS, RISK_ROLES, VERIFY_ROLES };
