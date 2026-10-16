'use strict';
// F44: the functions run for real inside the emulators (Auth, Firestore, Functions, Storage):
// real triggers, real callables with a real sign-in token, real files. The plain-function logic
// has its own faster tests in test/unit and test/emulator; this file proves the wiring.
//
// The functions cache the switches for 30 seconds, so the order matters: first everything with
// the switches OFF (nothing may happen), then switch everything ON once and wait the cache out.

const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { db, auth, bucket, waitFor, pause, setFlags, signUp, callFn, clearAll } = require('./helpers');

const ALL_ON = {
  serverLimits: true, serverChatScan: true, serverCredits: true, serverTrust: true, serverJobs: true,
  serverAdminActions: true, serverDeletion: true, serverWallet: true, pushNotifications: true, adminBroadcast: true,
  photoUploads: true, paymentGateway: true,
};

let boss; // an admin with the super role (no role field = super)
let cust; // an ordinary signed-in person

test.before(async () => {
  await clearAll();
  boss = await signUp('boss@example.test');
  cust = await signUp('cust@example.test');
  await db.collection('admins').doc(boss.uid).set({ createdBy: 'console' });
});

test('switches OFF: callables say "disabled" and triggers change nothing', async () => {
  await setFlags({});
  // callable behind a switch
  const r = await callFn('adminSetRiskTier', { uid: cust.uid, tier: 'review', reason: 'test' }, boss.token);
  assert.equal(r.error.status, 'FAILED_PRECONDITION');
  // trigger behind a switch: a message with a phone number is NOT removed
  await db.collection('bookings').doc('BOFF').set({ customerId: cust.uid, driverId: 'drvOff' });
  const msg = db.collection('bookings').doc('BOFF').collection('messages').doc('m1');
  await msg.set({ senderId: cust.uid, text: 'call me on 9876543210 please', createdAt: Timestamp.now() });
  await pause(4000);
  assert.equal((await msg.get()).exists, true, 'nothing happens while the switch is off');
  assert.equal((await db.collection('violations').get()).size, 0);
  // wallet trigger: no summary is written
  await db.collection('ledger').doc('LOFF').set({ driverId: 'drvOff', bookingId: 'BOFF', type: 'trip_earning', amountPaise: 1000, createdAt: Timestamp.now() });
  await pause(2000);
  assert.equal((await db.collection('wallets').doc('drvOff').get()).exists, false);
});

test('serverStatus works with every switch off: needs a sign-in and an admin', async () => {
  const none = await callFn('serverStatus', {}, undefined);
  assert.equal(none.error.status, 'UNAUTHENTICATED');
  const stranger = await callFn('serverStatus', {}, cust.token);
  assert.equal(stranger.error.status, 'PERMISSION_DENIED');
  const ok = await callFn('serverStatus', {}, boss.token);
  assert.equal(ok.result.ok, true);
  assert.equal(ok.result.region, 'asia-south1');
  assert.ok(Object.values(ok.result.switches).every((v) => v === false));
});

test('switch everything ON (and wait for the 30 s switch cache)', async () => {
  await setFlags(ALL_ON);
  await pause(32000);
  const ok = await callFn('serverStatus', {}, boss.token);
  assert.equal(ok.result.switches.serverWallet, true);
  assert.equal(ok.result.switches.paymentGateway, true);
});

test('limits: when one shipper posts a 6th load in a minute, one load is removed and one audit line is written (burst limit 5)', async () => {
  for (let i = 0; i < 6; i++) {
    await db.collection('loads').doc(`LIM${i}`).set({ shipperId: 'shipLim', status: 'open', createdAt: Timestamp.now() });
  }
  // Which one goes depends on which trigger runs last; what must hold is the count and the audit.
  await waitFor(async () => (await db.collection('loads').where('shipperId', '==', 'shipLim').get()).size === 5, 'five loads are left');
  const audit = await waitFor(async () => {
    const s = await db.collection('audit_events').where('targetId', '==', 'shipLim').get();
    return s.empty ? null : s.docs.map((d) => d.data());
  }, 'an audit line');
  assert.equal(audit.length, 1);
  assert.equal(audit[0].data.action, 'server_limit');
  assert.equal(audit[0].data.kind, 'load');
  assert.equal(audit[0].data.limit, 5);
  await pause(2000);
  assert.equal((await db.collection('loads').where('shipperId', '==', 'shipLim').get()).size, 5, 'it stays at five');
});

test('chat scan: a message with a phone number is removed and a violation is written', async () => {
  await db.collection('bookings').doc('B1').set({ customerId: cust.uid, driverId: 'drv1' });
  const good = db.collection('bookings').doc('B1').collection('messages').doc('ok');
  const bad = db.collection('bookings').doc('B1').collection('messages').doc('bad');
  await good.set({ senderId: cust.uid, text: 'Truck kab aayega?', createdAt: Timestamp.now() });
  await bad.set({ senderId: cust.uid, text: 'mujhe 9876543210 par call karo', createdAt: Timestamp.now() });
  await waitFor(async () => !(await bad.get()).exists, 'the bad message is removed');
  assert.equal((await good.get()).exists, true, 'a normal message stays');
  const v = await waitFor(async () => {
    const s = await db.collection('violations').where('userId', '==', cust.uid).get();
    return s.empty ? null : s.docs[0].data();
  }, 'a violation');
  assert.equal(v.source, 'server');
  const u = (await db.collection('users').doc(cust.uid).get()).data();
  assert.equal(u.chatStrikes, 1);
});

test('credits: a credit line updates the balance the clients cannot write', async () => {
  const col = db.collection('users').doc('credU').collection('credits');
  await col.doc('a').set({ kind: 'grant', amountPaise: 50000, createdAt: Timestamp.now() });
  await col.doc('b').set({ kind: 'spend', amountPaise: -20000, createdAt: Timestamp.now() });
  const b = await waitFor(async () => {
    const s = await db.collection('credit_balances').doc('credU').get();
    return s.exists && s.data().lines === 2 ? s.data() : null;
  }, 'balance of 2 lines');
  assert.equal(b.balancePaise, 30000);
});

test('trust: a delivered trip is counted for the driver and the public summary appears', async () => {
  const ref = db.collection('bookings').doc('BT1');
  await ref.set({ customerId: cust.uid, driverId: 'drvTrust', status: 'picked_up' });
  await ref.update({ status: 'delivered', 'timeline.delivered': Timestamp.now() });
  await waitFor(async () => (await db.collection('trip_counts').doc('drvTrust').get()).exists, 'trip_counts');
  await waitFor(async () => (await db.collection('public_trust').doc('drvTrust').get()).exists, 'public_trust');
});

test('wallet: a ledger line makes the driver wallet; a payout above the balance is rejected', async () => {
  await db.collection('ledger').doc('W1').set({ driverId: 'drvW', bookingId: 'BW', type: 'trip_earning', amountPaise: 100000, createdAt: Timestamp.now() });
  const w = await waitFor(async () => {
    const s = await db.collection('wallets').doc('drvW').get();
    return s.exists ? s.data() : null;
  }, 'wallet summary');
  assert.equal(JSON.stringify(w).includes('100000'), true, 'the earning is in the summary');
  const p = db.collection('payouts').doc('P1');
  await p.set({ driverId: 'drvW', amountPaise: 9000000, status: 'requested', createdAt: Timestamp.now() });
  await waitFor(async () => {
    const s = await p.get();
    return s.exists && s.data().status !== 'requested';
  }, 'the impossible payout is changed');
});

test('admin actions: risk tier through the callable writes the change and the audit line', async () => {
  await db.collection('users').doc('riskU').set({ name: 'R' });
  const denied = await callFn('adminSetRiskTier', { uid: 'riskU', tier: 'review', reason: 'x' }, cust.token);
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  const bad = await callFn('adminSetRiskTier', { uid: 'riskU', tier: 'wizard', reason: 'x' }, boss.token);
  assert.equal(bad.error.status, 'INVALID_ARGUMENT');
  const ok = await callFn('adminSetRiskTier', { uid: 'riskU', tier: 'review', reason: 'many cancels' }, boss.token);
  assert.equal(ok.error, undefined);
  const u = (await db.collection('users').doc('riskU').get()).data();
  assert.equal(u.riskTier, 'review');
  const audits = await db.collection('audit_events').where('targetId', '==', 'riskU').get();
  assert.ok(audits.size >= 1);
});

test('broadcast: only staff; a bad text is refused', async () => {
  const denied = await callFn('adminBroadcast', { title: 'Hi', body: 'There' }, cust.token);
  assert.equal(denied.error.status, 'PERMISSION_DENIED');
  const bad = await callFn('adminBroadcast', { title: '', body: '' }, boss.token);
  assert.equal(bad.error.status, 'INVALID_ARGUMENT');
});

test('payments: order from the booking amount; a forged signature is refused', async () => {
  await db.collection('bookings').doc('BP1').set({ customerId: cust.uid, driverId: 'drvP', agreedFarePaise: 250000 });
  const stranger = await callFn('paymentCreateOrder', { bookingId: 'BP1' }, boss.token);
  assert.equal(stranger.error.status, 'PERMISSION_DENIED');
  const none = await callFn('paymentCreateOrder', { bookingId: 'BP1' }, undefined);
  assert.equal(none.error.status, 'UNAUTHENTICATED');
  // No real order can be created here (the emulator cannot reach Razorpay): the gateway failure is a calm error.
  const real = await callFn('paymentCreateOrder', { bookingId: 'BP1' }, cust.token);
  assert.ok(real.error, 'no gateway in the emulator');
  assert.ok(['UNAVAILABLE', 'FAILED_PRECONDITION', 'INTERNAL'].includes(real.error.status), real.error.status);
  // A forged signature on an order that exists
  await db.collection('payment_orders').doc('order_x1').set({ bookingId: 'BP1', customerId: cust.uid, amountPaise: 250000, status: 'created', createdAt: new Date() });
  const forged = await callFn('paymentVerify', { orderId: 'order_x1', paymentId: 'pay_1', signature: 'forged' }, cust.token);
  assert.equal(forged.error.status, 'PERMISSION_DENIED');
  assert.equal((await db.collection('payment_orders').doc('order_x1').get()).data().status, 'created');
});

test('deletion: an approved request removes the data, the files and the sign-in', async () => {
  const gone = await signUp('gone@example.test');
  await db.collection('users').doc(gone.uid).set({ name: 'Gone', role: 'customer' });
  await db.collection('users').doc(gone.uid).collection('uploads').doc('u1').set({ kind: 'rc', path: `users/${gone.uid}/docs/rc/u1.jpg` });
  await bucket().file(`users/${gone.uid}/docs/rc/u1.jpg`).save(Buffer.from([1, 2, 3]), { contentType: 'image/jpeg' });
  const other = `users/someoneElse/docs/rc/keep.jpg`;
  await bucket().file(other).save(Buffer.from([9]), { contentType: 'image/jpeg' });
  await db.collection('deletion_requests').doc(gone.uid).set({ status: 'pending', requestedAt: Timestamp.now() });
  await db.collection('deletion_requests').doc(gone.uid).update({ status: 'approved' });
  await waitFor(async () => (await db.collection('deletion_requests').doc(gone.uid).get()).data().status === 'done', 'the request is done', 30000);
  assert.equal((await db.collection('users').doc(gone.uid).get()).exists, false);
  const [files] = await bucket().getFiles({ prefix: `users/${gone.uid}/` });
  assert.equal(files.length, 0, 'the files are gone');
  await assert.rejects(auth.getUser(gone.uid), (e) => e.code === 'auth/user-not-found');
  const [keep] = await bucket().file(other).exists();
  assert.equal(keep, true, 'another person\'s file is untouched');
});

test('push: with the switch ON and nobody to send to, triggers finish without breaking the data', async () => {
  // The emulators have no FCM. A notification for a person with no token must be harmless.
  await db.collection('notifications').doc('N1').set({ userId: 'noToken', type: 'booking', title: 'x', createdAt: Timestamp.now() });
  await db.collection('sos_alerts').doc('S1').set({ userId: cust.uid, createdAt: Timestamp.now() });
  await pause(3000);
  assert.equal((await db.collection('notifications').doc('N1').get()).exists, true);
});
