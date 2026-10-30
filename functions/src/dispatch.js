'use strict';
// Server side of the bid engine (Part 4, U14). Switch: config/features.flags.dispatchV2 (OFF by default).
//
// 1. autoAcceptBids: when a bid arrives on a load that has an autoAccept rule, the server applies the same rule
//    the app applies while the customer's app is open, so a bid can be taken with the app closed.
// 2. dispatchWave: the rings of an instant load (which wave is open). Skeleton: it records the wave on the load;
//    sending the push to the drivers of the ring is the next step (TODO(functions) below).
//
// Both are skeletons until the owner deploys and turns dispatchV2 on; nothing here runs before that.

const RING_KM = [3, 7, 15];
const RING_DELAY_S = [0, 30, 60];
const ACCEPT_S = 30;

function isRule(a) {
  return !!a && typeof a === 'object' && Number.isSafeInteger(a.maxPaise) && a.maxPaise > 0 && a.maxPaise <= 100000000 &&
    typeof a.minRating === 'number' && a.minRating >= 0 && a.minRating <= 5 && typeof a.verifiedOnly === 'boolean';
}

// The same rule as lib/core/dispatch/dispatch_models.dart AutoAccept.accepts.
function ruleAccepts(rule, bid) {
  if (!isRule(rule)) return false;
  if (!Number.isSafeInteger(bid.pricePaise) || bid.pricePaise <= 0 || bid.pricePaise > rule.maxPaise) return false;
  if (rule.verifiedOnly && bid.verified !== true) return false;
  if (rule.minRating > 0 && (typeof bid.rating !== 'number' || bid.rating < rule.minRating)) return false;
  return true;
}

// The cheapest pending bid the rule allows (earliest on a tie), or null. offers: [{id, ...offer fields}].
function pickBid(rule, offers, trustOf) {
  const live = offers
    .filter((o) => o.status === 'pending')
    .map((o) => {
      const t = trustOf(o.driverId) || {};
      return { o, bid: { pricePaise: o.pricePaise, rating: typeof t.rating === 'number' ? t.rating : null, verified: t.verified === true || o.companyVerified === true } };
    })
    .filter(({ bid }) => ruleAccepts(rule, bid));
  live.sort((a, b) => a.o.pricePaise - b.o.pricePaise || millis(a.o.createdAt) - millis(b.o.createdAt) || (a.o.id < b.o.id ? -1 : 1));
  return live.length ? live[0].o : null;
}

function millis(t) {
  return t && typeof t.toMillis === 'function' ? t.toMillis() : 0;
}

// Selects the picked bid and rejects every other pending or selected bid on the load, in one transaction that
// re-reads the load and the bid, so a customer who accepted by hand a second ago is not overridden.
async function autoAccept(db, loadId, FieldValue) {
  const loadRef = db.collection('loads').doc(loadId);
  const load = (await loadRef.get()).data();
  if (!load || load.status !== 'open' || !isRule(load.autoAccept)) return { accepted: null, reason: 'no rule' };
  const snap = await db.collection('offers').where('loadId', '==', loadId).get();
  const offers = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  const trust = {};
  for (const o of offers) {
    if (o.status === 'pending' && !(o.driverId in trust)) {
      const t = await db.collection('public_trust').doc(o.driverId).get();
      trust[o.driverId] = t.exists ? t.data() : null;
    }
  }
  const pick = pickBid(load.autoAccept, offers, (id) => trust[id]);
  if (!pick) return { accepted: null, reason: 'no bid fits' };
  const result = await db.runTransaction(async (tx) => {
    const fresh = (await tx.get(loadRef)).data();
    const mine = await tx.get(db.collection('offers').doc(pick.id));
    if (!fresh || fresh.status !== 'open' || !mine.exists || mine.data().status !== 'pending') return { accepted: null, reason: 'changed' };
    const others = await tx.get(db.collection('offers').where('loadId', '==', loadId));
    for (const d of others.docs) {
      if (d.id === pick.id) continue;
      const st = d.data().status;
      if (st === 'pending' || st === 'selected') tx.update(d.ref, { status: 'rejected', updatedAt: FieldValue.serverTimestamp() });
    }
    tx.update(mine.ref, { status: 'selected', updatedAt: FieldValue.serverTimestamp(), autoAccepted: true });
    return { accepted: pick.id };
  });
  return result;
}

// E36: a head start in seconds for loads of Black-tier customers (config dispatch.blackHeadStartSeconds, 0 to 120,
// default 0 = no difference). Their wider rings open that much sooner; nothing else changes.
function headStartSeconds(tier, cfg = {}) {
  const s = cfg.blackHeadStartSeconds;
  if (tier !== 'black' || !Number.isSafeInteger(s)) return 0;
  return Math.max(0, Math.min(120, s));
}

// Which wave is open for a load posted at createdMs, given the settings. -1 before the first, stalled after the last.
function currentWave(createdMs, nowMs, cfg = {}, headStartS = 0) {
  const delays = Array.isArray(cfg.ringDelaySeconds) ? cfg.ringDelaySeconds : RING_DELAY_S;
  const accept = Number.isSafeInteger(cfg.acceptSeconds) ? cfg.acceptSeconds : ACCEPT_S;
  const head = Number.isSafeInteger(headStartS) && headStartS > 0 ? headStartS : 0;
  const elapsed = Math.max(0, Math.floor((nowMs - createdMs) / 1000) + head);
  if (elapsed >= delays[delays.length - 1] + accept) return { wave: delays.length - 1, stalled: true };
  let wave = 0;
  for (let i = 0; i < delays.length; i++) if (elapsed >= delays[i]) wave = i;
  return { wave, stalled: false };
}

// Records the open wave on each recent open instant load whose wave changed. Skeleton: no push yet.
async function runWave(db, nowMs, cfg = {}) {
  const since = new Date(nowMs - 10 * 60 * 1000);
  const snap = await db.collection('loads').where('status', '==', 'open').where('createdAt', '>=', since).get();
  let updated = 0;
  // E36: the shipper's tier, read once per run and only when a head start is configured.
  const tiers = new Map();
  const tierOf = async (uid) => {
    if (!cfg.blackHeadStartSeconds || typeof uid !== 'string' || !uid) return null;
    if (!tiers.has(uid)) tiers.set(uid, (await db.collection('users').doc(uid).get()).get('tier') || null);
    return tiers.get(uid);
  };
  for (const d of snap.docs) {
    const l = d.data();
    if (l.mode === 'bid' || l.mode === 'scheduled' || !l.createdAt) continue;
    const { wave, stalled } = currentWave(l.createdAt.toMillis(), nowMs, cfg, headStartSeconds(await tierOf(l.shipperId), cfg));
    if (l.dispatchWave === wave && l.dispatchStalled === stalled) continue;
    await d.ref.update({ dispatchWave: wave, dispatchStalled: stalled });
    // TODO(functions): send the "new load near you" push to the drivers of ring `wave` (push.js, switch pushNotifications).
    updated++;
  }
  return { updated };
}

module.exports = { RING_KM, RING_DELAY_S, ACCEPT_S, isRule, ruleAccepts, pickBid, autoAccept, currentWave, runWave, headStartSeconds };
