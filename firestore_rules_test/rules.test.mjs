// Security rules tests. Run with: npm test  (starts the Firestore emulator)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { GeoPoint, Timestamp, addDoc, deleteField, doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const as = (uid) => env.authenticatedContext(uid).firestore();
const asAdmin = () => env.authenticatedContext('admin1', { admin: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const LOAD = {
  shipperId: 'customer1',
  pickup: 'Delhi',
  drop: 'Mumbai',
  cargoType: 'FMCG',
  weight: 8,
  vehicleType: '20ft',
  budget: 25000,
  pickupDate: Timestamp.fromDate(new Date('2026-10-05')),
  notes: '',
  status: 'open',
};
const VEHICLE = { ownerId: 'driver1', number: 'MH12AB1234', type: '20ft', capacity: 10, rcNumber: 'RC1', status: 'active' };

function bookingFor(loadId, overrides = {}) {
  return {
    loadId,
    driverId: 'driver1',
    vehicleId: 'v1',
    customerId: 'customer1',
    status: 'accepted',
    pickup: LOAD.pickup,
    drop: LOAD.drop,
    cargoType: LOAD.cargoType,
    weight: LOAD.weight,
    vehicleType: LOAD.vehicleType,
    budget: LOAD.budget,
    pickupDate: LOAD.pickupDate,
    notes: '',
    vehicleNumber: VEHICLE.number,
    driverName: 'Ramesh',
    driverPhone: '+919800000000',
    timeline: { accepted: serverTimestamp() },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

/** Same writes as BookingService.accept (batched like the transaction commit). */
function acceptBatch(db, loadId, driver = 'driver1', bookingOverrides = {}) {
  const b = writeBatch(db);
  b.set(doc(db, 'bookings', loadId), bookingFor(loadId, { driverId: driver, ...bookingOverrides }));
  b.update(doc(db, 'loads', loadId), { status: 'matched', driverId: driver, bookingId: loadId, matchedAt: serverTimestamp() });
  b.update(doc(db, 'vehicles', bookingOverrides.vehicleId ?? (driver === 'driver2' ? 'v2' : 'v1')), { availability: 'on_trip' });
  return b.commit();
}

/** Same writes as VehicleService.add: vehicle + number reservation. */
function addVehicle(db, id, data = VEHICLE) {
  const b = writeBatch(db);
  b.set(doc(db, 'vehicle_numbers', data.number), { ownerId: data.ownerId, vehicleId: id });
  b.set(doc(db, 'vehicles', id), data);
  return b.commit();
}

async function seedOpenLoad() {
  await seed(async (db) => {
    await setDoc(doc(db, 'loads', 'L1'), LOAD);
    await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    await setDoc(doc(db, 'vehicles', 'v2'), { ...VEHICLE, ownerId: 'driver2', number: 'KA01CD5678' });
  });
}

const OTPS = { pickupOtp: '482913', deliveryOtp: '771204' };
const PICKUP = { packages: 40, weightTons: 7.5, sealNumber: 'SL-9', damageNote: '' };
const DELIVERY = { receiverName: 'Anil', receiverPhone: '+919811111111', damageNote: '' };

async function seedBooking(status = 'accepted') {
  await seedOpenLoad();
  await seed(async (db) => {
    await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, status: 'matched', driverId: 'driver1', bookingId: 'L1' });
    await setDoc(doc(db, 'bookings', 'L1'), { ...bookingFor('L1'), status, timeline: {} });
  });
}

describe('users', () => {
  test('owner reads/writes own doc; others cannot', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'users', 'u1'), { phone: '+91', selectedRole: 'customer' }));
    await assertSucceeds(getDoc(doc(as('u1'), 'users', 'u1')));
    await assertFails(getDoc(doc(as('u2'), 'users', 'u1')));
    await assertFails(setDoc(doc(as('u2'), 'users', 'u1'), { phone: 'x' }));
    await assertFails(getDoc(doc(anon(), 'users', 'u1')));
  });

  test('drivers cannot approve themselves', async () => {
    await assertFails(setDoc(doc(as('d1'), 'users', 'd1'), { verified: true, verificationStatus: 'approved' }));
    await assertSucceeds(setDoc(doc(as('d1'), 'users', 'd1'), { phone: '+91' }));
    // First driver profile save initialises pending/false.
    await assertSucceeds(updateDoc(doc(as('d1'), 'users', 'd1'), { verified: false, verificationStatus: 'pending', driverName: 'R' }));
    await assertFails(updateDoc(doc(as('d1'), 'users', 'd1'), { verificationStatus: 'approved' }));
    await assertFails(updateDoc(doc(as('d1'), 'users', 'd1'), { verified: true }));
    await assertSucceeds(updateDoc(doc(as('d1'), 'users', 'd1'), { driverName: 'Ramesh' }));
  });
});

describe('admin verification', () => {
  const seedDriver = () => seed((db) => setDoc(doc(db, 'users', 'd1'), { driverName: 'R', verified: false, verificationStatus: 'pending' }));

  test('admin reads drivers and approves/rejects; others cannot', async () => {
    await seedDriver();
    await assertSucceeds(getDocs(query(collection(asAdmin(), 'users'), where('verificationStatus', '==', 'pending'))));
    await assertFails(getDocs(query(collection(as('u2'), 'users'), where('verificationStatus', '==', 'pending'))));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'approved', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: false, verificationStatus: 'rejected', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('u2'), 'users', 'd1'), { verified: true, verificationStatus: 'approved' }));
  });

  test('admin can only touch verification fields, consistently', async () => {
    await seedDriver();
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { driverName: 'X' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'rejected' }));
    await assertFails(updateDoc(doc(asAdmin(), 'users', 'd1'), { verified: true, verificationStatus: 'bogus' }));
  });
});

describe('vehicles', () => {
  test('owner creates/updates; any signed-in user reads', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1'));
    await assertSucceeds(getDoc(doc(as('customer1'), 'vehicles', 'v1')));
    await assertFails(getDoc(doc(anon(), 'vehicles', 'v1')));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { status: 'inactive' }));
    await assertFails(updateDoc(doc(as('driver2'), 'vehicles', 'v1'), { status: 'active' }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { ownerId: 'driver2' }));
    await assertFails(deleteDoc(doc(as('driver2'), 'vehicles', 'v1')));
  });

  test('rcImageUrl must point at Firebase Storage', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1', {
      ...VEHICLE,
      rcImageUrl: 'https://firebasestorage.googleapis.com/v0/b/loadgo-defc2.appspot.com/o/vehicles%2Fdriver1%2Fv1%2Frc.jpg',
    }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { rcImageUrl: 'https://evil.example.com/x.jpg' }));
  });

  test('cannot create for someone else or with invalid data', async () => {
    await assertFails(addVehicle(as('driver2'), 'v9'));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, status: 'flying' }));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, capacity: 0 }));
    await assertFails(addVehicle(as('driver1'), 'v9', { ...VEHICLE, availability: 'suspended' }));
    await assertFails(setDoc(doc(as('driver1'), 'vehicles', 'v9'), VEHICLE), 'needs a number reservation');
  });

  test('the same number cannot be registered twice, even by another account', async () => {
    await assertSucceeds(addVehicle(as('driver1'), 'v1'));
    await assertFails(addVehicle(as('driver2'), 'v2', { ...VEHICLE, ownerId: 'driver2' }));
    await assertFails(addVehicle(as('driver1'), 'v3'));
    // Reservation can't be stolen or pointed at someone else's vehicle.
    await assertFails(setDoc(doc(as('driver2'), 'vehicle_numbers', VEHICLE.number), { ownerId: 'driver2', vehicleId: 'v1' }));
    await assertFails(deleteDoc(doc(as('driver2'), 'vehicle_numbers', VEHICLE.number)));
  });

  test('renumbering moves the reservation; deleting frees it', async () => {
    await addVehicle(as('driver1'), 'v1');
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { number: 'DL01ZZ0001' }), 'new number must be reserved');
    const b = writeBatch(db);
    b.set(doc(db, 'vehicle_numbers', 'DL01ZZ0001'), { ownerId: 'driver1', vehicleId: 'v1' });
    b.delete(doc(db, 'vehicle_numbers', VEHICLE.number));
    b.update(doc(db, 'vehicles', 'v1'), { number: 'DL01ZZ0001' });
    await assertSucceeds(b.commit());
    await assertSucceeds(addVehicle(as('driver2'), 'v2', { ...VEHICLE, ownerId: 'driver2' }));
    const d = writeBatch(db);
    d.delete(doc(db, 'vehicles', 'v1'));
    d.delete(doc(db, 'vehicle_numbers', 'DL01ZZ0001'));
    await assertSucceeds(d.commit());
  });

  test('documents, service date and availability', async () => {
    await addVehicle(as('driver1'), 'v1');
    const db = as('driver1');
    await assertSucceeds(updateDoc(doc(db, 'vehicles', 'v1'), {
      docs: { insurance: { number: 'POL1', expiry: Timestamp.fromDate(new Date('2027-01-01')) } },
      nextServiceDate: Timestamp.fromDate(new Date('2026-11-01')),
    }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { docs: { passport: { number: 'X' } } }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { nextServiceDate: 'soon' }));
    await assertSucceeds(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'maintenance' }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'suspended' }));
    await assertFails(updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'parked' }));
    await assertFails(updateDoc(doc(as('driver2'), 'vehicles', 'v1'), { availability: 'available' }));
  });

  test('only admins suspend or lift a suspension', async () => {
    await addVehicle(as('driver1'), 'v1');
    await assertSucceeds(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { availability: 'suspended' }));
    await assertFails(updateDoc(doc(as('driver1'), 'vehicles', 'v1'), { availability: 'available' }));
    await assertFails(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { capacity: 50 }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'vehicles', 'v1'), { availability: 'available' }));
  });
});

describe('loads', () => {
  test('shipper posts an open load; drivers read open loads', async () => {
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, createdAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertSucceeds(getDocs(query(collection(as('driver1'), 'loads'), where('status', '==', 'open'))));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'loads'), where('shipperId', '==', 'customer1'))));
    await assertFails(getDocs(collection(as('driver1'), 'loads')));
    await assertFails(getDoc(doc(anon(), 'loads', 'L1')));
  });

  test('load create is validated', async () => {
    await assertFails(setDoc(doc(as('customer2'), 'loads', 'L1'), LOAD));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, status: 'matched' }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, weight: -1 }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, driverId: 'driver1' }));
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, budget: null }));
  });

  test('shipper edits/cancels only while open; drivers cannot edit', async () => {
    await seedOpenLoad();
    await assertSucceeds(updateDoc(doc(as('customer1'), 'loads', 'L1'), { notes: 'fragile' }));
    await assertFails(updateDoc(doc(as('driver1'), 'loads', 'L1'), { budget: 1 }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'matched' }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { cancelled: true }));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed' }));
    await assertSucceeds(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed', cancelled: true, cancelledAt: serverTimestamp() }));
    // Once cancelled it cannot be reopened.
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'open', cancelled: false }));
  });

  test('shipper cannot cancel a matched load', async () => {
    await seedOpenLoad();
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'closed', cancelled: true }));
  });
});

describe('accepting a load', () => {
  test('driver accepts with booking + load update together', async () => {
    await seedOpenLoad();
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });

  test('matching without a booking, or a booking without matching, fails', async () => {
    await seedOpenLoad();
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'L1' }));
    await assertFails(setDoc(doc(db, 'bookings', 'L1'), bookingFor('L1')));
  });

  test('cannot accept with a tampered budget or someone else\'s vehicle', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { budget: 99999 }));
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { vehicleId: 'v2' }));
  });

  test('cannot accept own load or an already matched load', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('customer1'), 'L1', 'customer1', { customerId: 'customer1' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
    await assertFails(acceptBatch(as('driver2'), 'L1', 'driver2', { vehicleId: 'v2' }));
    // Matched load is hidden from other drivers but visible to the parties.
    await assertFails(getDoc(doc(as('driver2'), 'loads', 'L1')));
    await assertSucceeds(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'loads', 'L1')));
  });
});

describe('bookings', () => {
  test('only the driver and customer can read', async () => {
    await seedBooking();
    await assertSucceeds(getDoc(doc(as('driver1'), 'bookings', 'L1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'bookings', 'L1')));
    await assertSucceeds(getDocs(query(collection(as('driver1'), 'bookings'), where('driverId', '==', 'driver1'))));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'bookings'), where('customerId', '==', 'customer1'))));
    await assertFails(getDoc(doc(as('driver2'), 'bookings', 'L1')));
    await assertFails(getDocs(collection(as('driver2'), 'bookings')));
  });

  test('driver advances one step at a time; nobody else can', async () => {
    await seedBooking();
    const step = (db, status, extra = {}) =>
      updateDoc(doc(db, 'bookings', 'L1'), { status, [`timeline.${status}`]: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
    await assertFails(step(as('driver1'), 'delivered'));
    await assertFails(step(as('driver1'), 'loading'), 'no skipping');
    await assertFails(step(as('customer1'), 'driver_arriving'));
    await assertFails(step(as('driver2'), 'driver_arriving'));
    await assertSucceeds(step(as('driver1'), 'driver_arriving'));
    await assertFails(step(as('driver1'), 'accepted'));
    await assertSucceeds(step(as('driver1'), 'loading'));
    await seed((db) => setDoc(doc(db, 'bookings', 'L1', 'secrets', 'otp'), OTPS));
    await assertFails(step(as('driver1'), 'picked_up'), 'needs OTP');
    await assertSucceeds(step(as('driver1'), 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP }));
    await assertSucceeds(step(as('driver1'), 'in_transit'));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { budget: 1 }));
    await assertFails(deleteDoc(doc(as('driver1'), 'bookings', 'L1')));
  });

  test('driver shares live location only while in transit', async () => {
    const loc = () => ({ lastKnownLocation: new GeoPoint(28.6, 77.2), locationUpdatedAt: serverTimestamp() });
    await seedBooking('picked_up');
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await seed((db) => updateDoc(doc(db, 'bookings', 'L1'), { status: 'in_transit' }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('driver2'), 'bookings', 'L1'), loc()));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { ...loc(), budget: 1 }));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { lastKnownLocation: 'x', locationUpdatedAt: serverTimestamp() }));
  });

  test('delivering closes the load; closing early fails', async () => {
    await seedBooking('unloading');
    await seed((s) => setDoc(doc(s, 'bookings', 'L1', 'secrets', 'otp'), OTPS));
    const db = as('driver1');
    await assertFails(updateDoc(doc(db, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() }));
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', 'L1'), {
      status: 'delivered', 'timeline.delivered': serverTimestamp(), updatedAt: serverTimestamp(),
      deliveryOtp: OTPS.deliveryOtp, deliveryProof: DELIVERY,
    });
    b.update(doc(db, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
    await assertFails(updateDoc(doc(as('customer1'), 'loads', 'L1'), { status: 'open' }));
  });
});

describe('ratings', () => {
  const rating = (rater, rated, extra = {}) => ({ bookingId: 'L1', raterId: rater, ratedId: rated, stars: 5, comment: 'Great', createdAt: serverTimestamp(), ...extra });

  test('parties rate each other once after delivery', async () => {
    await seedBooking('delivered');
    await assertSucceeds(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1')));
    await assertSucceeds(setDoc(doc(as('driver1'), 'ratings', 'L1_driver1'), rating('driver1', 'customer1', { stars: 4 })));
    // No second rating / edits.
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 1 })));
    await assertFails(deleteDoc(doc(as('customer1'), 'ratings', 'L1_customer1')));
    await assertSucceeds(getDocs(query(collection(as('driver2'), 'ratings'), where('ratedId', '==', 'driver1'))));
  });

  test('rejects early, outsider, mismatched or invalid ratings', async () => {
    await seedBooking('in_transit');
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1')));
    await seedBooking('delivered');
    await assertFails(setDoc(doc(as('driver2'), 'ratings', 'L1_driver2'), rating('driver2', 'driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'customer1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'other_id'), rating('customer1', 'driver1')));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 6 })));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { stars: 4.5 })));
    await assertFails(setDoc(doc(as('customer1'), 'ratings', 'L1_customer1'), rating('customer1', 'driver1', { comment: 'x'.repeat(501) })));
  });
});

describe('notifications', () => {
  const notif = (userId, extra = {}) => ({ userId, type: 'status_changed', message: 'Delhi → Mumbai', relatedId: 'L1', status: 'picked_up', read: false, createdAt: serverTimestamp(), ...extra });

  test('a booking party notifies the other party', async () => {
    await seedBooking();
    await assertSucceeds(addDoc(collection(as('driver1'), 'notifications'), notif('customer1')));
    await assertSucceeds(addDoc(collection(as('customer1'), 'notifications'), notif('driver1', { type: 'rating_received', status: null })));
  });

  test('outsiders, self-notifications and bad data are rejected', async () => {
    await seedBooking();
    await assertFails(addDoc(collection(as('driver2'), 'notifications'), notif('customer1')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('driver2')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('driver1')));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { read: true })));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { type: 'spam' })));
    await assertFails(addDoc(collection(as('driver1'), 'notifications'), notif('customer1', { relatedId: 'nope' })));
  });

  test('only the recipient reads and marks read', async () => {
    await seedBooking();
    await seed((db) => setDoc(doc(db, 'notifications', 'n1'), notif('customer1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'notifications', 'n1')));
    await assertSucceeds(getDocs(query(collection(as('customer1'), 'notifications'), where('userId', '==', 'customer1'))));
    await assertFails(getDoc(doc(as('driver1'), 'notifications', 'n1')));
    await assertFails(updateDoc(doc(as('customer1'), 'notifications', 'n1'), { message: 'changed' }));
    await assertFails(updateDoc(doc(as('driver1'), 'notifications', 'n1'), { read: true }));
    await assertSucceeds(updateDoc(doc(as('customer1'), 'notifications', 'n1'), { read: true }));
  });

  test('accept transaction can include the customer notification', async () => {
    await seedOpenLoad();
    const db = as('driver1');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'L1'), bookingFor('L1'));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'L1', matchedAt: serverTimestamp() });
    b.set(doc(db, 'notifications', 'n2'), notif('customer1', { type: 'load_accepted', status: null }));
    await assertSucceeds(b.commit());
  });
});

describe('driver cancels before pickup', () => {
  /** Same writes as BookingService.cancelByDriver. */
  function cancelBatch(db, bookingId = 'L1', cancellation = { by: 'driver', chargePaise: 0 }) {
    const b = writeBatch(db);
    b.update(doc(db, 'bookings', bookingId), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation, updatedAt: serverTimestamp() });
    b.update(doc(db, 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField(), matchedAt: deleteField(), reopenedAt: serverTimestamp() });
    return b.commit();
  }

  test('cancel reopens the load and another driver can accept with a new booking', async () => {
    await seedBooking();
    await assertSucceeds(cancelBatch(as('driver1')));
    await assertSucceeds(getDoc(doc(as('driver2'), 'loads', 'L1')));
    // New booking id for the second driver.
    const db = as('driver2');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B2'), bookingFor('L1', { driverId: 'driver2', vehicleId: 'v2' }));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver2', bookingId: 'B2', matchedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
    // The old driver can no longer touch the load or the old booking.
    await assertFails(getDoc(doc(as('driver1'), 'loads', 'L1')));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { status: 'picked_up' }));
  });

  test('the recorded cancellation charge must be a sane driver record', async () => {
    await seedBooking();
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'customer', chargePaise: 0 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: -1 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 12.5 }));
    await assertFails(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 100, paid: true }));
    await assertSucceeds(cancelBatch(as('driver1'), 'L1', { by: 'driver', chargePaise: 5000 }));
  });

  test('cannot cancel after pickup, as someone else, or without reopening', async () => {
    await seedBooking();
    await assertFails(cancelBatch(as('driver2')));
    await assertFails(cancelBatch(as('customer1')));
    await assertFails(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { status: 'cancelled', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('driver1'), 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField() }));
    await seedBooking('picked_up');
    await assertFails(cancelBatch(as('driver1')));
  });

  test('cannot point a load at a booking for a different load', async () => {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'loads', 'L2'), LOAD));
    const db = as('driver1');
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B9'), bookingFor('L2'));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'B9' });
    await assertFails(b.commit());
  });
});

describe('config', () => {
  const TYPES = { types: [{ id: 'Mini', name: 'Mini truck', minTons: 0.75, maxTons: 2, category: 'lcv', active: true }] };

  test('signed-in users read config, anonymous users cannot', async () => {
    await seed((db) => setDoc(doc(db, 'config', 'vehicle_types'), TYPES));
    await assertSucceeds(getDoc(doc(as('driver1'), 'config', 'vehicle_types')));
    await assertFails(getDoc(doc(anon(), 'config', 'vehicle_types')));
  });

  test('only admins write config, with a valid shape', async () => {
    await assertFails(setDoc(doc(as('driver1'), 'config', 'vehicle_types'), TYPES));
    await assertSucceeds(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), TYPES));
    await assertFails(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), { types: [] }));
    await assertFails(setDoc(doc(asAdmin(), 'config', 'vehicle_types'), { ...TYPES, extra: 1 }));
    await assertFails(deleteDoc(doc(asAdmin(), 'config', 'vehicle_types')));
  });
});

describe('vehicle availability and bookings', () => {
  test('a vehicle in maintenance, suspended or on another trip cannot be booked', async () => {
    await seedOpenLoad();
    for (const availability of ['maintenance', 'suspended', 'on_trip']) {
      await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { availability }));
      await assertFails(acceptBatch(as('driver1'), 'L1'), availability);
    }
    await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { availability: 'available', status: 'inactive' }));
    await assertFails(acceptBatch(as('driver1'), 'L1'), 'inactive');
    await seed((db) => updateDoc(doc(db, 'vehicles', 'v1'), { status: 'active' }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1'));
  });
});

describe('fare estimate', () => {
  const EST = { total: 412000, tripFare: 380000, distanceKm: 120, platformFee: 19000, gst: 13000, distanceSource: 'cities' };

  test('loads may carry a well-formed estimate in integer paise', async () => {
    await assertSucceeds(setDoc(doc(as('customer1'), 'loads', 'L1'), { ...LOAD, estimate: EST }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L2'), { ...LOAD, estimate: { ...EST, total: 4120.5 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L3'), { ...LOAD, estimate: { ...EST, tripFare: 500000 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L4'), { ...LOAD, estimate: { ...EST, distanceKm: 99999 } }));
    await assertFails(setDoc(doc(as('customer1'), 'loads', 'L5'), { ...LOAD, estimate: 'cheap' }));
  });

  test('the booking must copy the load estimate total', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'loads', 'L1'), { ...LOAD, estimate: EST });
      await setDoc(doc(db, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { fareEstimate: 1 }));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { fareEstimate: EST.total }));
  });
});

describe('load posting upgrade', () => {
  test('extra stops: at most 2 per side, non-empty strings', async () => {
    const db = as('customer1');
    await assertSucceeds(setDoc(doc(db, 'loads', 'A'), { ...LOAD, extraPickups: ['Gurugram', 'Noida'], extraDrops: ['Ajmer'] }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, extraPickups: ['a1', 'b2', 'c3'] }));
    await assertFails(setDoc(doc(db, 'loads', 'C'), { ...LOAD, extraDrops: [''] }));
    await assertFails(setDoc(doc(db, 'loads', 'D'), { ...LOAD, extraDrops: 'Ajmer' }));
  });

  test('pickup slot must be a known value', async () => {
    const db = as('customer1');
    await assertSucceeds(setDoc(doc(db, 'loads', 'A'), { ...LOAD, pickupSlot: 'evening' }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, pickupSlot: 'midnight' }));
  });

  test('prohibited goods are refused even if the app check is bypassed', async () => {
    const db = as('customer1');
    await assertFails(setDoc(doc(db, 'loads', 'A'), { ...LOAD, notes: 'Two boxes of Explosives' }));
    await assertFails(setDoc(doc(db, 'loads', 'B'), { ...LOAD, notes: 'ganja' }));
    await assertFails(setDoc(doc(db, 'loads', 'C'), { ...LOAD, cargoType: 'Fireworks' }));
    await assertSucceeds(setDoc(doc(db, 'loads', 'D'), { ...LOAD, notes: 'gunny bags, handle with care' }));
    await seed((s) => setDoc(doc(s, 'loads', 'E'), LOAD));
    await assertFails(updateDoc(doc(db, 'loads', 'E'), { notes: 'actually ammunition' }));
  });

  test('bookings must copy the stops of the load', async () => {
    await seed(async (s) => {
      await setDoc(doc(s, 'loads', 'L1'), { ...LOAD, extraDrops: ['Ajmer'] });
      await setDoc(doc(s, 'vehicles', 'v1'), VEHICLE);
    });
    await assertFails(acceptBatch(as('driver1'), 'L1'));
    await assertSucceeds(acceptBatch(as('driver1'), 'L1', 'driver1', { extraDrops: ['Ajmer'] }));
  });

  test('saved places: owner only, validated', async () => {
    const mine = doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p1');
    await assertSucceeds(setDoc(mine, { label: 'warehouse', name: 'Bhiwandi', address: 'Thane' }));
    await assertSucceeds(getDoc(mine));
    await assertFails(getDoc(doc(as('driver1'), 'users', 'customer1', 'saved_places', 'p1')));
    await assertFails(setDoc(doc(as('driver1'), 'users', 'customer1', 'saved_places', 'p2'), { label: 'home', name: 'x', address: 'yy' }));
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p3'), { label: 'castle', name: 'x', address: 'yy' }));
    await assertFails(setDoc(doc(as('customer1'), 'users', 'customer1', 'saved_places', 'p4'), { label: 'home', name: 'x', address: 'yy', extra: 1 }));
    await assertSucceeds(deleteDoc(mine));
  });
});

describe('offers', () => {
  const OFFER = {
    loadId: 'L1', driverId: 'driver1', customerId: 'customer1', vehicleId: 'v1', vehicleNumber: VEHICLE.number,
    vehicleType: '20ft', driverName: 'Ramesh', pricePaise: 2400000, originalPaise: 2400000, status: 'pending',
  };
  const ref = (db, id = 'L1_driver1') => doc(db, 'offers', id);

  async function seedOffer(overrides = {}) {
    await seedOpenLoad();
    await seed((db) => setDoc(doc(db, 'offers', 'L1_driver1'), { ...OFFER, ...overrides }));
  }

  /** Same writes as OfferService.confirm -> BookingService.accept with an offer. */
  function confirmBatch(db, overrides = {}) {
    const b = writeBatch(db);
    b.set(doc(db, 'bookings', 'B1'), bookingFor('L1', { offerId: 'L1_driver1', agreedFarePaise: OFFER.pricePaise, ...overrides }));
    b.update(doc(db, 'loads', 'L1'), { status: 'matched', driverId: 'driver1', bookingId: 'B1', matchedAt: serverTimestamp() });
    b.update(doc(db, 'vehicles', 'v1'), { availability: 'on_trip' });
    b.update(doc(db, 'offers', 'L1_driver1'), { status: 'confirmed', bookingId: 'B1', updatedAt: serverTimestamp() });
    return b.commit();
  }

  test('driver offers on an open load with their own vehicle; parties read it', async () => {
    await seedOpenLoad();
    await assertSucceeds(setDoc(ref(as('driver1')), OFFER));
    await assertSucceeds(getDoc(ref(as('customer1'))));
    await assertFails(getDoc(ref(as('driver2'))));
    // Wrong id, someone else's vehicle, bad price, own load.
    await assertFails(setDoc(ref(as('driver1'), 'L1_x'), OFFER));
    await assertFails(setDoc(ref(as('driver2'), 'L1_driver2'), { ...OFFER, driverId: 'driver2' }));
    await assertFails(setDoc(ref(as('driver2'), 'L1_driver2'), { ...OFFER, driverId: 'driver2', vehicleId: 'v2', pricePaise: 10.5, originalPaise: 10.5 }));
    await assertFails(setDoc(ref(as('customer1'), 'L1_customer1'), { ...OFFER, driverId: 'customer1' }));
  });

  test('customer counters once, driver accepts the counter at that price', async () => {
    await seedOffer();
    await assertFails(updateDoc(ref(as('driver1')), { status: 'countered', counterPaise: 1 }));
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'countered', counterPaise: 2000000 }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'pending', pricePaise: 2100000 }));
    await assertSucceeds(updateDoc(ref(as('driver1')), { status: 'pending', pricePaise: 2000000 }));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'countered', counterPaise: 1500000 }), 'only one counter');
  });

  test('select, then the driver confirms by creating the booking at the agreed price', async () => {
    await seedOffer();
    await assertFails(confirmBatch(as('driver1')), 'not selected yet');
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'selected' }));
    await assertFails(confirmBatch(as('driver1'), { agreedFarePaise: 1 }));
    await assertSucceeds(confirmBatch(as('driver1')));
  });

  test('a booking cannot claim an agreed fare without a confirmed offer', async () => {
    await seedOpenLoad();
    await assertFails(acceptBatch(as('driver1'), 'L1', 'driver1', { agreedFarePaise: 1 }));
  });

  test('withdraw and reject; terminal offers stay terminal', async () => {
    await seedOffer();
    await assertFails(updateDoc(ref(as('customer1')), { status: 'withdrawn' }));
    await assertSucceeds(updateDoc(ref(as('driver1')), { status: 'withdrawn' }));
    await assertFails(updateDoc(ref(as('customer1')), { status: 'selected' }));
    await seedOffer({ status: 'selected' });
    await assertSucceeds(updateDoc(ref(as('customer1')), { status: 'rejected' }));
    await assertFails(updateDoc(ref(as('driver1')), { status: 'pending' }));
    await assertFails(deleteDoc(ref(as('driver1'))));
  });
});

describe('trip OTPs, proof of delivery and e-way bill', () => {
  const otpRef = (db) => doc(db, 'bookings', 'L1', 'secrets', 'otp');
  const step = (db, status, extra = {}) =>
    updateDoc(doc(db, 'bookings', 'L1'), { status, [`timeline.${status}`]: serverTimestamp(), updatedAt: serverTimestamp(), ...extra });

  test('only the customer creates and reads the OTPs; nobody changes them', async () => {
    await seedBooking();
    await assertFails(setDoc(otpRef(as('driver1')), OTPS));
    await assertFails(setDoc(otpRef(as('customer1')), { pickupOtp: '12345', deliveryOtp: '123456' }));
    await assertFails(setDoc(doc(as('customer1'), 'bookings', 'L1', 'secrets', 'other'), OTPS));
    await assertSucceeds(setDoc(otpRef(as('customer1')), OTPS));
    await assertSucceeds(getDoc(otpRef(as('customer1'))));
    await assertFails(getDoc(otpRef(as('driver1'))));
    await assertFails(setDoc(otpRef(as('customer1')), { pickupOtp: '000000', deliveryOtp: '000000' }));
    await assertFails(deleteDoc(otpRef(as('customer1'))));
  });

  test('pickup needs the right OTP and valid cargo details', async () => {
    await seedBooking('loading');
    await seed((s) => setDoc(otpRef(s), OTPS));
    const d = as('driver1');
    await assertFails(step(d, 'picked_up', { pickupOtp: '000000', pickupProof: PICKUP }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.deliveryOtp, pickupProof: PICKUP }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: { ...PICKUP, packages: 0 } }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: { ...PICKUP, extra: 1 } }));
    await assertFails(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP, budget: 1 }));
    await assertSucceeds(step(d, 'picked_up', { pickupOtp: OTPS.pickupOtp, pickupProof: PICKUP }));
  });

  test('delivery needs the delivery OTP and a receiver name', async () => {
    await seedBooking('unloading');
    await seed((s) => setDoc(otpRef(s), OTPS));
    const d = as('driver1');
    const close = (extra) => {
      const b = writeBatch(d);
      b.update(doc(d, 'bookings', 'L1'), { status: 'delivered', 'timeline.delivered': serverTimestamp(), updatedAt: serverTimestamp(), ...extra });
      b.update(doc(d, 'loads', 'L1'), { status: 'closed', closedAt: serverTimestamp() });
      return b.commit();
    };
    await assertFails(close({ deliveryOtp: OTPS.pickupOtp, deliveryProof: DELIVERY }));
    await assertFails(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: { ...DELIVERY, receiverName: '' } }));
    await assertFails(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: { ...DELIVERY, receiverPhone: 'abc' } }));
    await assertSucceeds(close({ deliveryOtp: OTPS.deliveryOtp, deliveryProof: DELIVERY }));
  });

  test('without the customer secret nobody can pick up', async () => {
    await seedBooking('loading');
    await assertFails(step(as('driver1'), 'picked_up', { pickupOtp: '123456', pickupProof: PICKUP }));
  });

  test('driver may cancel while arriving but not once loading', async () => {
    await seedBooking('driver_arriving');
    const cancel = (db) => {
      const b = writeBatch(db);
      b.update(doc(db, 'bookings', 'L1'), { status: 'cancelled', 'timeline.cancelled': serverTimestamp(), cancellation: { by: 'driver', chargePaise: 0 }, updatedAt: serverTimestamp() });
      b.update(doc(db, 'loads', 'L1'), { status: 'open', driverId: deleteField(), bookingId: deleteField(), matchedAt: deleteField(), reopenedAt: serverTimestamp() });
      return b.commit();
    };
    await assertSucceeds(cancel(as('driver1')));
    await seedBooking('loading');
    await assertFails(cancel(as('driver1')));
  });

  test('either party records a 12-digit e-way bill number', async () => {
    await seedBooking('in_transit');
    await assertSucceeds(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: '123456789012', updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(as('driver1'), 'bookings', 'L1'), { ewayBillNo: '', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: 'EWB-1' }));
    await assertFails(updateDoc(doc(as('customer1'), 'bookings', 'L1'), { ewayBillNo: '123456789012', status: 'delivered' }));
    await assertFails(updateDoc(doc(as('driver2'), 'bookings', 'L1'), { ewayBillNo: '123456789012' }));
  });
});

describe('booking chat', () => {
  const msg = (sender, text = 'Namaste', extra = {}) => ({ senderId: sender, text, flagged: false, createdAt: serverTimestamp(), ...extra });
  const msgs = (db) => collection(db, 'bookings', 'L1', 'messages');

  test('both parties send and read; outsiders cannot', async () => {
    await seedBooking();
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')));
    await assertSucceeds(addDoc(msgs(as('driver1')), msg('driver1', 'On my way', { flagged: true })));
    await assertSucceeds(getDocs(msgs(as('driver1'))));
    await assertFails(getDocs(msgs(as('driver2'))));
    await assertFails(addDoc(msgs(as('driver2')), msg('driver2')));
  });

  test('length, sender, server time and immutability are enforced', async () => {
    await seedBooking();
    const db = as('customer1');
    await assertFails(addDoc(msgs(db), msg('customer1', '')));
    await assertFails(addDoc(msgs(db), msg('customer1', 'x'.repeat(501))));
    await assertFails(addDoc(msgs(db), msg('driver1')));
    await assertFails(addDoc(msgs(db), msg('customer1', 'hi', { createdAt: Timestamp.fromDate(new Date('2020-01-01')) })));
    await assertFails(addDoc(msgs(db), msg('customer1', 'hi', { extra: 1 })));
    await seed((s) => setDoc(doc(s, 'bookings', 'L1', 'messages', 'm1'), msg('customer1')));
    await assertFails(updateDoc(doc(db, 'bookings', 'L1', 'messages', 'm1'), { text: 'edited' }));
    await assertFails(deleteDoc(doc(db, 'bookings', 'L1', 'messages', 'm1')));
  });

  test('a blocked sender cannot message the person who blocked them', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('customer1'), 'users', 'customer1', 'blocked', 'driver1'), { createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(as('driver1'), 'users', 'customer1', 'blocked', 'driver1')));
    await assertFails(addDoc(msgs(as('driver1')), msg('driver1')));
    await assertSucceeds(addDoc(msgs(as('customer1')), msg('customer1')));
    await assertSucceeds(deleteDoc(doc(as('customer1'), 'users', 'customer1', 'blocked', 'driver1')));
    await assertSucceeds(addDoc(msgs(as('driver1')), msg('driver1')));
  });

  test('read marks are personal', async () => {
    await seedBooking();
    await assertSucceeds(setDoc(doc(as('driver1'), 'bookings', 'L1', 'chat_reads', 'driver1'), { lastReadAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver1'), 'bookings', 'L1', 'chat_reads', 'customer1'), { lastReadAt: serverTimestamp() }));
    await assertFails(setDoc(doc(as('driver2'), 'bookings', 'L1', 'chat_reads', 'driver2'), { lastReadAt: serverTimestamp() }));
  });

  test('reports: only about the other booking party; admins review', async () => {
    await seedBooking();
    const rep = (by, about, extra = {}) => ({ reporterId: by, reportedId: about, bookingId: 'L1', reason: 'off_platform', details: '', status: 'open', createdAt: serverTimestamp(), ...extra });
    await assertSucceeds(setDoc(doc(as('customer1'), 'reports', 'r1'), rep('customer1', 'driver1')));
    await assertSucceeds(getDoc(doc(as('customer1'), 'reports', 'r1')));
    await assertFails(getDoc(doc(as('driver1'), 'reports', 'r1')));
    await assertSucceeds(getDoc(doc(asAdmin(), 'reports', 'r1')));
    await assertFails(setDoc(doc(as('driver2'), 'reports', 'r2'), rep('driver2', 'customer1')));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r3'), rep('customer1', 'driver2')));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r4'), rep('customer1', 'driver1', { reason: 'meh' })));
    await assertFails(setDoc(doc(as('customer1'), 'reports', 'r5'), rep('customer1', 'driver1', { status: 'resolved' })));
    await assertFails(updateDoc(doc(as('customer1'), 'reports', 'r1'), { status: 'resolved' }));
    await assertSucceeds(updateDoc(doc(asAdmin(), 'reports', 'r1'), { status: 'resolved', resolvedBy: 'admin1' }));
  });
});
