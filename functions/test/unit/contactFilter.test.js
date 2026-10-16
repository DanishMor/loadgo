'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { check, normalise } = require('../../src/contactFilter');
const { blockFor, needsReview } = require('../../src/chatScan');

const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'contact_cases.json'), 'utf8'));

test('the fixture from the Dart filter is not empty', () => {
  assert.ok(fixture.cases.length > 300, `only ${fixture.cases.length} cases`);
  const kinds = new Set(fixture.cases.map((c) => c.kind));
  for (const k of ['phone', 'upi', 'app', 'payment', null]) assert.ok(kinds.has(k), `no case of kind ${k}`);
});

test('the JavaScript filter gives the same answer as the Dart filter for every case', () => {
  const wrong = [];
  for (const c of fixture.cases) {
    const got = check(c.text, c.recent);
    if (got !== c.kind) wrong.push({ text: c.text.slice(0, 60), recent: c.recent, dart: c.kind, js: got });
  }
  assert.deepEqual(wrong, [], `${wrong.length} cases differ`);
});

test('digits of other scripts become 0-9 and invisible marks disappear', () => {
  assert.equal(normalise('९८७६'), '9876');
  assert.equal(normalise('9​8️⃣'), '98');
  assert.equal(normalise('ABC'), 'abc');
});

test('the strike ladder is the same as the app', () => {
  assert.equal(blockFor(1), null);
  assert.equal(blockFor(2), null);
  assert.equal(blockFor(3), 24 * 3600 * 1000);
  assert.equal(blockFor(4), 3 * 24 * 3600 * 1000);
  assert.equal(blockFor(5), 7 * 24 * 3600 * 1000);
  assert.equal(blockFor(9), 7 * 24 * 3600 * 1000);
  assert.equal(needsReview(4), false);
  assert.equal(needsReview(5), true);
});

test('a very long text does not hang', () => {
  const t0 = Date.now();
  check('9 '.repeat(5000));
  check('a'.repeat(100000));
  assert.ok(Date.now() - t0 < 2000);
});
