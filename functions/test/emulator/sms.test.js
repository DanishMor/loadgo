'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { emergencySms, onNotificationSms, sendTemplate, msisdn, msg91Http, SmsError } = require('../../src/sms');
const { QuotaError } = require('../../src/quota');

const TEMPLATES = { sos: 'tpl_sos_000001', tripStatus: 'tpl_trip_000001' };

test.beforeEach(async () => {
  await clearDb();
  const db = getDb();
  await db.collection('config').doc('sms').set({ templates: TEMPLATES });
  await db.collection('users').doc('u1').set({ phone: '+919876543210', emergencyContacts: [{ name: 'Mother', phone: '+919811111111' }, { name: 'Bad', phone: '12' }] });
  await db.collection('users').doc('u2').set({ phone: '+919822222222', fcmTokens: ['t'.repeat(40)] });
  await db.collection('users').doc('u3').set({ phone: '+919833333333', notificationPrefs: { bookingUpdates: false } });
  await db.collection('users').doc('u4').set({ role: 'customer' });
});

const recorder = (calls = []) => async (req) => {
  calls.push(req);
  return { messageId: 'm' + calls.length };
};
async function refused(p, code) {
  await assert.rejects(p, (e) => (e instanceof SmsError || e instanceof QuotaError) && e.code === code, `expected ${code}`);
}

test('numbers: India mobile numbers only, in the +91 form', () => {
  assert.equal(msisdn('+919876543210'), '919876543210');
  assert.equal(msisdn('+91 98765 43210'), '919876543210');
  for (const bad of ['9876543210', '+14155550123', '+911234567890', '+9198765', '', null, 5, '+919876543210; rm']) assert.equal(msisdn(bad), null, String(bad));
});

test('emergency SMS goes only to a saved contact, through the sos template, with the text as a variable', async () => {
  const calls = [];
  const r = await emergencySms(getDb(), recorder(calls), 'u1', { to: '+919811111111', text: 'I need help near Jaipur' });
  assert.equal(r.messageId, 'm1');
  assert.deepEqual(calls[0], { mobile: '919811111111', templateId: 'tpl_sos_000001', vars: { var1: 'I need help near Jaipur' } });
});

test('emergency SMS: a stranger number, a bad number, empty or huge text and a signed-out caller are refused and nothing is sent', async () => {
  const calls = [];
  const send = recorder(calls);
  await refused(emergencySms(getDb(), send, 'u1', { to: '+919899999999', text: 'hi' }), 'permission-denied');
  await refused(emergencySms(getDb(), send, 'u1', { to: '12', text: 'hi' }), 'invalid-argument');
  await refused(emergencySms(getDb(), send, 'u1', { to: '+919811111111', text: '   ' }), 'invalid-argument');
  await refused(emergencySms(getDb(), send, 'u1', { to: '+919811111111', text: 'x'.repeat(481) }), 'invalid-argument');
  await refused(emergencySms(getDb(), send, undefined, { to: '+919811111111', text: 'hi' }), 'unauthenticated');
  await refused(emergencySms(getDb(), send, 'u4', { to: '+919811111111', text: 'hi' }), 'permission-denied');
  assert.equal(calls.length, 0);
});

test('no template set means nothing is sent and no quota is used', async () => {
  await getDb().collection('config').doc('sms').set({ templates: {} });
  const calls = [];
  await refused(emergencySms(getDb(), recorder(calls), 'u1', { to: '+919811111111', text: 'hi' }), 'failed-precondition');
  assert.equal(calls.length, 0);
  assert.equal((await getDb().collection('quota_usage').get()).size, 0);
});

test('a person has a daily limit; the total limit stops everybody', async () => {
  await getDb().collection('config').doc('sms').set({ templates: TEMPLATES, perUserPerDay: 2, totalPerDay: 3 });
  const calls = [];
  const send = recorder(calls);
  const go = (uid) => emergencySms(getDb(), send, uid, { to: '+919811111111', text: 'hi' });
  await getDb().collection('users').doc('u5').set({ emergencyContacts: [{ phone: '+919811111111' }] });
  await go('u1');
  await go('u1');
  await refused(go('u1'), 'resource-exhausted');
  await go('u5');
  await refused(go('u5'), 'resource-exhausted'); // the total of 3 is used up
  assert.equal(calls.length, 3);
});

test('trip SMS: only for someone with a phone, no push token and booking updates on', async () => {
  const calls = [];
  const send = recorder(calls);
  const note = (userId, type = 'load_accepted') => ({ userId, type, relatedId: 'abc123booking' });
  assert.deepEqual(await onNotificationSms(getDb(), send, note('u1')), { sent: true });
  assert.deepEqual(calls[0], { mobile: '919876543210', templateId: 'tpl_trip_000001', vars: { var1: 'Your truck is booked', var2: 'OOKING' } });
  assert.equal((await onNotificationSms(getDb(), send, note('u2'))).reason, 'has_push');
  assert.equal((await onNotificationSms(getDb(), send, note('u3'))).reason, 'switched_off');
  assert.equal((await onNotificationSms(getDb(), send, note('u4'))).reason, 'no_phone');
  assert.equal((await onNotificationSms(getDb(), send, note('u1', 'chat_message'))).reason, 'skipped');
  assert.equal((await onNotificationSms(getDb(), send, { type: 'load_accepted' })).reason, 'skipped');
  assert.equal((await onNotificationSms(getDb(), send, null)).reason, 'skipped');
  assert.equal(calls.length, 1);
});

test('a device token under users/{uid}/devices also counts as push', async () => {
  await getDb().collection('users').doc('u1').collection('devices').doc('d1').set({ fcmToken: 'x'.repeat(40) });
  const calls = [];
  assert.equal((await onNotificationSms(getDb(), recorder(calls), { userId: 'u1', type: 'trip_status', relatedId: 'b1' })).reason, 'has_push');
  assert.equal(calls.length, 0);
});

test('trip SMS: the daily limit and a missing template are calm, not errors', async () => {
  await getDb().collection('config').doc('sms').set({ templates: TEMPLATES, perUserPerDay: 1 });
  const send = recorder();
  const n = { userId: 'u1', type: 'trip_status', relatedId: 'b1' };
  assert.equal((await onNotificationSms(getDb(), send, n)).sent, true);
  assert.equal((await onNotificationSms(getDb(), send, n)).reason, 'resource-exhausted');
  await getDb().collection('config').doc('sms').set({ templates: {} });
  assert.equal((await onNotificationSms(getDb(), send, n)).reason, 'failed-precondition');
});

test('variables: only var1 to var5, short, on one line', async () => {
  const calls = [];
  await sendTemplate(getDb(), recorder(calls), { uid: 'u1', to: '+919876543210', template: 'sos', vars: { var1: 'a\nb', evil: 'x', var9: 'y', var2: 'z'.repeat(500) } });
  assert.deepEqual(Object.keys(calls[0].vars).sort(), ['var1', 'var2']);
  assert.equal(calls[0].vars.var1, 'a b');
  assert.equal(calls[0].vars.var2.length, 160);
});

test('the MSG91 request carries the template, the number and the variables; errors are calm', async () => {
  let seen;
  const ok = async (url, init) => {
    seen = { url, init };
    return { ok: true, status: 200, json: async () => ({ type: 'success', message: 'req_123' }) };
  };
  const r = await msg91Http('test_key_not_real', ok)({ mobile: '919876543210', templateId: 'tpl', vars: { var1: 'a' } });
  assert.equal(r.messageId, 'req_123');
  assert.equal(seen.init.headers.authkey, 'test_key_not_real');
  assert.deepEqual(JSON.parse(seen.init.body), { template_id: 'tpl', short_url: '0', recipients: [{ mobiles: '919876543210', var1: 'a' }] });
  const refusedHttp = async () => ({ ok: true, status: 200, json: async () => ({ type: 'error', message: 'bad' }) });
  await assert.rejects(msg91Http('k', refusedHttp)({ mobile: '1', templateId: 't', vars: {} }), (e) => e.code === 'failed-precondition');
  const busy = async () => ({ ok: false, status: 503, json: async () => ({}) });
  await assert.rejects(msg91Http('k', busy)({ mobile: '1', templateId: 't', vars: {} }), (e) => e.code === 'unavailable');
  const down = async () => { throw new Error('net'); };
  await assert.rejects(msg91Http('k', down)({ mobile: '1', templateId: 't', vars: {} }), (e) => e.code === 'unavailable');
});
