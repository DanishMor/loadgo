'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { route, cacheKey, dayKey, googleRoutesHttp, MapsError } = require('../../src/maps');

const DELHI = { lat: 28.6139, lng: 77.209 };
const JAIPUR = { lat: 26.9124, lng: 75.7873 };

test.beforeEach(clearDb);

const fakeHttp = (calls = []) => async (from, to) => {
  calls.push({ from, to });
  return { meters: 281000, seconds: 18000 };
};
async function refused(p, code) {
  await assert.rejects(p, (e) => e instanceof MapsError && e.code === code, `expected ${code}`);
}

test('the same pair of places (to about 1 km) is paid for once and then served from the cache', async () => {
  const calls = [];
  const a = await route(getDb(), fakeHttp(calls), 'u1', { from: DELHI, to: JAIPUR });
  assert.deepEqual(a, { meters: 281000, seconds: 18000, cached: false });
  const b = await route(getDb(), fakeHttp(calls), 'u2', { from: { lat: 28.6141, lng: 77.2092 }, to: JAIPUR });
  assert.equal(b.cached, true);
  assert.equal(calls.length, 1);
  assert.equal(b.meters, 281000);
});

test('a cached answer older than 30 days is asked again', async () => {
  const calls = [];
  await route(getDb(), fakeHttp(calls), 'u1', { from: DELHI, to: JAIPUR });
  await route(getDb(), fakeHttp(calls), 'u1', { from: DELHI, to: JAIPUR }, Date.now() + 31 * 86400000);
  assert.equal(calls.length, 2);
});

test('each person has a few turns a day; cached answers do not use them', async () => {
  await getDb().collection('config').doc('mapsLimits').set({ perUserPerDay: 2 });
  const calls = [];
  const places = [28.1, 28.2, 28.3];
  for (const lat of places.slice(0, 2)) await route(getDb(), fakeHttp(calls), 'u1', { from: { lat, lng: 77 }, to: JAIPUR });
  await refused(route(getDb(), fakeHttp(calls), 'u1', { from: { lat: 28.3, lng: 77 }, to: JAIPUR }), 'resource-exhausted');
  assert.equal(calls.length, 2, 'the refused one was not sent to Google');
  // the same pair again is a cache hit and still works for the person with no turns left
  assert.equal((await route(getDb(), fakeHttp(calls), 'u1', { from: { lat: 28.1, lng: 77 }, to: JAIPUR })).cached, true);
  // another person is not affected
  await route(getDb(), fakeHttp(calls), 'u2', { from: { lat: 28.3, lng: 77 }, to: JAIPUR });
  // the next day the turns are back
  await route(getDb(), fakeHttp(calls), 'u1', { from: { lat: 28.4, lng: 77 }, to: JAIPUR }, Date.now() + 86400000);
});

test('a total cap for everybody stops a runaway day', async () => {
  await getDb().collection('config').doc('mapsLimits').set({ perUserPerDay: 100, totalPerDay: 3 });
  const calls = [];
  for (let i = 0; i < 3; i++) await route(getDb(), fakeHttp(calls), `u${i}`, { from: { lat: 20 + i, lng: 77 }, to: JAIPUR });
  await refused(route(getDb(), fakeHttp(calls), 'u9', { from: { lat: 30, lng: 77 }, to: JAIPUR }), 'resource-exhausted');
  assert.equal(calls.length, 3);
});

test('limits are read as whole numbers only; junk falls back to the defaults', async () => {
  await getDb().collection('config').doc('mapsLimits').set({ perUserPerDay: 'many', totalPerDay: -5 });
  for (let i = 0; i < 20; i++) await route(getDb(), fakeHttp(), 'u1', { from: { lat: 10 + i * 0.5, lng: 77 }, to: JAIPUR });
  await refused(route(getDb(), fakeHttp(), 'u1', { from: { lat: 35, lng: 77 }, to: JAIPUR }), 'resource-exhausted');
});

test('places outside India, not numbers, missing or a stranger are refused before anything is paid', async () => {
  const calls = [];
  await refused(route(getDb(), fakeHttp(calls), 'u1', { from: { lat: 51.5, lng: -0.1 }, to: JAIPUR }), 'invalid-argument');
  await refused(route(getDb(), fakeHttp(calls), 'u1', { from: { lat: '28', lng: 77 }, to: JAIPUR }), 'invalid-argument');
  await refused(route(getDb(), fakeHttp(calls), 'u1', { from: { lat: NaN, lng: 77 }, to: JAIPUR }), 'invalid-argument');
  await refused(route(getDb(), fakeHttp(calls), 'u1', { from: DELHI }), 'invalid-argument');
  await refused(route(getDb(), fakeHttp(calls), 'u1', undefined), 'invalid-argument');
  await refused(route(getDb(), fakeHttp(calls), undefined, { from: DELHI, to: JAIPUR }), 'unauthenticated');
  await refused(route(getDb(), fakeHttp(calls), '../x', { from: DELHI, to: JAIPUR }), 'unauthenticated');
  assert.equal(calls.length, 0);
  assert.equal((await getDb().collection('maps_usage').get()).size, 0);
});

test('Google refusing or being down is a calm error and nothing is cached', async () => {
  const down = async () => { throw new MapsError('unavailable', 'maps busy'); };
  await refused(route(getDb(), down, 'u1', { from: DELHI, to: JAIPUR }), 'unavailable');
  assert.equal((await getDb().collection('route_cache').get()).size, 0);
});

test('cache keys and day keys are stable', () => {
  assert.equal(cacheKey(DELHI, JAIPUR), cacheKey({ lat: 28.6101, lng: 77.2099 }, { lat: 26.9101, lng: 75.7901 }));
  assert.notEqual(cacheKey(DELHI, JAIPUR), cacheKey(JAIPUR, DELHI));
  assert.equal(dayKey(Date.UTC(2026, 9, 16, 20, 0)), '2026-10-17', 'the India date, after 18:30 UTC it is already tomorrow');
});

test('the Google request asks only for distance and time and parses the answer', async () => {
  let seen;
  const fetchImpl = async (url, init) => {
    seen = { url, init };
    return { ok: true, status: 200, json: async () => ({ routes: [{ distanceMeters: 1234, duration: '567s' }] }) };
  };
  const r = await googleRoutesHttp('test_key_not_real', fetchImpl)(DELHI, JAIPUR);
  assert.deepEqual(r, { meters: 1234, seconds: 567 });
  assert.equal(seen.init.headers['X-Goog-FieldMask'], 'routes.distanceMeters,routes.duration');
  assert.equal(JSON.parse(seen.init.body).travelMode, 'DRIVE');
  const none = async () => ({ ok: true, status: 200, json: async () => ({}) });
  await assert.rejects(googleRoutesHttp('k', none)(DELHI, JAIPUR), (e) => e.code === 'not-found');
  const busy = async () => ({ ok: false, status: 503, json: async () => ({}) });
  await assert.rejects(googleRoutesHttp('k', busy)(DELHI, JAIPUR), (e) => e.code === 'unavailable');
  const offline = async () => { throw new Error('x'); };
  await assert.rejects(googleRoutesHttp('k', offline)(DELHI, JAIPUR), (e) => e.code === 'unavailable');
});
