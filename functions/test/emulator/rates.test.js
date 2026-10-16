'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { getDb, clearDb } = require('../helpers');
const { recordTrip, routeKey, KEEP } = require('../../src/rates');

test.beforeEach(clearDb);

const trip = (over = {}) => ({ status: 'delivered', pickup: 'Andheri, Mumbai', drop: 'Jaipur Rajasthan', vehicleType: '14ft', agreedFarePaise: 4500000, ...over });

test('the key names both cities and the truck type the same way the app does', () => {
  assert.equal(routeKey('Andheri, Mumbai', 'jaipur', '14ft'), 'mumbai_jaipur_14ft');
  assert.equal(routeKey('Bombay', 'Delhi', '20 ft Container'), 'mumbai_delhi_20ftcontainer');
  assert.equal(routeKey('Nowhereville', 'Delhi', '14ft'), null);
  assert.equal(routeKey('Delhi', 'Delhi', '14ft'), null, 'a trip inside one city is not a route');
  assert.equal(routeKey('Delhi', 'Pune', ''), null);
});

test('a delivered booking is added once; the paid amount wins over the agreed one', async () => {
  const db = getDb();
  assert.equal((await recordTrip(db, 'b1', trip({ paidAmountPaise: 4400000 }))).action, 'recorded');
  assert.equal((await recordTrip(db, 'b1', trip())).action, 'again');
  assert.equal((await recordTrip(db, 'b2', trip({ agreedFarePaise: undefined, fareEstimate: 4000000 }))).action, 'recorded');
  const d = (await db.collection('route_rates').doc('mumbai_jaipur_14ft').get()).data();
  assert.deepEqual(d.recent, [4400000, 4000000]);
  assert.equal(d.n, 2);
  assert.ok(!JSON.stringify(d).includes('b1'), 'no booking id is kept');
});

test('only the last 30 amounts are kept but the count goes on', async () => {
  const db = getDb();
  for (let i = 1; i <= KEEP + 5; i++) await recordTrip(db, `b${i}`, trip({ agreedFarePaise: 1000000 + i }));
  const d = (await db.collection('route_rates').doc('mumbai_jaipur_14ft').get()).data();
  assert.equal(d.recent.length, KEEP);
  assert.equal(d.recent[KEEP - 1], 1000000 + KEEP + 5);
  assert.equal(d.n, KEEP + 5);
});

test('not delivered, no amount, a silly amount, odd ids and unknown places are skipped', async () => {
  const db = getDb();
  const skip = async (id, b) => assert.equal((await recordTrip(db, id, b)).action, 'skipped');
  await skip('b1', trip({ status: 'cancelled' }));
  await skip('b2', trip({ agreedFarePaise: undefined }));
  await skip('b3', trip({ agreedFarePaise: 1e12 }));
  await skip('b4', trip({ agreedFarePaise: 12.5 }));
  await skip('../x', trip());
  await skip('b6', trip({ pickup: 'Nowhereville' }));
  await skip('b7', null);
  assert.equal((await db.collection('route_rates').get()).size, 0);
  assert.equal((await db.collection('route_rates_seen').get()).size, 0);
});

test('two at the same moment are both counted exactly once', async () => {
  const db = getDb();
  await Promise.all([recordTrip(db, 'a1', trip()), recordTrip(db, 'a2', trip()), recordTrip(db, 'a1', trip())]);
  const d = (await db.collection('route_rates').doc('mumbai_jaipur_14ft').get()).data();
  assert.equal(d.n, 2);
});
