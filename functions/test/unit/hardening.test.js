'use strict';
// Part 5 (H5): the checklist in docs/FUNCTIONS_SECURITY.md, pinned so a new function cannot skip it unnoticed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const index = fs.readFileSync(path.join(__dirname, '../../index.js'), 'utf8');

test('limits are explicit: timeout, memory and maximum instances', () => {
  assert.match(index, /setGlobalOptions\(\{[^}]*maxInstances:\s*\d+[^}]*\}\)/);
  assert.match(index, /setGlobalOptions\(\{[^}]*timeoutSeconds:\s*\d+/);
  assert.match(index, /setGlobalOptions\(\{[^}]*memory:\s*'\d+MiB'/);
});

test('every callable and HTTP function sits behind a switch (flagOn) or a staff check', () => {
  // Split the file into one chunk per `exports.name =` and check each chunk that defines an onCall / onRequest.
  const chunks = index.split(/\nexports\./).slice(1);
  const wrapped = new Set(['adminCallable', 'paymentCallable']); // these helpers contain the flag check
  for (const chunk of chunks) {
    const name = chunk.split(/\s*=/)[0];
    if (!/onCall\(|onRequest\(|adminCallable\(|paymentCallable\(/.test(chunk)) continue;
    // serverStatus is the one exception on purpose: it answers while every switch is off (the first thing to try after a deploy), but only to staff (requireStaff inside).
    const ok = name === 'serverStatus' || /flagOn\(/.test(chunk) || [...wrapped].some((w) => chunk.includes(`${w}(`));
    assert.ok(ok, `${name} has no switch (flagOn) and does not use a wrapper that has one`);
  }
});

test('callables never return or log a raw error object to the caller', () => {
  // The only things thrown to a caller are HttpsError with a short fixed text or a typed error's own message.
  assert.doesNotMatch(index, /throw new HttpsError\('internal',\s*(e|err|error)\b/);
  assert.doesNotMatch(index, /HttpsError\('internal',[^)]*\.message/);
});

test('secrets come from Secret Manager only', () => {
  assert.match(index, /defineSecret\('RAZORPAY_KEY_SECRET'\)/);
  for (const file of fs.readdirSync(path.join(__dirname, '../../src'))) {
    const src = fs.readFileSync(path.join(__dirname, '../../src', file), 'utf8');
    assert.doesNotMatch(src, /rzp_(live|test)_[A-Za-z0-9]{8,}/, file);
    assert.doesNotMatch(src, /AIza[0-9A-Za-z_-]{35}/, file);
    assert.doesNotMatch(src, /-----BEGIN [A-Z ]*PRIVATE KEY-----/, file);
  }
});

test('logs: console.error and warn carry a short message, never the whole input', () => {
  for (const file of fs.readdirSync(path.join(__dirname, '../../src')).concat(['../index.js'])) {
    const src = fs.readFileSync(path.join(__dirname, '../../src', file), 'utf8');
    assert.doesNotMatch(src, /console\.(log|error|warn)\([^)]*(request\.data|rawBody|input\b)(?!\.)/, `${file} logs raw input`);
  }
});
