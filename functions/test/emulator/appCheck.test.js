'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { clearFlagCache } = require('../../src/common');
const { guard, AppCheckError } = require('../../src/appCheck');

test.beforeEach(async () => {
  await clearDb();
  clearFlagCache();
});

const fakeLog = () => {
  const lines = [];
  return { lines, warn: (m) => lines.push(m) };
};

test('a call with a valid App Check token passes and writes no warning', async () => {
  const log = fakeLog();
  assert.deepEqual(await guard(getDb(), { app: { appId: 'x' } }, 'mapsRoute', log), { checked: true });
  assert.equal(log.lines.length, 0);
});

test('monitor mode: a call without a token passes but is counted in the log, with no user data', async () => {
  const log = fakeLog();
  const r = await guard(getDb(), { auth: { uid: 'secret_uid' }, data: { number: 'SECRET' } }, 'kycVerify', log);
  assert.deepEqual(r, { checked: false });
  assert.equal(log.lines.length, 1);
  assert.deepEqual(JSON.parse(log.lines[0]), { event: 'app_check_missing', fn: 'kycVerify' });
  assert.ok(!log.lines[0].includes('secret'));
});

test('enforce mode: a call without a token is refused; with a token it still passes', async () => {
  await getDb().collection('config').doc('features').set({ flags: { appCheckEnforce: true } });
  const log = fakeLog();
  await assert.rejects(guard(getDb(), {}, 'smsSend', log), (e) => e instanceof AppCheckError && e.code === 'failed-precondition');
  await assert.rejects(guard(getDb(), undefined, 'smsSend', log), AppCheckError);
  assert.deepEqual(await guard(getDb(), { app: { appId: 'x' } }, 'smsSend', log), { checked: true });
});

test('any other value than true leaves it in monitor mode', async () => {
  await getDb().collection('config').doc('features').set({ flags: { appCheckEnforce: 'yes' } });
  assert.deepEqual(await guard(getDb(), {}, 'payment', fakeLog()), { checked: false });
});

test('a very long function name cannot flood the log', async () => {
  const log = fakeLog();
  await guard(getDb(), {}, 'x'.repeat(500), log);
  assert.equal(JSON.parse(log.lines[0]).fn.length, 40);
});
