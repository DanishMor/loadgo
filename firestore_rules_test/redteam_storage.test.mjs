// Part 5 (H2): red-team attacks on storage.rules. Every ATTACK must fail.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
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
  });
});

const image = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const jpeg = { contentType: 'image/jpeg' };
const st = (uid) => (uid ? env.authenticatedContext(uid).storage() : env.unauthenticatedContext().storage());
const put = (uid, path, data = image, meta = jpeg) => st(uid).ref(path).put(data, meta);
const seedFile = (path) => env.withSecurityRulesDisabled((ctx) => ctx.storage().ref(path).put(image, jpeg));

const attacks = [
  ['anonymous writes an RC', () => put(null, 'vehicles/driver1/v1/rc.jpg')],
  ['write into another owner RC folder', () => put('driver2', 'vehicles/driver1/v1/rc.jpg')],
  ['RC as SVG (script carrier)', () => put('driver1', 'vehicles/driver1/v1/rc.svg', image, { contentType: 'image/svg+xml' })],
  ['RC as HTML', () => put('driver1', 'vehicles/driver1/v1/rc.html', image, { contentType: 'text/html' })],
  ['RC empty file', () => put('driver1', 'vehicles/driver1/v1/rc.jpg', new Uint8Array(0))],
  ['RC over 5 MB', () => put('driver1', 'vehicles/driver1/v1/rc.jpg', new Uint8Array(5 * 1024 * 1024 + 1))],
  ['papers as SVG', () => put('driver1', 'users/driver1/docs/licence/a.svg', image, { contentType: 'image/svg+xml' })],
  ['papers as executable', () => put('driver1', 'users/driver1/docs/licence/a.exe', image, { contentType: 'application/x-msdownload' })],
  ['papers in another user folder', () => put('driver2', 'users/driver1/docs/licence/a.jpg')],
  ['papers with an invented kind', () => put('driver1', 'users/driver1/docs/passport/a.jpg')],
  ['papers one folder too deep', () => put('driver1', 'users/driver1/docs/licence/x/a.jpg')],
  ['truck photo as PDF', () => put('driver1', 'users/driver1/trucks/v1/a.pdf', image, { contentType: 'application/pdf' })],
  ['truck photo in another folder', () => put('driver2', 'users/driver1/trucks/v1/a.jpg')],
  ['customer writes pickup proof', () => put('cust1', 'bookings/B1/pickup/a.jpg')],
  ['stranger writes delivery proof', () => put('driver2', 'bookings/B1/delivery/a.jpg')],
  ['driver writes a proof of an invented kind', () => put('driver1', 'bookings/B1/secret/a.jpg')],
  ['proof for a booking that does not exist', () => put('driver1', 'bookings/NOPE/pickup/a.jpg')],
  ['proof as text', () => put('driver1', 'bookings/B1/pickup/a.txt', image, { contentType: 'text/plain' })],
  ['stranger writes damage evidence', () => put('driver2', 'bookings/B1/damage/a.jpg')],
  ['customer writes a seal photo (E19)', () => put('cust1', 'bookings/B1/seal/a.jpg')],
  ['goods photo for a load that does not exist (E19)', () => put('cust1', 'loads/NOPE/cargo/goods1')],
  ['random top-level path', () => put('driver1', 'public/a.jpg')],
  ['root file', () => put('driver1', 'a.jpg')],
  ['admin writes into a user papers folder', () => put('adm1', 'users/driver1/docs/licence/a.jpg')],
];
for (const [name, fn] of attacks) test(`ATTACK ${name}`, async () => assertFails(fn()));

test('ATTACK driver overwrites a proof', async () => {
  await seedFile('bookings/B1/pickup/a.jpg');
  await assertFails(put('driver1', 'bookings/B1/pickup/a.jpg'));
});
test('ATTACK driver deletes a proof', async () => {
  await seedFile('bookings/B1/pickup/a.jpg');
  await assertFails(st('driver1').ref('bookings/B1/pickup/a.jpg').delete());
});
test('ATTACK admin deletes a proof', async () => {
  await seedFile('bookings/B1/pickup/a.jpg');
  await assertFails(st('adm1').ref('bookings/B1/pickup/a.jpg').delete());
});
test('ATTACK stranger reads a proof', async () => {
  await seedFile('bookings/B1/pickup/a.jpg');
  await assertFails(st('driver2').ref('bookings/B1/pickup/a.jpg').getMetadata());
});
test('ATTACK anonymous reads a proof', async () => {
  await seedFile('bookings/B1/pickup/a.jpg');
  await assertFails(st(null).ref('bookings/B1/pickup/a.jpg').getMetadata());
});
test('ATTACK stranger reads someone else papers', async () => {
  await seedFile('users/driver1/docs/licence/a.jpg');
  await assertFails(st('driver2').ref('users/driver1/docs/licence/a.jpg').getMetadata());
});
test('ATTACK anonymous reads a truck photo', async () => {
  await seedFile('users/driver1/trucks/v1/a.jpg');
  await assertFails(st(null).ref('users/driver1/trucks/v1/a.jpg').getMetadata());
});
test('ATTACK stranger deletes someone else papers', async () => {
  await seedFile('users/driver1/docs/licence/a.jpg');
  await assertFails(st('driver2').ref('users/driver1/docs/licence/a.jpg').delete());
});

// Controls: the same shapes, done right, work (so the attacks above are not failing for a silly reason).
test('CONTROL owner writes an RC and papers; the trip driver writes proof; admin reads papers', async () => {
  await assertSucceeds(put('driver1', 'vehicles/driver1/v1/rc.jpg'));
  await assertSucceeds(put('driver1', 'users/driver1/docs/licence/a.jpg'));
  await assertSucceeds(put('driver1', 'bookings/B1/pickup/control-new.jpg'));
  await assertSucceeds(st('adm1').ref('users/driver1/docs/licence/a.jpg').getMetadata());
});
