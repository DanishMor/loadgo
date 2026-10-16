'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { getDb, clearDb } = require('../helpers');
const { setRiskTier, decideDriver, requireStaff, serverStatus, ActionError } = require('../../src/adminActions');

const NOW = Date.UTC(2026, 9, 15, 12, 0, 0);

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('admins').doc('boss').set({ createdBy: 'console' }); // no role: super
  await db.collection('admins').doc('ops1').set({ role: 'ops' });
  await db.collection('admins').doc('ver1').set({ role: 'verifier' });
  await db.collection('admins').doc('sup1').set({ role: 'support' });
  await db.collection('admins').doc('fin1').set({ role: 'finance' });
  await db.collection('admins').doc('odd').set({ role: 'wizard' });
  await db.collection('users').doc('d1').set({ driverName: 'Ravi', verificationStatus: 'pending', verified: false });
});

async function denied(promise, code) {
  await assert.rejects(promise, (e) => e instanceof ActionError && e.code === code, `expected ${code}`);
}

test('a missing role means super; an unknown role also means super (as the rules do)', async () => {
  const db = getDb();
  assert.equal(await requireStaff(db, 'boss', ['super']), 'super');
  assert.equal(await requireStaff(db, 'odd', ['super']), 'super');
});

test('who may set a risk tier: super and ops; support, verifier, finance, strangers and signed-out callers may not', async () => {
  const db = getDb();
  await setRiskTier(db, 'boss', { uid: 'd1', tier: 'review', reason: 'many cancels' }, NOW);
  await setRiskTier(db, 'ops1', { uid: 'd1', tier: 'restricted', reason: 'fraud report' }, NOW);
  for (const who of ['sup1', 'ver1', 'fin1']) await denied(setRiskTier(db, who, { uid: 'd1', tier: 'banned' }, NOW), 'permission-denied');
  await denied(setRiskTier(db, 'stranger', { uid: 'd1', tier: 'banned' }, NOW), 'permission-denied');
  await denied(setRiskTier(db, null, { uid: 'd1', tier: 'banned' }, NOW), 'unauthenticated');
  assert.equal((await db.collection('users').doc('d1').get()).data().riskTier, 'restricted');
});

test('the tier change writes the fields the rules expect and one audit line with the real actor', async () => {
  const db = getDb();
  const r = await setRiskTier(db, 'ops1', { uid: 'd1', tier: 'suspended', reason: '  Repeated no-shows  ' }, NOW);
  assert.deepEqual(r, { ok: true, uid: 'd1', tier: 'suspended' });
  const u = (await db.collection('users').doc('d1').get()).data();
  assert.equal(u.riskTier, 'suspended');
  assert.equal(u.riskReason, 'Repeated no-shows');
  assert.equal(u.riskUpdatedAt.toMillis(), NOW);
  assert.equal(u.driverName, 'Ravi', 'nothing else changed');
  const audits = (await db.collection('audit_events').get()).docs.map((d) => d.data());
  assert.equal(audits.length, 1);
  assert.equal(audits[0].type, 'risk_change');
  assert.equal(audits[0].actorId, 'ops1');
  assert.equal(audits[0].targetId, 'd1');
  assert.equal(audits[0].data.tier, 'suspended');
  assert.equal(audits[0].data.via, 'server');
});

test('bad input is refused before anything is written', async () => {
  const db = getDb();
  await denied(setRiskTier(db, 'boss', { uid: 'd1', tier: 'god' }, NOW), 'invalid-argument');
  await denied(setRiskTier(db, 'boss', { uid: 'a/b', tier: 'normal' }, NOW), 'invalid-argument');
  await denied(setRiskTier(db, 'boss', null, NOW), 'invalid-argument');
  await denied(setRiskTier(db, 'boss', { uid: 'd1', tier: 'normal', reason: 'x'.repeat(201) }, NOW), 'invalid-argument');
  await denied(setRiskTier(db, 'boss', { uid: 'ghost', tier: 'normal' }, NOW), 'not-found');
  assert.equal((await db.collection('audit_events').get()).size, 0);
  assert.equal((await db.collection('users').doc('d1').get()).data().riskTier, undefined);
});

test('who may decide a driver: super and verifier only', async () => {
  const db = getDb();
  await decideDriver(db, 'ver1', { uid: 'd1', status: 'approved' }, NOW);
  await decideDriver(db, 'boss', { uid: 'd1', status: 'pending' }, NOW);
  for (const who of ['ops1', 'sup1', 'fin1', 'stranger']) await denied(decideDriver(db, who, { uid: 'd1', status: 'approved' }, NOW), 'permission-denied');
});

test('approval sets verified and the meta; rejection needs a known reason and keeps an optional short note', async () => {
  const db = getDb();
  await decideDriver(db, 'ver1', { uid: 'd1', status: 'approved' }, NOW);
  let u = (await db.collection('users').doc('d1').get()).data();
  assert.equal(u.verified, true);
  assert.equal(u.verificationStatus, 'approved');
  assert.equal(u.verificationMeta.source, 'manual_review');
  assert.equal(u.verificationMeta.by, 'ver1');
  assert.equal(u.verificationMeta.status, 'approved');
  assert.equal(u.verificationMeta.at.toMillis(), NOW);
  assert.equal(u.verificationMeta.reason, undefined);

  await decideDriver(db, 'ver1', { uid: 'd1', status: 'rejected', reason: 'rc_mismatch', note: 'RC photo is of another truck' }, NOW);
  u = (await db.collection('users').doc('d1').get()).data();
  assert.equal(u.verified, false);
  assert.equal(u.verificationMeta.reason, 'rc_mismatch');
  assert.equal(u.verificationMeta.note, 'RC photo is of another truck');
  const types = (await db.collection('audit_events').get()).docs.map((d) => d.data().type);
  assert.deepEqual(types, ['verification', 'verification']);
});

test('a reason on an approval, an unknown reason, a long note or a note without a reason are refused', async () => {
  const db = getDb();
  await denied(decideDriver(db, 'ver1', { uid: 'd1', status: 'approved', reason: 'other' }, NOW), 'invalid-argument');
  await denied(decideDriver(db, 'ver1', { uid: 'd1', status: 'rejected', reason: 'because' }, NOW), 'invalid-argument');
  await denied(decideDriver(db, 'ver1', { uid: 'd1', status: 'rejected', reason: 'other', note: 'x'.repeat(121) }, NOW), 'invalid-argument');
  await denied(decideDriver(db, 'ver1', { uid: 'd1', status: 'pending', note: 'hello' }, NOW), 'invalid-argument');
  await denied(decideDriver(db, 'ver1', { uid: 'd1', status: 'maybe' }, NOW), 'invalid-argument');
  await denied(decideDriver(db, 'ver1', { uid: 'nobody', status: 'approved' }, NOW), 'not-found');
  assert.equal((await db.collection('audit_events').get()).size, 0);
});

test('the time stamps are the server time given, not anything from the caller', async () => {
  const db = getDb();
  await decideDriver(db, 'ver1', { uid: 'd1', status: 'approved', at: 1, by: 'someone-else', verified: false }, NOW);
  const u = (await db.collection('users').doc('d1').get()).data();
  assert.equal(u.verificationMeta.by, 'ver1');
  assert.equal(u.verificationMeta.at.toMillis(), NOW);
  assert.equal(u.verified, true);
  assert.ok(u.updatedAt instanceof Timestamp);
});

test('serverStatus: any staff role may ask, it works with every switch off, and shows only switch names', async () => {
  const db = getDb();
  const off = await serverStatus(db, 'sup1', NOW);
  assert.equal(off.ok, true);
  assert.equal(off.at, NOW);
  assert.equal(off.region, 'asia-south1');
  assert.ok(Object.keys(off.switches).length >= 11);
  assert.ok(Object.values(off.switches).every((v) => v === false));
  await db.collection('config').doc('features').set({ flags: { serverJobs: true, serverWallet: 'yes' } });
  require('../../src/common').clearFlagCache();
  const on = await serverStatus(db, 'fin1', NOW);
  assert.equal(on.switches.serverJobs, true);
  assert.equal(on.switches.serverWallet, false, 'only exactly true counts');
});

test('serverStatus: strangers and signed-out callers are refused', async () => {
  const db = getDb();
  await denied(serverStatus(db, 'nobody'), 'permission-denied');
  await denied(serverStatus(db, undefined), 'unauthenticated');
});
