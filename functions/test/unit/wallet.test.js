'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { computeBoxes, billAmount } = require('../../src/wallet');

const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'fixtures', 'wallet_cases.json'), 'utf8'));

test('the JavaScript book gives the same boxes as the Dart book for 400 random books', () => {
  assert.ok(fixture.cases.length >= 400);
  const wrong = [];
  fixture.cases.forEach((c, i) => {
    const got = computeBoxes({ ledger: c.ledger, payouts: c.payouts, bookings: [] });
    const e = c.expected;
    if (got.availablePaise !== e.available || got.heldPaise !== e.held || got.paidOutPaise !== e.paidOut) {
      wrong.push({ i, got: [got.availablePaise, got.heldPaise, got.paidOutPaise], dart: [e.available, e.held, e.paidOut] });
    }
  });
  assert.deepEqual(wrong.slice(0, 5), [], `${wrong.length} books differ`);
});

test('a plain book', () => {
  const b = computeBoxes({
    ledger: [
      { type: 'trip_earning', amountPaise: 100000 },
      { type: 'platform_commission', amountPaise: -5000 },
      { type: 'adjustment', amountPaise: -2000 },
    ],
    payouts: [
      { status: 'requested', amountPaise: 10000 },
      { status: 'approved', amountPaise: 5000 },
      { status: 'paid', amountPaise: 20000 },
      { status: 'rejected', amountPaise: 99999 },
      { status: 'reversed', amountPaise: 99999 },
    ],
    bookings: [
      { status: 'delivered', paymentStatus: 'customer_marked_paid', paidAmountPaise: 30000 },
      { status: 'delivered', paymentStatus: 'driver_confirmed', paidAmountPaise: 99999 },
      { status: 'in_transit', paidAmountPaise: 12345 },
    ],
  });
  assert.equal(b.netPaise, 93000);
  assert.equal(b.heldPaise, 15000);
  assert.equal(b.paidOutPaise, 20000);
  assert.equal(b.availablePaise, 58000);
  assert.equal(b.pendingPaise, 30000);
  assert.equal(b.overdrawn, false);
});

test('more paid than earned is shown as overdrawn, not hidden', () => {
  const b = computeBoxes({ ledger: [{ type: 'trip_earning', amountPaise: 1000 }], payouts: [{ status: 'paid', amountPaise: 5000 }], bookings: [] });
  assert.equal(b.availablePaise, -4000);
  assert.equal(b.overdrawn, true);
});

test('damaged documents never throw', () => {
  const b = computeBoxes({
    ledger: [{}, { type: 'trip_earning' }, { type: 'trip_earning', amountPaise: 'lots' }, { type: 'trip_earning', amountPaise: 2 ** 60 }, { type: 7, amountPaise: 5 }],
    payouts: [{}, { status: 'paid', amountPaise: -5 }, { status: 'paid', amountPaise: NaN }],
    bookings: [{ status: 'delivered', budget: 'x' }, { status: 'delivered', budget: 12.5 }, {}],
  });
  assert.equal(b.netPaise, 0);
  assert.equal(b.pendingPaise, 1250);
});

test('the bill of a booking: paid, then agreed, then estimate, then budget', () => {
  assert.equal(billAmount({ paidAmountPaise: 5, agreedFarePaise: 6, fareEstimate: 7, budget: 8 }), 5);
  assert.equal(billAmount({ agreedFarePaise: 6, fareEstimate: 7, budget: 8 }), 6);
  assert.equal(billAmount({ fareEstimate: 7, budget: 8 }), 7);
  assert.equal(billAmount({ budget: 8 }), 800);
  assert.equal(billAmount({}), 0);
});
