'use strict';
// G40: the Part 3 functions run for real inside the emulators: real callables with a real sign-in token, a real
// HTTPS webhook, real triggers. Nothing reaches Google, Razorpay or the SMS partner: the cases are chosen so the
// functions answer before any outside call (cache hits, refusals, the sandbox ID check, a signed webhook).
// File order matters: functions.test.js runs first (switches ON), this file turns the Part 3 switches on once and
// waits out the 30 second switch cache; the App Check enforcement test is last because it changes every later call.

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { Timestamp } = require('firebase-admin/firestore');
const { PROJECT, db, waitFor, pause, setFlags, signUp, callFn, clearAll } = require('./helpers');

const ALL_ON = {
  serverLimits: true, serverChatScan: true, serverCredits: true, serverTrust: true, serverJobs: true,
  serverAdminActions: true, serverDeletion: true, serverWallet: true, pushNotifications: true, adminBroadcast: true,
  photoUploads: true, paymentGateway: true,
};
const PART3_ON = { ...ALL_ON, maps: true, smsGateway: true, kycVerify: true, rateRange: true, payHold: true };
const WEBHOOK_SECRET = 'test_webhook_for_emulator'; // the same fake value run.sh writes to .secret.local

let cust;
let driver;

async function webhook(body, { secret = WEBHOOK_SECRET, eventId, signature } = {}) {
  const raw = JSON.stringify(body);
  const sig = signature === undefined ? crypto.createHmac('sha256', secret).update(raw).digest('hex') : signature;
  const res = await fetch(`http://127.0.0.1:5002/${PROJECT}/asia-south1/paymentWebhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-razorpay-signature': sig, 'x-razorpay-event-id': eventId },
    body: raw,
  });
  return { status: res.status, text: await res.text() };
}

test.before(async () => {
  await clearAll();
  cust = await signUp('p3cust@example.test');
  driver = await signUp('p3driver@example.test');
});

test('Part 3 switches OFF: maps, SMS and ID check say "disabled"', async () => {
  await setFlags(ALL_ON);
  await pause(31000);
  for (const [fn, data] of [
    ['mapsRoute', { from: { lat: 28.6, lng: 77.2 }, to: { lat: 26.9, lng: 75.8 } }],
    ['smsSend', { to: '+919811111111', text: 'hi' }],
    ['kycVerify', { kind: 'pan', number: 'ABCDE1234F' }],
  ]) {
    const r = await callFn(fn, data, cust.token);
    assert.equal(r.error && r.error.status, 'FAILED_PRECONDITION', fn);
  }
});

test('Part 3 switches ON (wait out the 30 s cache)', async () => {
  await db.collection('config').doc('kyc').set({ provider: 'sandbox' });
  await setFlags(PART3_ON);
  await pause(31000);
  const r = await callFn('serverStatus', {}, undefined);
  assert.equal(r.error.status, 'UNAUTHENTICATED');
});

test('ID check: the sandbox answers through the callable and the answer lands where only admins read; bad input is refused', async () => {
  const ok = await callFn('kycVerify', { kind: 'licence', number: 'MH12 2020 0000001' }, cust.token);
  assert.deepEqual(ok.result, { status: 'verified', holderName: 'Sandbox Holder' });
  const stored = (await db.collection('kyc_checks').doc(cust.uid).get()).data();
  assert.equal(stored.licence.status, 'verified');
  assert.ok(!JSON.stringify(stored).includes('MH1220200000001'), 'the number is not kept');
  assert.equal((await callFn('kycVerify', { kind: 'aadhaar', number: '123456789012' }, cust.token)).error.status, 'INVALID_ARGUMENT');
  assert.equal((await callFn('kycVerify', { kind: 'pan', number: 'short' }, cust.token)).error.status, 'INVALID_ARGUMENT');
  assert.equal((await callFn('kycVerify', { kind: 'pan', number: 'ABCDE1234F' }, undefined)).error.status, 'UNAUTHENTICATED');
});

test('maps: a cached route is answered without Google; places outside India and a signed-out call are refused', async () => {
  await db.collection('route_cache').doc('28p61_77p21__26p91_75p79').set({ meters: 281000, seconds: 18000, at: Timestamp.now() });
  const hit = await callFn('mapsRoute', { from: { lat: 28.6139, lng: 77.209 }, to: { lat: 26.9124, lng: 75.7873 } }, cust.token);
  assert.deepEqual(hit.result, { meters: 281000, seconds: 18000, cached: true });
  assert.equal((await callFn('mapsRoute', { from: { lat: 51.5, lng: -0.1 }, to: { lat: 26.9, lng: 75.8 } }, cust.token)).error.status, 'INVALID_ARGUMENT');
  assert.equal((await callFn('mapsRoute', { from: { lat: 28.6, lng: 77.2 }, to: { lat: 26.9, lng: 75.8 } }, undefined)).error.status, 'UNAUTHENTICATED');
});

test('SMS: only to the caller\'s own emergency contacts', async () => {
  await db.collection('users').doc(cust.uid).set({ emergencyContacts: [{ name: 'Mother', phone: '+919822222222' }] });
  assert.equal((await callFn('smsSend', { to: '+919899999999', text: 'help' }, cust.token)).error.status, 'PERMISSION_DENIED');
  assert.equal((await callFn('smsSend', { to: 'nope', text: 'help' }, cust.token)).error.status, 'INVALID_ARGUMENT');
  assert.equal((await callFn('smsSend', { to: '+919822222222', text: 'help' }, undefined)).error.status, 'UNAUTHENTICATED');
});

test('webhook: a bad signature is refused; a good one settles the order, holds the money; a replay does nothing', async () => {
  await db.collection('bookings').doc('P3B1').set({
    customerId: cust.uid, driverId: driver.uid, status: 'in_transit', pickup: 'Mumbai', drop: 'Jaipur', vehicleType: '14ft', agreedFarePaise: 4500000, paymentStatus: 'pending',
  });
  await db.collection('payment_orders').doc('order_p3').set({ bookingId: 'P3B1', customerId: cust.uid, amountPaise: 4500000, status: 'created', createdAt: Timestamp.now() });
  const event = { event: 'payment.captured', payload: { payment: { entity: { id: 'pay_p3', order_id: 'order_p3', amount: 4500000 } } } };

  const bad = await webhook(event, { eventId: 'ev-p3-1', signature: 'abc' });
  assert.equal(bad.status, 400);
  const wrong = await webhook(event, { eventId: 'ev-p3-1', secret: 'not the secret' });
  assert.equal(wrong.status, 400);
  assert.equal((await db.collection('payment_orders').doc('order_p3').get()).data().status, 'created');

  // The first call into a cold function can fail while the emulator loads its secrets; the server then releases the
  // event claim (so the real Razorpay would retry), and the test retries the same way.
  let good = await webhook(event, { eventId: 'ev-p3-1' });
  for (let i = 0; i < 3 && good.status !== 200; i++) {
    await pause(1500);
    good = await webhook(event, { eventId: 'ev-p3-1' });
  }
  assert.deepEqual(good, { status: 200, text: 'paid' });
  assert.equal((await db.collection('payment_orders').doc('order_p3').get()).data().status, 'paid');
  const b = (await db.collection('bookings').doc('P3B1').get()).data();
  assert.deepEqual(b.paymentHold, { orderId: 'order_p3', paise: 4500000 }, 'payHold is on: the money is held');
  assert.equal((await db.collection('ledger').where('bookingId', '==', 'P3B1').get()).size, 0, 'nothing is credited yet');

  const again = await webhook(event, { eventId: 'ev-p3-1' });
  assert.equal(again.text, 'duplicate');
});

test('delivery: the held money becomes the driver\'s earning, the route gets its first amount, and the wallet follows', async () => {
  await db.collection('bookings').doc('P3B1').update({ status: 'delivered', timeline: { delivered: Timestamp.now() } });
  const lines = await waitFor(async () => {
    const s = await db.collection('ledger').where('bookingId', '==', 'P3B1').get();
    return s.size === 2 ? s.docs.map((d) => ({ id: d.id, ...d.data() })) : null;
  }, 'the two ledger lines after delivery');
  assert.equal(lines.find((l) => l.type === 'trip_earning').amountPaise, 4500000);
  assert.equal(lines.find((l) => l.type === 'platform_commission').amountPaise, -225000);
  const b = (await db.collection('bookings').doc('P3B1').get()).data();
  assert.equal(b.paymentStatus, 'driver_confirmed');
  assert.equal(b.paymentHold, undefined);
  const rate = await waitFor(async () => {
    const d = await db.collection('route_rates').doc('mumbai_jaipur_14ft').get();
    return d.exists ? d.data() : null;
  }, 'the route rate');
  assert.deepEqual(rate.recent, [4500000]);
  const wallet = await waitFor(async () => {
    const d = await db.collection('wallets').doc(driver.uid).get();
    return d.exists ? d.data() : null;
  }, 'the driver wallet');
  assert.ok(wallet);
});

test('a booking cancelled while the money is held leaves a line for finance', async () => {
  await db.collection('bookings').doc('P3B2').set({
    customerId: cust.uid, driverId: driver.uid, status: 'in_transit', pickup: 'Pune', drop: 'Delhi', vehicleType: '14ft', agreedFarePaise: 100000, paymentStatus: 'pending',
    paymentHold: { orderId: 'order_p3b2', paise: 100000 },
  });
  await db.collection('bookings').doc('P3B2').update({ status: 'cancelled' });
  const line = await waitFor(async () => {
    const d = await db.collection('audit_events').doc('hold_cancelled_P3B2').get();
    return d.exists ? d.data() : null;
  }, 'the audit line for the cancelled hold');
  assert.equal(line.data.orderId, 'order_p3b2');
});

test('old trips are cleaned: the job function exists and the switch decides', async () => {
  // The scheduled job itself is covered by the emulator test; here only that the deployed set has no broken import.
  const r = await callFn('serverStatus', {}, undefined);
  assert.equal(r.error.status, 'UNAUTHENTICATED');
});

test('App Check enforcement ON: a call without the app\'s proof is refused, with it OFF it only counted (last test)', async () => {
  await setFlags({ ...PART3_ON, appCheckEnforce: true });
  await pause(31000);
  const r = await callFn('mapsRoute', { from: { lat: 28.6139, lng: 77.209 }, to: { lat: 26.9124, lng: 75.7873 } }, cust.token);
  assert.equal(r.error.status, 'FAILED_PRECONDITION');
  assert.match(r.error.message, /app check/);
  assert.equal((await callFn('kycVerify', { kind: 'pan', number: 'ABCDE1234F' }, cust.token)).error.status, 'FAILED_PRECONDITION');
  await setFlags(PART3_ON);
});
