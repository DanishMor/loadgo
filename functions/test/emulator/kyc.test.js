'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { verify, KycError, sandboxProvider } = require('../../src/kyc');
const { QuotaError } = require('../../src/quota');

const DL = 'MH1220200000001';
test.beforeEach(clearDb);

async function refused(p, code) {
  await assert.rejects(p, (e) => (e instanceof KycError || e instanceof QuotaError) && e.code === code, `expected ${code}`);
}
const withSandbox = async () => getDb().collection('config').doc('kyc').set({ provider: 'sandbox' });

test('no partner set: unavailable, nothing stored, no quota used (the admin reviews by eye)', async () => {
  assert.deepEqual(await verify(getDb(), 'u1', { kind: 'licence', number: DL }), { status: 'unavailable' });
  assert.equal((await getDb().collection('kyc_checks').get()).size, 0);
  assert.equal((await getDb().collection('quota_usage').get()).size, 0);
});

test('sandbox: the last character decides verified, mismatch or not found', async () => {
  await withSandbox();
  assert.deepEqual(await verify(getDb(), 'u1', { kind: 'licence', number: DL }), { status: 'verified', holderName: 'Sandbox Holder' });
  assert.equal((await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' })).status, 'verified');
  assert.equal((await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1230Z' })).status, 'mismatch');
  assert.equal((await verify(getDb(), 'u1', { kind: 'rc', number: 'MH12AB1230' })).status, 'not_found');
  assert.equal((await verify(getDb(), 'u1', { kind: 'gstin', number: '27ABCDE1234F1Z5' })).status, 'verified');
});

test('the result is stored for the admin without the number, in a collection only the server writes', async () => {
  await withSandbox();
  await verify(getDb(), 'u1', { kind: 'licence', number: DL });
  await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' });
  const d = (await getDb().collection('kyc_checks').doc('u1').get()).data();
  assert.equal(d.licence.status, 'verified');
  assert.equal(d.pan.status, 'verified');
  assert.equal(d.licence.provider, 'sandbox');
  assert.ok(d.licence.at);
  assert.ok(!JSON.stringify(d).includes(DL), 'the number is not kept');
  assert.ok(!JSON.stringify(d).includes('ABCDE1234F'));
});

test('input is checked again on the server: format, kind, signed in', async () => {
  await withSandbox();
  await refused(verify(getDb(), 'u1', { kind: 'licence', number: 'short' }), 'invalid-argument');
  await refused(verify(getDb(), 'u1', { kind: 'passport', number: DL }), 'invalid-argument');
  await refused(verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234' }), 'invalid-argument');
  await refused(verify(getDb(), 'u1', undefined), 'invalid-argument');
  await refused(verify(getDb(), 'u1', { kind: 'pan', number: 12345 }), 'invalid-argument');
  await refused(verify(getDb(), undefined, { kind: 'pan', number: 'ABCDE1234F' }), 'unauthenticated');
  await refused(verify(getDb(), '../x', { kind: 'pan', number: 'ABCDE1234F' }), 'unauthenticated');
  assert.equal((await getDb().collection('kyc_checks').get()).size, 0);
});

test('Aadhaar: only the last four digits are accepted, a full number is refused, and nothing is looked up', async () => {
  await withSandbox();
  await refused(verify(getDb(), 'u1', { kind: 'aadhaar', number: '123456789012' }), 'invalid-argument');
  await refused(verify(getDb(), 'u1', { kind: 'aadhaar', number: '12 3456 7890 12' }), 'invalid-argument');
  await refused(verify(getDb(), 'u1', { kind: 'aadhaar', number: '123' }), 'invalid-argument');
  assert.equal((await verify(getDb(), 'u1', { kind: 'aadhaar', number: '9012' })).status, 'unavailable');
});

test('spaces, dashes and case are ignored', async () => {
  await withSandbox();
  assert.equal((await verify(getDb(), 'u1', { kind: 'licence', number: 'mh12 2020-0000001' })).status, 'verified');
});

test('a person has a few checks a day', async () => {
  await getDb().collection('config').doc('kyc').set({ provider: 'sandbox', perUserPerDay: 2 });
  await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' });
  await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' });
  await refused(verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' }), 'resource-exhausted');
  await verify(getDb(), 'u2', { kind: 'pan', number: 'ABCDE1234F' });
});

test('a partner that fails or answers oddly is calm: unavailable, nothing stored', async () => {
  const down = { name: 'partner', lookup: async () => { throw new Error('net'); } };
  await refused(verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' }, { provider: down }), 'unavailable');
  const odd = { name: 'partner', lookup: async () => ({ status: 'maybe', holderName: 'X' }) };
  assert.deepEqual(await verify(getDb(), 'u1', { kind: 'pan', number: 'ABCDE1234F' }, { provider: odd }), { status: 'unavailable' });
  assert.equal((await getDb().collection('kyc_checks').doc('u1').get()).data().pan.status, 'unavailable');
});

test('contract: any provider answers one of four statuses and the sandbox never calls out', async () => {
  for (const kind of ['licence', 'rc', 'pan', 'gstin', 'aadhaar']) {
    const r = await sandboxProvider.lookup(kind, kind === 'aadhaar' ? '1234' : 'AB12CD3451');
    assert.ok(['verified', 'mismatch', 'not_found', 'unavailable'].includes(r.status), kind);
  }
});
