'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { isRule, ruleAccepts, pickBid, currentWave } = require('../../src/dispatch');

const RULE = { maxPaise: 100000, minRating: 4, verifiedOnly: true };
const ts = (ms) => ({ toMillis: () => ms });

test('a rule must have a whole positive limit, a rating from 0 to 5 and a yes/no for verified', () => {
  assert.ok(isRule(RULE));
  for (const bad of [null, 'x', {}, { ...RULE, maxPaise: 0 }, { ...RULE, maxPaise: 1.5 }, { ...RULE, maxPaise: 100000001 }, { ...RULE, minRating: 6 }, { ...RULE, minRating: -1 }, { ...RULE, verifiedOnly: 'yes' }]) {
    assert.equal(isRule(bad), false, JSON.stringify(bad));
  }
});

test('the rule accepts like the app: price at most the limit, rating at least the minimum, verified when asked', () => {
  assert.equal(ruleAccepts(RULE, { pricePaise: 100000, rating: 4, verified: true }), true);
  assert.equal(ruleAccepts(RULE, { pricePaise: 100001, rating: 5, verified: true }), false);
  assert.equal(ruleAccepts(RULE, { pricePaise: 90000, rating: 3.9, verified: true }), false);
  assert.equal(ruleAccepts(RULE, { pricePaise: 90000, rating: 5, verified: false }), false);
  assert.equal(ruleAccepts(RULE, { pricePaise: 90000, rating: null, verified: true }), false);
  assert.equal(ruleAccepts({ maxPaise: 10, minRating: 0, verifiedOnly: false }, { pricePaise: 5 }), true);
  assert.equal(ruleAccepts({ maxPaise: 10 }, { pricePaise: 5 }), false, 'a damaged rule never accepts');
  assert.equal(ruleAccepts(RULE, { pricePaise: 0, rating: 5, verified: true }), false);
});

test('pickBid takes the cheapest pending bid that fits, the earliest on a tie, and ignores other states', () => {
  const trust = { a: { rating: 4.5, verified: true }, b: { rating: 4.9, verified: true }, c: { rating: 3.0, verified: true }, d: { rating: 4.5, verified: false } };
  const offers = [
    { id: 'a', driverId: 'a', pricePaise: 90000, status: 'pending', createdAt: ts(2) },
    { id: 'b', driverId: 'b', pricePaise: 90000, status: 'pending', createdAt: ts(1) },
    { id: 'c', driverId: 'c', pricePaise: 50000, status: 'pending', createdAt: ts(3) },
    { id: 'd', driverId: 'd', pricePaise: 40000, status: 'pending', createdAt: ts(4) },
    { id: 'e', driverId: 'a', pricePaise: 10000, status: 'withdrawn', createdAt: ts(5) },
  ];
  assert.equal(pickBid(RULE, offers, (id) => trust[id]).id, 'b');
  assert.equal(pickBid({ ...RULE, maxPaise: 1000 }, offers, (id) => trust[id]), null);
  assert.equal(pickBid(RULE, [], () => null), null);
  assert.equal(pickBid(RULE, offers, () => null), null, 'no trust data: a rating rule cannot be met');
  assert.equal(pickBid({ ...RULE, verifiedOnly: false, minRating: 0 }, offers, () => null).id, 'd', 'the cheapest of all when no rating is asked');
});

test('company bids count as verified', () => {
  const o = [{ id: 'x', driverId: 'x', pricePaise: 5000, status: 'pending', companyVerified: true, createdAt: ts(1) }];
  assert.equal(pickBid({ maxPaise: 9000, minRating: 0, verifiedOnly: true }, o, () => null).id, 'x');
});

test('the wave: first ring at once, then 30 s and 60 s, stalled after the accept time', () => {
  const t0 = 1_000_000;
  const w = (s, cfg) => currentWave(t0, t0 + s * 1000, cfg);
  assert.deepEqual(w(0), { wave: 0, stalled: false });
  assert.deepEqual(w(29), { wave: 0, stalled: false });
  assert.deepEqual(w(30), { wave: 1, stalled: false });
  assert.deepEqual(w(60), { wave: 2, stalled: false });
  assert.deepEqual(w(89), { wave: 2, stalled: false });
  assert.deepEqual(w(90), { wave: 2, stalled: true });
  assert.deepEqual(w(-10), { wave: 0, stalled: false });
  assert.deepEqual(w(100, { ringDelaySeconds: [0, 10], acceptSeconds: 45 }), { wave: 1, stalled: true });
});
