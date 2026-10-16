'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { expectedSignature, verifySignature, validPaise, razorpayHttp, MAX_PAISE } = require('../../src/razorpay');

test('the signature is HMAC-SHA256 hex of "order|payment" with the key secret', () => {
  const secret = 'test_secret_not_real';
  const want = crypto.createHmac('sha256', secret).update('order_1|pay_1').digest('hex');
  assert.equal(expectedSignature('order_1', 'pay_1', secret), want);
  assert.equal(want.length, 64);
  assert.ok(verifySignature('order_1', 'pay_1', want, secret));
});

test('a wrong, short, empty or foreign signature is refused', () => {
  const secret = 's';
  const good = expectedSignature('o', 'p', secret);
  assert.equal(verifySignature('o', 'p', good.replace(/.$/, good.endsWith('0') ? '1' : '0'), secret), false);
  assert.equal(verifySignature('o', 'p', good.slice(0, 10), secret), false);
  assert.equal(verifySignature('o', 'p', '', secret), false);
  assert.equal(verifySignature('o', 'p2', good, secret), false, 'another payment');
  assert.equal(verifySignature('o2', 'p', good, secret), false, 'another order');
  assert.equal(verifySignature('o', 'p', good, 'other'), false, 'another secret');
  assert.equal(verifySignature('o', 'p', good, ''), false, 'no secret configured');
  assert.equal(verifySignature('o', 'p', undefined, secret), false);
  assert.equal(verifySignature(1, 'p', good, secret), false);
});

test('amounts are whole paise, positive, at most one crore rupees', () => {
  for (const ok of [1, 100, MAX_PAISE]) assert.equal(validPaise(ok), true, String(ok));
  for (const bad of [0, -1, 1.5, MAX_PAISE + 1, NaN, Infinity, '100', null, undefined, 2 ** 60]) assert.equal(validPaise(bad), false, String(bad));
});

test('the http helper sends basic auth to the Razorpay address and maps failures', async () => {
  let seen;
  const ok = razorpayHttp('key_id_x', 'secret_x', async (url, init) => {
    seen = { url, init };
    return { ok: true, status: 200, json: async () => ({ id: 'order_9' }) };
  });
  assert.deepEqual(await ok('POST', '/orders', { amount: 100 }), { id: 'order_9' });
  assert.equal(seen.url, 'https://api.razorpay.com/v1/orders');
  assert.equal(seen.init.headers.Authorization, 'Basic ' + Buffer.from('key_id_x:secret_x').toString('base64'));
  assert.equal(seen.init.body, JSON.stringify({ amount: 100 }));

  const down = razorpayHttp('a', 'b', async () => { throw new Error('offline'); });
  await assert.rejects(down('GET', '/x'), (e) => e.code === 'unavailable');
  const five = razorpayHttp('a', 'b', async () => ({ ok: false, status: 503, json: async () => ({}) }));
  await assert.rejects(five('GET', '/x'), (e) => e.code === 'unavailable');
  const refused = razorpayHttp('a', 'b', async () => ({ ok: false, status: 400, json: async () => ({ error: { description: 'bad' } }) }));
  await assert.rejects(refused('GET', '/x'), (e) => e.code === 'failed-precondition' && e.message === 'bad');
});

test('G9: the webhook signature is HMAC-SHA256 hex of the raw body with the webhook secret', () => {
  const { verifyWebhookSignature } = require('../../src/razorpay');
  const body = Buffer.from('{"event":"payment.captured"}');
  const sig = crypto.createHmac('sha256', 'wh_secret').update(body).digest('hex');
  assert.equal(verifyWebhookSignature(body, sig, 'wh_secret'), true);
  assert.equal(verifyWebhookSignature(body.toString(), sig, 'wh_secret'), true);
  assert.equal(verifyWebhookSignature(body, sig, 'other'), false);
  assert.equal(verifyWebhookSignature(body, sig, ''), false);
  assert.equal(verifyWebhookSignature(Buffer.from('{"event":"x"}'), sig, 'wh_secret'), false);
  assert.equal(verifyWebhookSignature(body, undefined, 'wh_secret'), false);
  assert.equal(verifyWebhookSignature(undefined, sig, 'wh_secret'), false);
  assert.equal(verifyWebhookSignature(body, sig.slice(2), 'wh_secret'), false);
});

test('G38: the commission share of a refund is exact for the biggest orders and adds up across partial refunds', () => {
  const { commissionShare } = require('../../src/razorpay');
  // 10 crore rupees order (1e10 paise), 5% commission, refund of nearly all of it: far above 2^53 when multiplied
  assert.equal(commissionShare(500000000, 9999999999, 10000000000), 500000000, 'half a paisa rounds up');
  assert.equal(commissionShare(500000000, 9999999990, 10000000000), 500000000, 'exactly half a paisa rounds up');
  assert.equal(commissionShare(500000000, 9999999980, 10000000000), 499999999, 'a hair under half rounds down');
  assert.equal(commissionShare(500000000, 10000000000, 10000000000), 500000000, 'a full refund gives back the whole commission');
  assert.equal(commissionShare(500000000, 0, 10000000000), 0);
  assert.equal(commissionShare(50000, 400000, 1000000), 20000);
  // many small refunds: the pieces (difference of running totals) add up to the share of the total
  let prev = 0;
  let sum = 0;
  for (const total of [333, 700, 1001, 5000, 9999, 12345, 20000]) {
    sum += commissionShare(1000, total, 20000) - commissionShare(1000, prev, 20000);
    prev = total;
  }
  assert.equal(sum, commissionShare(1000, 20000, 20000));
  assert.equal(commissionShare(1000, 5, 0), 0, 'no order amount, no division by zero');
});
