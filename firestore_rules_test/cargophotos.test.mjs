// E19 cargo photos: goods photos of a load (loads/{id}/cargo/{slot} in Firestore and Storage) and seal photos
// on a trip (bookings/{id}/proofs + bookings/{id}/seal/{file}). Run with the emulators (run-tests.sh).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins', 'support1'), { role: 'support' });
    await setDoc(doc(db, 'loads', 'L1'), { shipperId: 'cust1', status: 'open' });
    await setDoc(doc(db, 'loads', 'L2'), { shipperId: 'cust1', status: 'booked', driverId: 'drv1' });
    await setDoc(doc(db, 'loads', 'L2', 'cargo', 'goods1'), { slot: 'goods1', path: 'loads/L2/cargo/goods1', at: Timestamp.now() });
    await setDoc(doc(db, 'bookings', 'B1'), { customerId: 'cust1', driverId: 'drv1', status: 'confirmed' });
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const cargo = (uid, load, slot) => doc(db(uid), 'loads', load, 'cargo', slot);
const meta = (load, slot) => ({ slot, path: `loads/${load}/cargo/${slot}`, at: serverTimestamp() });

test('the shipper adds a goods photo record to one of three slots while the load is open', async () => {
  await assertSucceeds(setDoc(cargo('cust1', 'L1', 'goods1'), meta('L1', 'goods1')));
  await assertSucceeds(setDoc(cargo('cust1', 'L1', 'goods3'), meta('L1', 'goods3')));
});

test('nobody else; no fourth slot, wrong path, old time, extra field, or a booked load', async () => {
  await assertFails(setDoc(cargo('cust2', 'L1', 'goods1'), meta('L1', 'goods1')));
  await assertFails(setDoc(cargo('drv1', 'L1', 'goods1'), meta('L1', 'goods1')));
  await assertFails(setDoc(cargo('cust1', 'L1', 'goods4'), meta('L1', 'goods4')));
  await assertFails(setDoc(cargo('cust1', 'L1', 'goods1'), { ...meta('L1', 'goods1'), path: 'loads/L2/cargo/goods1' }));
  await assertFails(setDoc(cargo('cust1', 'L1', 'goods1'), { ...meta('L1', 'goods1'), at: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(cargo('cust1', 'L1', 'goods1'), { ...meta('L1', 'goods1'), note: 'x' }));
  await assertFails(setDoc(cargo('cust1', 'L2', 'goods2'), meta('L2', 'goods2')));
});

test('read where the load is readable: open loads by signed-in people; a booked load by its shipper, its driver and admins', async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'loads', 'L1', 'cargo', 'goods1'), { slot: 'goods1', path: 'loads/L1/cargo/goods1', at: Timestamp.now() }));
  await assertSucceeds(getDoc(cargo('drv2', 'L1', 'goods1')));
  await assertSucceeds(getDocs(collection(db('drv2'), 'loads', 'L1', 'cargo')));
  await assertSucceeds(getDoc(cargo('cust1', 'L2', 'goods1')));
  await assertSucceeds(getDoc(cargo('drv1', 'L2', 'goods1')));
  await assertSucceeds(getDoc(cargo('support1', 'L2', 'goods1')));
  await assertFails(getDoc(cargo('drv2', 'L2', 'goods1')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'loads', 'L1', 'cargo', 'goods1')));
});

test('only the shipper deletes a goods photo record', async () => {
  await assertFails(deleteDoc(cargo('drv1', 'L2', 'goods1')));
  await assertSucceeds(deleteDoc(cargo('cust1', 'L2', 'goods1')));
});

const proof = (uid, id, kind) => setDoc(doc(db(uid), 'bookings', 'B1', 'proofs', id), {
  kind, path: `bookings/B1/${kind}/${id}.jpg`, size: 1000, contentType: 'image/jpeg', by: uid, createdAt: serverTimestamp(),
});

test('seal photo record: the trip driver adds one; the customer and strangers cannot', async () => {
  await assertSucceeds(proof('drv1', 'p1', 'seal'));
  await assertFails(proof('cust1', 'p2', 'seal'));
  await assertFails(proof('drv2', 'p3', 'seal'));
  await assertFails(proof('drv1', 'p4', 'sealed'));
});

// ---- Storage ----
const image = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpeg = { contentType: 'image/jpeg' };
const store = (uid) => env.authenticatedContext(uid).storage();
const seed = (path) => env.withSecurityRulesDisabled((ctx) => ctx.storage().ref(path).put(image, jpeg));

test('storage: the shipper uploads images under 3 MB to a goods slot of an open load; nothing else', async () => {
  await assertSucceeds(store('cust1').ref('loads/L1/cargo/goods2').put(image, jpeg));
  await assertFails(store('cust2').ref('loads/L1/cargo/goods2').put(image, jpeg));
  await assertFails(store('cust1').ref('loads/L1/cargo/goods9').put(image, jpeg));
  await assertFails(store('cust1').ref('loads/L2/cargo/goods2').put(image, jpeg));
  await assertFails(store('cust1').ref('loads/L1/cargo/goods2').put(image, { contentType: 'image/svg+xml' }));
  await assertFails(store('cust1').ref('loads/L1/cargo/goods2').put(new Uint8Array(3 * 1024 * 1024 + 1), jpeg));
});

test('storage: goods photos are read where the load is readable', async () => {
  await seed('loads/L1/cargo/goods1');
  await seed('loads/L2/cargo/goods1');
  await assertSucceeds(store('drv2').ref('loads/L1/cargo/goods1').getMetadata());
  await assertSucceeds(store('drv1').ref('loads/L2/cargo/goods1').getMetadata());
  await assertSucceeds(store('support1').ref('loads/L2/cargo/goods1').getMetadata());
  await assertFails(store('drv2').ref('loads/L2/cargo/goods1').getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref('loads/L1/cargo/goods1').getMetadata());
});

test('storage: seal photos are added by the trip driver only and never replaced', async () => {
  await assertSucceeds(store('drv1').ref('bookings/B1/seal/a.jpg').put(image, jpeg));
  await assertFails(store('cust1').ref('bookings/B1/seal/b.jpg').put(image, jpeg));
  await assertFails(store('drv1').ref('bookings/B1/seal/a.jpg').put(image, jpeg));
  await assertSucceeds(store('cust1').ref('bookings/B1/seal/a.jpg').getMetadata());
});
