'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { flagOn, clearFlagCache } = require('../../src/common');

test.beforeEach(async () => {
  await clearDb();
  clearFlagCache();
});

test('the emulator is reachable and starts empty', async () => {
  const db = getDb();
  assert.equal((await db.collection('users').get()).size, 0);
  await db.collection('users').doc('u1').set({ name: 'Asha' });
  assert.equal((await db.collection('users').doc('u1').get()).data().name, 'Asha');
});

test('flags read from config/features in a real Firestore: off until the admin switches them on', async () => {
  const db = getDb();
  assert.equal(await flagOn(db, 'serverLimits'), false);
  clearFlagCache();
  await db.collection('config').doc('features').set({ pilotMode: true, flags: { serverLimits: true } });
  assert.equal(await flagOn(db, 'serverLimits'), true);
});
