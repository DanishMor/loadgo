'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { countCells } = require('../../src/demand');
const { currentWave, headStartSeconds } = require('../../src/dispatch');

// E36: open-load counts per pickup area, and the Black-tier head start in dispatch waves.
test('cells: counted by the first 4 geohash characters; junk skipped', () => {
  assert.deepEqual(countCells([
    { pickupGeohash: 'te7ud1x' },
    { pickupGeohash: 'TE7UZ' },
    { pickupGeohash: 'te7v' },
    { pickupGeohash: 'ail!' },
    { pickupGeohash: 7 },
    {},
    null,
  ]), { te7u: 2, te7v: 1 });
});

test('head start only for the black tier, from config, capped at 120 seconds', () => {
  assert.equal(headStartSeconds('black', {}), 0);
  assert.equal(headStartSeconds('black', { blackHeadStartSeconds: 30 }), 30);
  assert.equal(headStartSeconds('black', { blackHeadStartSeconds: 900 }), 120);
  assert.equal(headStartSeconds('black', { blackHeadStartSeconds: -5 }), 0);
  assert.equal(headStartSeconds('gold', { blackHeadStartSeconds: 30 }), 0);
  assert.equal(headStartSeconds(null, { blackHeadStartSeconds: 30 }), 0);
});

test('a head start opens the next wave sooner; without one nothing changes', () => {
  const cfg = { ringDelaySeconds: [0, 60, 120], acceptSeconds: 30 };
  const t0 = 1_000_000;
  assert.equal(currentWave(t0, t0 + 40_000, cfg).wave, 0);
  assert.equal(currentWave(t0, t0 + 40_000, cfg, 0).wave, 0);
  assert.equal(currentWave(t0, t0 + 40_000, cfg, 30).wave, 1);
  assert.deepEqual(currentWave(t0, t0 + 40_000, cfg, 'x'), currentWave(t0, t0 + 40_000, cfg));
});
