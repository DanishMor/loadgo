'use strict';
// G12/G17: a small daily quota for any paid server call. One counter per person per day and one for everybody,
// both in one transaction, so a bug or an attack cannot run up a bill. The limits are read from a config
// document (whole numbers only; junk means the default). Documents carry expireAt for a Firestore TTL policy.

class QuotaError extends Error {
  constructor(message) {
    super(message);
    this.code = 'resource-exhausted';
  }
}

function dayKey(nowMs) {
  return new Date(nowMs + 5.5 * 3600 * 1000).toISOString().slice(0, 10); // India date
}

function limitNumber(v, fallback) {
  return Number.isSafeInteger(v) && v >= 0 && v <= 1000000 ? v : fallback;
}

// kind: a short name such as 'sms'; defaults: { perUser, total }; cfg: the config document data (or undefined).
async function consume(db, kind, uid, defaults, cfg, nowMs = Date.now()) {
  const c = cfg || {};
  const perUser = limitNumber(c.perUserPerDay, defaults.perUser);
  const total = limitNumber(c.totalPerDay, defaults.total);
  const day = dayKey(nowMs);
  const mine = db.collection('quota_usage').doc(`${kind}_${uid}_${day}`);
  const all = db.collection('quota_usage').doc(`${kind}_all_${day}`);
  await db.runTransaction(async (tx) => {
    const [a, b] = await Promise.all([tx.get(mine), tx.get(all)]);
    const nMine = a.exists ? a.data().n || 0 : 0;
    const nAll = b.exists ? b.data().n || 0 : 0;
    if (nMine >= perUser) throw new QuotaError(`daily limit for ${kind} reached`);
    if (nAll >= total) throw new QuotaError(`${kind} is paused for today`);
    const expireAt = new Date(nowMs + 3 * 86400000);
    tx.set(mine, { kind, uid, day, n: nMine + 1, expireAt });
    tx.set(all, { kind, day, n: nAll + 1, expireAt });
  });
}

module.exports = { consume, QuotaError, dayKey, limitNumber };
