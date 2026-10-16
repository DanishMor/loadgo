'use strict';
// G10: road distance and time through Google, behind our own server so the key never reaches a phone and
// the cost stays small:
//   * the answer for the same pair of places (rounded to about 1 km) is kept for 30 days in route_cache,
//     so a popular route is paid for once;
//   * each person may ask a few times a day (config/mapsLimits.perUserPerDay, default 20);
//   * the whole thing is a switch (maps) and also a hard cap per day for everybody
//     (config/mapsLimits.totalPerDay, default 2000) so a bug or an attack cannot run up a bill.
// The key is a Firebase secret (MAPS_SERVER_KEY). The HTTP call is injected so tests use a fake.

const { safeId } = require('./common');

const CACHE_DAYS = 30;
const DEFAULT_PER_USER = 20;
const DEFAULT_TOTAL = 2000;
// India, with a little margin: nothing outside it is asked.
const BOUNDS = Object.freeze({ latMin: 6, latMax: 38, lngMin: 68, lngMax: 98 });

class MapsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // 'invalid-argument' | 'unauthenticated' | 'resource-exhausted' | 'unavailable' | 'not-found'
  }
}

function point(p) {
  if (!p || typeof p.lat !== 'number' || typeof p.lng !== 'number' || !Number.isFinite(p.lat) || !Number.isFinite(p.lng)) return null;
  if (p.lat < BOUNDS.latMin || p.lat > BOUNDS.latMax || p.lng < BOUNDS.lngMin || p.lng > BOUNDS.lngMax) return null;
  return { lat: p.lat, lng: p.lng };
}

const r2 = (n) => Math.round(n * 100) / 100; // 0.01 degree is about 1.1 km

function cacheKey(a, b) {
  const f = (n) => r2(n).toFixed(2).replace('.', 'p').replace('-', 'm');
  return `${f(a.lat)}_${f(a.lng)}__${f(b.lat)}_${f(b.lng)}`;
}

function dayKey(nowMs) {
  return new Date(nowMs + 5.5 * 3600 * 1000).toISOString().slice(0, 10); // India date
}

function limitNumber(v, fallback) {
  return Number.isSafeInteger(v) && v >= 0 && v <= 1000000 ? v : fallback;
}

// Counts one use for this person and for everybody today, in one transaction. Refuses when over the limit.
async function consumeQuota(db, uid, nowMs) {
  const cfg = ((await db.collection('config').doc('mapsLimits').get()).data()) || {};
  const perUser = limitNumber(cfg.perUserPerDay, DEFAULT_PER_USER);
  const total = limitNumber(cfg.totalPerDay, DEFAULT_TOTAL);
  const day = dayKey(nowMs);
  const mine = db.collection('maps_usage').doc(`${uid}_${day}`);
  const all = db.collection('maps_usage').doc(`all_${day}`);
  await db.runTransaction(async (tx) => {
    const [a, b] = await Promise.all([tx.get(mine), tx.get(all)]);
    const nMine = a.exists ? a.data().n || 0 : 0;
    const nAll = b.exists ? b.data().n || 0 : 0;
    if (nMine >= perUser) throw new MapsError('resource-exhausted', 'too many route requests today');
    if (nAll >= total) throw new MapsError('resource-exhausted', 'route requests are paused for today');
    tx.set(mine, { n: nMine + 1, uid, day, expireAt: new Date(nowMs + 3 * 86400000) });
    tx.set(all, { n: nAll + 1, day, expireAt: new Date(nowMs + 3 * 86400000) });
  });
}

// Google Routes API (computeRoutes). Only the distance and the duration are asked for.
function googleRoutesHttp(apiKey, fetchImpl = fetch) {
  return async (from, to) => {
    let res;
    try {
      res = await fetchImpl('https://routes.googleapis.com/directions/v2:computeRoutes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': apiKey, 'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration' },
        body: JSON.stringify({
          origin: { location: { latLng: { latitude: from.lat, longitude: from.lng } } },
          destination: { location: { latLng: { latitude: to.lat, longitude: to.lng } } },
          travelMode: 'DRIVE',
          regionCode: 'IN',
        }),
      });
    } catch {
      throw new MapsError('unavailable', 'maps not reachable');
    }
    if (res.status >= 500 || res.status === 429) throw new MapsError('unavailable', 'maps busy');
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new MapsError('unavailable', 'maps refused');
    const r = json && json.routes && json.routes[0];
    if (!r || !Number.isSafeInteger(r.distanceMeters)) throw new MapsError('not-found', 'no route');
    const seconds = typeof r.duration === 'string' ? parseInt(r.duration.replace(/s$/, ''), 10) : NaN;
    return { meters: r.distanceMeters, seconds: Number.isSafeInteger(seconds) ? seconds : 0 };
  };
}

async function route(db, http, callerUid, input, nowMs = Date.now()) {
  if (!safeId(callerUid)) throw new MapsError('unauthenticated', 'sign in first');
  const from = point(input && input.from);
  const to = point(input && input.to);
  if (!from || !to) throw new MapsError('invalid-argument', 'places');
  const ref = db.collection('route_cache').doc(cacheKey(from, to));
  const hit = await ref.get();
  if (hit.exists) {
    const d = hit.data();
    const at = d.at && typeof d.at.toMillis === 'function' ? d.at.toMillis() : d.at instanceof Date ? d.at.getTime() : 0;
    if (Number.isSafeInteger(d.meters) && nowMs - at < CACHE_DAYS * 86400000) return { meters: d.meters, seconds: d.seconds || 0, cached: true };
  }
  // Only a request that really goes to Google uses up the person's daily turns.
  await consumeQuota(db, callerUid, nowMs);
  const r = await http(from, to);
  await ref.set({ meters: r.meters, seconds: r.seconds, at: new Date(nowMs), expireAt: new Date(nowMs + (CACHE_DAYS + 5) * 86400000) });
  return { meters: r.meters, seconds: r.seconds, cached: false };
}

module.exports = { route, consumeQuota, googleRoutesHttp, cacheKey, dayKey, MapsError, BOUNDS, DEFAULT_PER_USER, DEFAULT_TOTAL };
