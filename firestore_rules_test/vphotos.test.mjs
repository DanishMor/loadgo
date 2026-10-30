// E18 vehicle photos: Firestore metadata (vehicles/{id}/photos/{slot}) and Storage files
// (users/{uid}/vphotos/{vehicleId}/{slot}). Run with the emulators (run-tests.sh).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collectionGroup, deleteDoc, doc, getDoc, getDocs, limit, query, serverTimestamp, setDoc, Timestamp, updateDoc, where } from 'firebase/firestore';

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
    await setDoc(doc(db, 'admins', 'verifier1'), { role: 'verifier' });
    await setDoc(doc(db, 'admins', 'support1'), { role: 'support' });
    await setDoc(doc(db, 'admins', 'super1'), { role: 'super' });
    await setDoc(doc(db, 'vehicles', 'v1'), { ownerId: 'driver1', number: 'MH12AB1234' });
    await setDoc(doc(db, 'vehicles', 'v1', 'photos', 'front'), { slot: 'front', path: 'users/driver1/vphotos/v1/front', status: 'pending', at: Timestamp.now() });
    await setDoc(doc(db, 'vehicles', 'v1', 'photos', 'plate'), { slot: 'plate', path: 'users/driver1/vphotos/v1/plate', status: 'pending', at: Timestamp.now() });
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const photo = (uid, slot) => doc(db(uid), 'vehicles', 'v1', 'photos', slot);
const meta = (slot, uid = 'driver1') => ({ slot, path: `users/${uid}/vphotos/v1/${slot}`, status: 'pending', at: serverTimestamp() });

test('the vehicle owner adds a pending photo record for a known slot, with its own path', async () => {
  await assertSucceeds(setDoc(photo('driver1', 'rear'), meta('rear')));
  await assertSucceeds(setDoc(photo('driver1', 'rc'), meta('rc')));
});

test('nobody else adds one; a wrong slot, path, status, time or extra field is refused', async () => {
  await assertFails(setDoc(photo('driver2', 'rear'), meta('rear', 'driver2')));
  await assertFails(setDoc(photo('driver1', 'roof'), meta('roof')));
  await assertFails(setDoc(photo('driver1', 'rear'), { ...meta('rear'), path: 'users/driver2/vphotos/v1/rear' }));
  await assertFails(setDoc(photo('driver1', 'rear'), { ...meta('rear'), status: 'approved' }));
  await assertFails(setDoc(photo('driver1', 'rear'), { ...meta('rear'), at: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(photo('driver1', 'rear'), { ...meta('rear'), verified: true }));
  await assertFails(setDoc(photo('driver1', 'badge'), { until: Timestamp.now(), by: 'driver1', at: serverTimestamp() }));
});

test('outside views and the badge are readable by signed-in people; plate and RC only by the owner and admins', async () => {
  await assertSucceeds(getDoc(photo('cust1', 'front')));
  await assertFails(getDoc(photo('cust1', 'plate')));
  await assertSucceeds(getDoc(photo('driver1', 'plate')));
  await assertSucceeds(getDoc(photo('support1', 'plate')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'vehicles', 'v1', 'photos', 'front')));
});

test('a verifier approves or rejects with a reason; the owner cannot approve; support admins cannot review', async () => {
  const review = (status, extra = {}) => ({ status, reviewedAt: serverTimestamp(), reviewedBy: 'verifier1', ...extra });
  await assertSucceeds(updateDoc(photo('verifier1', 'front'), review('approved')));
  await assertSucceeds(updateDoc(photo('verifier1', 'plate'), review('rejected', { reason: 'blurry' })));
  await assertFails(updateDoc(photo('verifier1', 'front'), review('rejected')));
  await assertFails(updateDoc(photo('verifier1', 'front'), review('rejected', { reason: 'ugly' })));
  await assertFails(updateDoc(photo('verifier1', 'front'), { ...review('approved'), path: 'x' }));
  await assertFails(updateDoc(photo('driver1', 'front'), { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'driver1' }));
  await assertFails(updateDoc(photo('support1', 'front'), { status: 'approved', reviewedAt: serverTimestamp(), reviewedBy: 'support1' }));
});

test('a new photo by the owner goes back to pending; the owner deletes a record, never the badge', async () => {
  await assertSucceeds(setDoc(photo('driver1', 'front'), meta('front')));
  await assertSucceeds(deleteDoc(photo('driver1', 'front')));
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'vehicles', 'v1', 'photos', 'badge'), { until: Timestamp.now(), by: 'verifier1', at: Timestamp.now() }));
  await assertFails(deleteDoc(photo('driver1', 'badge')));
});

test('only a verifier sets the Photo-verified badge, for at most about six months', async () => {
  const until = (days) => Timestamp.fromMillis(Date.now() + days * 86400000);
  await assertSucceeds(setDoc(photo('verifier1', 'badge'), { until: until(180), by: 'verifier1', at: serverTimestamp() }));
  await assertFails(setDoc(photo('verifier1', 'badge'), { until: until(400), by: 'verifier1', at: serverTimestamp() }));
  await assertFails(setDoc(photo('verifier1', 'badge'), { until: until(180), by: 'someone', at: serverTimestamp() }));
  await assertFails(setDoc(photo('support1', 'badge'), { until: until(180), by: 'support1', at: serverTimestamp() }));
});

test('the review queue: super and verifier admins list pending photos across vehicles (at most 50); nobody else', async () => {
  const queue = (uid, n = 50) => getDocs(query(collectionGroup(db(uid), 'photos'), where('status', '==', 'pending'), limit(n)));
  await assertSucceeds(queue('verifier1'));
  await assertSucceeds(queue('super1'));
  await assertFails(queue('verifier1', 51));
  await assertFails(getDocs(query(collectionGroup(db('verifier1'), 'photos'), where('status', '==', 'pending'))));
  await assertFails(queue('support1'));
  await assertFails(queue('driver1'));
  await assertFails(queue('cust1'));
});

// ---- Storage ----
const image = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpeg = { contentType: 'image/jpeg' };
const store = (uid) => env.authenticatedContext(uid).storage();
const seed = (path) => env.withSecurityRulesDisabled((ctx) => ctx.storage().ref(path).put(image, jpeg));

test('storage: the owner uploads images under 3 MB to a known slot; others and other types are refused', async () => {
  await assertSucceeds(store('driver1').ref('users/driver1/vphotos/v1/front').put(image, jpeg));
  await assertFails(store('driver2').ref('users/driver1/vphotos/v1/front').put(image, jpeg));
  await assertFails(store('driver1').ref('users/driver1/vphotos/v1/roof').put(image, jpeg));
  await assertFails(store('driver1').ref('users/driver1/vphotos/v1/front').put(image, { contentType: 'image/svg+xml' }));
  await assertFails(store('driver1').ref('users/driver1/vphotos/v1/front').put(new Uint8Array(3 * 1024 * 1024 + 1), jpeg));
});

test('storage: outside views are seen by signed-in people; plate and RC only by the owner and admins', async () => {
  await seed('users/driver1/vphotos/v1/front');
  await seed('users/driver1/vphotos/v1/plate');
  await assertSucceeds(store('cust1').ref('users/driver1/vphotos/v1/front').getMetadata());
  await assertFails(store('cust1').ref('users/driver1/vphotos/v1/plate').getMetadata());
  await assertSucceeds(store('driver1').ref('users/driver1/vphotos/v1/plate').getMetadata());
  await assertSucceeds(store('verifier1').ref('users/driver1/vphotos/v1/plate').getMetadata());
  await assertFails(env.unauthenticatedContext().storage().ref('users/driver1/vphotos/v1/front').getMetadata());
});
