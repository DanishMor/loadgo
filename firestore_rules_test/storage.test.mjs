// Cloud Storage rules tests. Run with: npm test  (starts the emulators)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'loadgo-rules-test',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearStorage());

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
