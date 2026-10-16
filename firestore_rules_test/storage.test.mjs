// Cloud Storage rules tests. Run with: npm test  (starts the emulators)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
    // Storage rules read bookings and admins from Firestore.
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins', 'adm1'), { createdBy: 'console' });
    await setDoc(doc(db, 'bookings', 'B1'), { driverId: 'driver1', customerId: 'cust1', status: 'loading' });
    await setDoc(doc(db, 'bookings', 'B2'), { driverId: 'fleet1', assignedDriverId: 'driver9', customerId: 'cust2', status: 'loading' });
  });
});

const image = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpeg = { contentType: 'image/jpeg' };
const rcPath = 'vehicles/driver1/v1/rc.jpg';
const storageAs = (uid) => env.authenticatedContext(uid).storage();

test('only the owner uploads their RC image', async () => {
  await assertSucceeds(storageAs('driver1').ref(rcPath).put(image, jpeg));
  await assertFails(storageAs('driver2').ref(rcPath).put(image, jpeg));
  await assertFails(env.unauthenticatedContext().storage().ref(rcPath).put(image, jpeg));
});

test('any signed-in user can view; anonymous cannot', async () => {
  await env.withSecurityRulesDisabled((ctx) => ctx.storage().ref(rcPath).put(image, jpeg));
  await assertSucceeds(storageAs('customer1').ref(rcPath).getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref(rcPath).getMetadata());
});

test('only images under 5 MB are accepted', async () => {
  await assertFails(storageAs('driver1').ref(rcPath).put(image, { contentType: 'application/pdf' }));
  await assertFails(storageAs('driver1').ref(rcPath).put(new Uint8Array(5 * 1024 * 1024 + 1), jpeg));
});

test('other paths are closed', async () => {
  await assertFails(storageAs('driver1').ref('random/file.jpg').put(image, jpeg));
});

// ---- F28: papers, truck photos and trip proof ----
const put = (uid, path, data = image, meta = jpeg) => storageAs(uid).ref(path).put(data, meta);
const seedFile = (path) => env.withSecurityRulesDisabled((ctx) => ctx.storage().ref(path).put(image, jpeg));
const big = new Uint8Array(5 * 1024 * 1024 + 1);

test('papers: the owner writes a known kind, as an image under 5 MB', async () => {
  const p = 'users/driver1/docs/licence/a1.jpg';
  await assertSucceeds(put('driver1', p));
  await assertSucceeds(put('driver1', 'users/driver1/docs/rc/a1.jpg', image, { contentType: 'image/png' }));
  await assertSucceeds(put('driver1', 'users/driver1/docs/insurance/a1.webp', image, { contentType: 'image/webp' }));
  await assertSucceeds(put('driver1', 'users/driver1/docs/licence/a1.jpg'), 'replace the photo');
  await assertFails(put('driver2', p), 'not the owner');
  await assertFails(env.unauthenticatedContext().storage().ref(p).put(image, jpeg));
  await assertFails(put('driver1', 'users/driver1/docs/aadhaar/a1.jpg'), 'Aadhaar is never uploaded');
  await assertFails(put('driver1', 'users/driver1/docs/licence/a2.pdf', image, { contentType: 'application/pdf' }), 'not an image');
  await assertFails(put('driver1', 'users/driver1/docs/licence/a3.jpg', big), 'over 5 MB');
  await assertFails(put('driver1', 'users/driver1/docs/licence/a4.jpg', new Uint8Array(0)), 'empty');
  await assertFails(put('driver1', 'users/driver1/docs/licence/a5.gif', image, { contentType: 'image/gif' }), 'gif is not taken');
});

test('papers: only the owner and an admin read; other signed-in people and strangers cannot', async () => {
  const p = 'users/driver1/docs/licence/a1.jpg';
  await seedFile(p);
  await assertSucceeds(storageAs('driver1').ref(p).getMetadata());
  await assertSucceeds(storageAs('adm1').ref(p).getMetadata());
  await assertFails(storageAs('cust1').ref(p).getMetadata());
  await assertFails(storageAs('driver2').ref(p).getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref(p).getMetadata());
  await assertSucceeds(storageAs('driver1').ref(p).delete());
});

test('papers: another person cannot delete', async () => {
  const p = 'users/driver1/docs/licence/a1.jpg';
  await seedFile(p);
  await assertFails(storageAs('driver2').ref(p).delete());
  await assertFails(storageAs('adm1').ref(p).delete());
});

test('truck photos: the owner writes, any signed-in person looks', async () => {
  const p = 'users/driver1/trucks/v1/front.jpg';
  await assertSucceeds(put('driver1', p));
  await assertFails(put('driver2', p));
  await assertFails(put('driver1', 'users/driver1/trucks/v1/x.jpg', big));
  await assertSucceeds(storageAs('cust1').ref(p).getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref(p).getMetadata());
});

test('trip proof: the trip driver writes pickup, delivery and pod; the customer does not', async () => {
  await assertSucceeds(put('driver1', 'bookings/B1/pickup/p1.jpg'));
  await assertSucceeds(put('driver1', 'bookings/B1/delivery/d1.jpg'));
  await assertSucceeds(put('driver1', 'bookings/B1/pod/s1.jpg'));
  await assertFails(put('cust1', 'bookings/B1/pickup/p2.jpg'));
  await assertFails(put('driver2', 'bookings/B1/pickup/p2.jpg'), 'a driver of another trip');
  await assertFails(put('driver1', 'bookings/B2/pickup/p1.jpg'), 'not this driver');
  await assertSucceeds(put('driver9', 'bookings/B2/pickup/p1.jpg'), 'the driver a transporter assigned');
  await assertFails(put('driver1', 'bookings/B1/selfie/p1.jpg'), 'unknown kind');
  await assertFails(put('driver1', 'bookings/B1/pickup/p3.jpg', big));
  await assertFails(put('driver1', 'bookings/B1/pickup/p4.jpg', image, { contentType: 'text/html' }));
  await assertFails(put('driver1', 'bookings/NOPE/pickup/p1.jpg'), 'no such booking');
});

test('damage evidence: the driver or the customer writes, nobody else', async () => {
  await assertSucceeds(put('driver1', 'bookings/B1/damage/e1.jpg'));
  await assertSucceeds(put('cust1', 'bookings/B1/damage/e2.jpg'));
  await assertFails(put('cust2', 'bookings/B1/damage/e3.jpg'));
  await assertFails(put('driver2', 'bookings/B1/damage/e3.jpg'));
});

test('trip proof: both sides and admins read; strangers do not; nothing is changed or deleted', async () => {
  const p = 'bookings/B1/pod/s1.jpg';
  await seedFile(p);
  await assertSucceeds(storageAs('driver1').ref(p).getMetadata());
  await assertSucceeds(storageAs('cust1').ref(p).getMetadata());
  await assertSucceeds(storageAs('adm1').ref(p).getMetadata());
  await assertFails(storageAs('cust2').ref(p).getMetadata());
  await assertFails(storageAs('driver2').ref(p).getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref(p).getMetadata());
  await assertFails(put('driver1', p), 'evidence is not overwritten');
  await assertFails(storageAs('driver1').ref(p).delete());
  await assertFails(storageAs('adm1').ref(p).delete());
});

test('the older vehicle RC place still works as before', async () => {
  await assertSucceeds(put('driver1', rcPath));
  await assertSucceeds(storageAs('cust1').ref(rcPath).getMetadata());
});

test('the rules file names no public link and no wildcard read', async () => {
  const rules = readFileSync(new URL('../storage.rules', import.meta.url), 'utf8');
  assert.ok(!/allow read: if true/.test(rules));
  assert.ok(!/allow write: if true/.test(rules));
  assert.ok(/match \/\{allPaths=\*\*\}[^}]*allow read, write: if false/s.test(rules));
});
