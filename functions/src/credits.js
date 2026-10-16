'use strict';
// F18: credits and referral settlement on the server. Credit lines are written
// by the app (spend), by admins (grant, deduct) and by the referral step. The
// rules check each line but cannot add them up, so a modified app could spend
// more than it has. The server adds the lines up (the real balance), writes it
// to credit_balances/{uid} (clients cannot write that document), marks an
// overspend on the load and audits it, and checks every referral.

const { Timestamp, AggregateField } = require('firebase-admin/firestore');
const { safeId, paise } = require('./common');

const REFERRAL_WINDOW_MS = 7 * 24 * 3600 * 1000;
const MAX_REFERRALS_PER_PERSON = 20;

// The real balance: the sum of every credit line (signed whole paise).
async function recomputeBalance(db, uid, nowMs = Date.now()) {
  if (!safeId(uid)) return null;
  const col = db.collection('users').doc(uid).collection('credits');
  const agg = await col.aggregate({ total: AggregateField.sum('amountPaise'), lines: AggregateField.count() }).get();
  const d = agg.data();
  const balancePaise = paise(d.total);
  await db.collection('credit_balances').doc(uid).set({
    balancePaise,
    lines: d.lines,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  return { balancePaise, lines: d.lines };
}

// A new credit line. A spend that takes the balance below zero is an overspend:
// the load is marked with the shortfall and one audit line is written.
async function onCreditLine(db, uid, lineId, data, nowMs = Date.now()) {
  const r = await recomputeBalance(db, uid, nowMs);
  if (!r) return { action: 'skipped' };
  const isSpend = data && data.kind === 'spend' && paise(data.amountPaise) < 0;
  if (!isSpend || r.balancePaise >= 0) return { action: 'balanced', balancePaise: r.balancePaise };
  const loadId = safeId(data.loadId);
  const shortfall = Math.min(-r.balancePaise, -paise(data.amountPaise));
  if (loadId) {
    await db.collection('loads').doc(loadId).set({ creditsShortfallPaise: shortfall }, { merge: true });
  }
  await db.collection('audit_events').add({
    type: 'user_action',
    actorId: 'server',
    targetId: uid,
    loadId: loadId || null,
    data: { action: 'credit_overspend', amountPaise: shortfall },
    createdAt: Timestamp.fromMillis(nowMs),
  });
  return { action: 'overspend', balancePaise: r.balancePaise, shortfallPaise: shortfall };
}

// A new referral (referrals/{newUser} = { referrerUid, code }). The app already
// wrote a credit line for both people. If the referral does not hold, both lines
// are voided with an opposite line, so the real balance is right.
async function onReferral(db, uid, data, nowMs = Date.now()) {
  const referrer = data && safeId(data.referrerUid);
  if (!safeId(uid) || !referrer) return { action: 'skipped' };
  const problems = [];
  if (referrer === uid) problems.push('own_code');
  const users = db.collection('users');
  const [me, owner] = await Promise.all([users.doc(uid).get(), users.doc(referrer).get()]);
  if (!owner.exists) problems.push('unknown_referrer');
  const created = me.exists && me.data().createdAt instanceof Timestamp ? me.data().createdAt.toMillis() : null;
  if (created !== null && nowMs - created > REFERRAL_WINDOW_MS) problems.push('too_late');
  const count = (await db.collection('referrals').where('referrerUid', '==', referrer).count().get()).data().count;
  if (count > MAX_REFERRALS_PER_PERSON) problems.push('too_many');
  if (problems.length === 0) return { action: 'ok' };

  const bonus = async (owner_, lineId) => {
    const line = await users.doc(owner_).collection('credits').doc(lineId).get();
    const amount = line.exists ? paise(line.data().amountPaise) : 0;
    if (amount > 0) {
      await users.doc(owner_).collection('credits').doc(`void_${lineId}`).set({
        amountPaise: -amount,
        kind: 'referral_void',
        note: problems.join(','),
        createdAt: Timestamp.fromMillis(nowMs),
      });
    }
  };
  await bonus(uid, 'referral_in');
  await bonus(referrer, `referral_from_${uid}`);
  await db.collection('audit_events').add({
    type: 'user_action',
    actorId: 'server',
    targetId: uid,
    data: { action: 'referral_void' },
    createdAt: Timestamp.fromMillis(nowMs),
  });
  return { action: 'voided', problems };
}

module.exports = { recomputeBalance, onCreditLine, onReferral, REFERRAL_WINDOW_MS, MAX_REFERRALS_PER_PERSON };
