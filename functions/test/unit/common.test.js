'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { FLAGS, flagOn, readFlags, clearFlagCache, paise, text, safeId, REGION } = require('../../src/common');

// A tiny stand-in for Firestore: db.collection('config').doc('features').get()
function fakeDb(data, { throws = false } = {}) {
  let reads = 0;
  const db = {
    reads: () => reads,
    collection: () => ({
      doc: () => ({
        get: async () => {
          reads++;
          if (throws) throw new Error('offline');
          return { exists: data !== undefined, data: () => data };
        },
      }),
    }),
  };
  return db;
}

test.beforeEach(() => clearFlagCache());

test('the region is Mumbai', () => assert.equal(REGION, 'asia-south1'));

test('every server feature is off when the document is missing, empty or unreadable', async () => {
  for (const db of [fakeDb(undefined), fakeDb({}), fakeDb({ flags: null }), fakeDb({ flags: 'x' }), fakeDb({}, { throws: true })]) {
    clearFlagCache();
    for (const f of FLAGS) assert.equal(await flagOn(db, f), false, f);
  }
});

test('only an explicit true turns a feature on; other values and unknown names stay off', async () => {
  const db = fakeDb({ flags: { serverLimits: true, serverChatScan: 'true', serverCredits: 1, serverTrust: false, notAFlag: true } });
  assert.equal(await flagOn(db, 'serverLimits'), true);
  assert.equal(await flagOn(db, 'serverChatScan'), false);
  assert.equal(await flagOn(db, 'serverCredits'), false);
  assert.equal(await flagOn(db, 'serverTrust'), false);
  assert.equal(await flagOn(db, 'notAFlag'), false, 'a name outside the list is always off');
});

test('the switches are cached for 30 seconds', async () => {
  const db = fakeDb({ flags: { serverJobs: true } });
  await flagOn(db, 'serverJobs', 1000);
  await flagOn(db, 'serverJobs', 20000);
  assert.equal(db.reads(), 1);
  await readFlags(db, 40000);
  assert.equal(db.reads(), 2);
});

test('paise, text and safeId never throw', () => {
  assert.equal(paise(12), 12);
  for (const v of [null, undefined, '5', 1.5, NaN, Infinity, 2 ** 60, {}, []]) assert.equal(paise(v), 0, String(v));
  assert.equal(text('abc', 2), 'ab');
  assert.equal(text(5), '');
  assert.equal(safeId('abc_DEF-123'), 'abc_DEF-123');
  for (const v of ['a/b', '', 'x'.repeat(129), 'a b', null, 5, '../x']) assert.equal(safeId(v), null, String(v));
});
