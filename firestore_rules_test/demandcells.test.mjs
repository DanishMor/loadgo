// E36 demand cells: server-written counts; clients read, never write.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, limit, query, setDoc, Timestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'loadgo-rules-test', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'demand_cells', 'te7u'), { openLoads: 4, updatedAt: Timestamp.now() }));
});

test('signed-in people read a cell or a few; strangers and big lists are refused; nobody writes', async () => {
  const db = env.authenticatedContext('drv1').firestore();
  await assertSucceeds(getDoc(doc(db, 'demand_cells', 'te7u')));
  await assertSucceeds(getDocs(query(collection(db, 'demand_cells'), limit(9))));
  await assertFails(getDocs(collection(db, 'demand_cells')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'demand_cells', 'te7u')));
  await assertFails(setDoc(doc(db, 'demand_cells', 'te7u'), { openLoads: 99, updatedAt: Timestamp.now() }));
});
