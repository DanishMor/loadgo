'use strict';
// F23: the earnings and accounts book on the server. The app computes balances
// from the ledger on the phone; the rules cannot add lines up. This module does
// it with the Admin SDK:
//   * recomputeWallet  : adds up a person's ledger lines and payouts and writes
//                        wallets/{uid} (clients cannot write it). Pure function of
//                        the stored data, so running it twice, or in parallel, gives
//                        the same result.
//   * validatePayout   : a new payout request that asks for more than is available,
//                        or while another is open, is rejected by the server.
//   * reconcileAll     : the daily check over everyone; writes reconciliation_reports/{day}.
//   * decidePayout     : approve, pay, reject and reverse as a callable with the
//                        maker-checker rule, a reason where needed, and the audit line.
// The numbers follow lib/core/money/wallet_book.dart.

const { Timestamp, FieldPath } = require('firebase-admin/firestore');
const { safeId, paise, text } = require('./common');
const { ActionError, requireStaff } = require('./adminActions');

const LIMIT = 1e15; // the same clamp as Money.limit in the app (web-safe)
const OPEN = ['requested', 'approved'];
const NET_TYPES = ['trip_earning', 'platform_commission', 'adjustment'];
const FINANCE_ROLES = Object.freeze(['super', 'finance']);
const MAX_LINE = 1e11; // WalletEntry.maxPaise in the app

function clamp(n) {
  return Math.max(-LIMIT, Math.min(LIMIT, n));
}

function billAmount(b) {
  const paid = paise(b.paidAmountPaise);
  if (paid > 0) return paid;
  const agreed = paise(b.agreedFarePaise);
  if (agreed > 0) return agreed;
  const est = paise(b.fareEstimate);
  if (est > 0) return est;
  return typeof b.budget === 'number' && Number.isFinite(b.budget) ? Math.round(b.budget * 100) : 0;
}

// A ledger line the app's WalletBook would accept: a known type, not zero, not above the largest line;
// a commission is never positive.
function lineOk(l) {
  const a = paise(l.amountPaise);
  if (!NET_TYPES.includes(l.type) || a === 0 || Math.abs(a) > MAX_LINE) return false;
  return !(l.type === 'platform_commission' && a > 0);
}

// Pure: the boxes from the stored lines, payouts and bookings.
function computeBoxes({ ledger, payouts, bookings }) {
  let net = 0;
  for (const l of ledger) if (lineOk(l)) net = clamp(net + paise(l.amountPaise));
  let held = 0;
  let paidOut = 0;
  for (const p of payouts) {
    const raw = paise(p.amountPaise);
    const a = raw > 0 && raw <= MAX_LINE ? raw : 0;
    if (OPEN.includes(p.status)) held = clamp(held + a);
    else if (p.status === 'paid') paidOut = clamp(paidOut + a);
  }
  let pending = 0;
  for (const b of bookings) {
    if (b.status === 'delivered' && b.paymentStatus !== 'driver_confirmed') pending = clamp(pending + billAmount(b));
  }
  const available = clamp(net - held - paidOut);
  return { netPaise: net, availablePaise: available, heldPaise: held, paidOutPaise: paidOut, pendingPaise: pending, overdrawn: available < 0 };
}

async function recomputeWallet(db, uid, nowMs = Date.now()) {
  if (!safeId(uid)) return null;
  const wref = db.collection('wallets').doc(uid);
  return db.runTransaction(async (tx) => {
    const [ledger, payouts, held, assigned] = await Promise.all([
      tx.get(db.collection('ledger').where('driverId', '==', uid)),
      tx.get(db.collection('payouts').where('driverId', '==', uid)),
      tx.get(db.collection('bookings').where('driverId', '==', uid).where('status', '==', 'delivered')),
      tx.get(db.collection('bookings').where('assignedDriverId', '==', uid).where('status', '==', 'delivered')),
    ]);
    const seen = new Set();
    const bookings = [];
    for (const d of [...held.docs, ...assigned.docs]) {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        bookings.push(d.data());
      }
    }
    const boxes = computeBoxes({ ledger: ledger.docs.map((d) => d.data()), payouts: payouts.docs.map((d) => d.data()), bookings });
    const summary = { ...boxes, lines: ledger.size, payouts: payouts.size, updatedAt: Timestamp.fromMillis(nowMs) };
    tx.set(wref, summary);
    return summary;
  });
}

// A new payout request: reject it when it cannot be paid from what is available.
// The request itself is excluded from "held" so it is judged against the rest.
async function validatePayout(db, payoutId, payout, nowMs = Date.now()) {
  if (!payout || payout.status !== 'requested' || !safeId(payout.driverId) || !safeId(payoutId)) return { action: 'skipped' };
  const uid = payout.driverId;
  const ref = db.collection('payouts').doc(payoutId);
  const verdict = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh.exists || fresh.data().status !== 'requested') return null;
    const [ledger, payouts] = await Promise.all([tx.get(db.collection('ledger').where('driverId', '==', uid)), tx.get(db.collection('payouts').where('driverId', '==', uid))]);
    const others = payouts.docs.filter((d) => d.id !== payoutId).map((d) => d.data());
    const b = computeBoxes({ ledger: ledger.docs.map((d) => d.data()), payouts: others, bookings: [] });
    const amount = paise(fresh.data().amountPaise);
    let reason = null;
    if (others.some((p) => OPEN.includes(p.status))) reason = 'another_open_request';
    else if (amount <= 0) reason = 'bad_amount';
    else if (amount > b.availablePaise) reason = 'over_available';
    if (reason) {
      tx.update(ref, { status: 'rejected', reason: `server:${reason}`, handledBy: 'server', handledAt: Timestamp.fromMillis(nowMs) });
      tx.set(db.collection('audit_events').doc(), {
        type: 'user_action',
        actorId: 'server',
        targetId: payoutId,
        data: { action: 'payout_auto_reject', reason, amountPaise: amount },
        createdAt: Timestamp.fromMillis(nowMs),
      });
    }
    return reason;
  });
  await recomputeWallet(db, uid, nowMs);
  return verdict ? { action: 'rejected', reason: verdict } : { action: 'ok' };
}

// The daily check over everyone who has lines or payouts.
async function reconcileAll(db, nowMs = Date.now()) {
  const ids = new Set();
  for (const col of ['ledger', 'payouts']) {
    let last = null;
    for (;;) {
      let q = db.collection(col).orderBy(FieldPath.documentId()).limit(500);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      snap.docs.forEach((d) => {
        const id = safeId(d.data().driverId);
        if (id) ids.add(id);
      });
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) break;
    }
  }
  const problems = [];
  for (const uid of ids) {
    const s = await recomputeWallet(db, uid, nowMs);
    if (s.overdrawn) problems.push({ uid, kind: 'overdrawn', availablePaise: s.availablePaise });
  }
  const day = new Date(nowMs).toISOString().slice(0, 10).replace(/-/g, '');
  const report = { checked: ids.size, problems, at: Timestamp.fromMillis(nowMs) };
  await db.collection('reconciliation_reports').doc(day).set(report);
  return { day, ...report };
}

const REJECT_NEEDS = { reject: [3, 200], reverse: [5, 200] };

// approve | pay | reject | reverse by a finance or super admin. Same rules as firestore.rules.
async function decidePayout(db, callerUid, input, nowMs = Date.now()) {
  const role = await requireStaff(db, callerUid, FINANCE_ROLES);
  const id = safeId(input && input.payoutId);
  const action = input && input.action;
  if (!id) throw new ActionError('invalid-argument', 'payoutId');
  if (!['approve', 'pay', 'reject', 'reverse'].includes(action)) throw new ActionError('invalid-argument', 'action');
  const reason = text(input.reason, 400).trim();
  const reference = text(input.reference, 200).trim();
  const range = REJECT_NEEDS[action];
  if (range && (reason.length < range[0] || reason.length > range[1])) throw new ActionError('invalid-argument', 'reason');
  if (action === 'pay' && (reference.length < 4 || reference.length > 60)) throw new ActionError('invalid-argument', 'reference');

  const ref = db.collection('payouts').doc(id);
  const when = Timestamp.fromMillis(nowMs);
  let driverId = null;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new ActionError('not-found', 'payout');
    const p = snap.data();
    driverId = safeId(p.driverId);
    let patch;
    if (action === 'approve') {
      if (p.status !== 'requested') throw new ActionError('failed-precondition', 'not waiting for approval');
      patch = { status: 'approved', approvedBy: callerUid, approvedAt: when };
    } else if (action === 'pay') {
      if (p.status !== 'approved') throw new ActionError('failed-precondition', 'not approved');
      if (p.approvedBy === callerUid) throw new ActionError('permission-denied', 'the approver cannot pay');
      patch = { status: 'paid', paidBy: callerUid, paidAt: when, reference };
    } else if (action === 'reject') {
      if (!OPEN.includes(p.status)) throw new ActionError('failed-precondition', 'already settled');
      patch = { status: 'rejected', handledBy: callerUid, handledAt: when, reason };
    } else {
      if (p.status !== 'paid') throw new ActionError('failed-precondition', 'not paid');
      patch = { status: 'reversed', reversedBy: callerUid, reversedAt: when, reason };
    }
    tx.update(ref, patch);
    tx.set(db.collection('audit_events').doc(), {
      type: 'payout_decision',
      actorId: callerUid,
      targetId: id,
      data: { action, amountPaise: paise(p.amountPaise), via: 'server', role },
      createdAt: when,
    });
  });
  if (driverId) await recomputeWallet(db, driverId, nowMs);
  return { ok: true, payoutId: id, action };
}

module.exports = { computeBoxes, billAmount, recomputeWallet, validatePayout, reconcileAll, decidePayout };
