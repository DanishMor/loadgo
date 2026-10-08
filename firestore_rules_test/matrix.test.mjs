// MASTER-5 Task 44: a generated role x collection x operation matrix.
//
// The collections are read from firestore.rules itself, so a new `match` is
// covered the moment it is added. Three properties are checked for each:
//
//  1. nobody who is signed out can read, list, create, update or delete
//     (except the two public share links, read by their long random token);
//  2. a signed-in person cannot create a junk document anywhere (every create
//     rule has a field whitelist), and cannot delete or update one that is not theirs;
//  3. which collections a signed-in customer / driver / transporter can list
//     without a filter is a frozen list: a new one must be added here on purpose.
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, test } from 'node:test';
import { assertFails, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, terminate, updateDoc } from 'firebase/firestore';

const RULES = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');
const COLLECTIONS = [...new Set([...RULES.matchAll(/^ {4}match \/([a-z_]+)\/\{/gm)].map((m) => m[1]))];

let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'loadgo-rules-test', firestore: { rules: RULES } });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' });
    for (const [uid, role] of [['cust1', 'customer'], ['drv1', 'driver'], ['flt1', 'fleet'], ['cust2', 'customer']]) {
      await setDoc(doc(db, 'users', uid), { role, selectedRole: role, phone: '+919800000000' });
    }
  });
});
after(() => env.cleanup());

const opened = new Set();
const as = (uid) => {
  const d = uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
  opened.add(d);
  return d;
};
afterEach(async () => {
  const list = [...opened];
  opened.clear();
  await Promise.all(list.map((d) => terminate(d._delegate ?? d).catch(() => {})));
});

// Documents a signed-out person may read by id: the share links (unguessable tokens).
const PUBLIC_GET = new Set(['trip_shares', 'lr_shares']);

// Collections a signed-in person may list WITHOUT a filter. Frozen on purpose.
// Everything else needs a query the rules can prove (own id, status, party ...).
// truck_posts is the empty-trucks board: open to every signed-in person by design (no phone numbers on it).
const LISTABLE_BY_ANY_SIGNED_IN = new Set(['vehicles', 'ratings', 'config', 'promos', 'incentives', 'truck_posts']);

describe('collections found in firestore.rules', () => {
  test('the list is not empty and has the ones we know', () => {
    for (const c of ['users', 'loads', 'bookings', 'lrs', 'calls', 'violations', 'config', 'admins']) {
      if (!COLLECTIONS.includes(c)) throw new Error(`${c} not found in ${COLLECTIONS}`);
    }
  });
});

describe('signed out', () => {
  for (const c of COLLECTIONS) {
    test(`${c}: no list, no create, no update, no delete${PUBLIC_GET.has(c) ? ' (a get by token is public)' : ', no get'}`, async () => {
      const db = as(null);
      if (!PUBLIC_GET.has(c)) await assertFails(getDoc(doc(db, c, 'x1')));
      await assertFails(getDocs(collection(db, c)));
      await assertFails(setDoc(doc(db, c, 'x1'), { x: 1 }));
      await assertFails(updateDoc(doc(db, c, 'x1'), { x: 1 }));
      await assertFails(deleteDoc(doc(db, c, 'x1')));
    });
  }
});

describe('signed in as customer, driver and transporter', () => {
  for (const c of COLLECTIONS) {
    test(`${c}: a junk create, an update or a delete of someone else's document fails`, async () => {
      for (const uid of ['cust1', 'drv1', 'flt1']) {
        const db = as(uid);
        // a junk document with fields no create rule allows, under an id nobody owns
        // (users/{uid}: only your own id could ever pass, so test a stranger's)
        await assertFails(setDoc(doc(db, c, 'zz_not_mine_zz'), { junk: 1, role: 'admin', riskTier: 'normal', verified: true }));
        await assertFails(updateDoc(doc(db, c, 'zz_not_mine_zz'), { junk: 1 }));
        await assertFails(deleteDoc(doc(db, c, 'zz_not_mine_zz')));
      }
    });
  }

  test('which collections can be listed without any filter is the frozen list', async () => {
    const found = {};
    for (const [uid, label] of [['cust1', 'customer'], ['drv1', 'driver'], ['flt1', 'transporter']]) {
      const db = as(uid);
      for (const c of COLLECTIONS) {
        let ok = true;
        try {
          await getDocs(collection(db, c));
        } catch {
          ok = false;
        }
        if (ok) (found[label] ??= new Set()).add(c);
      }
    }
    for (const [label, set] of Object.entries(found)) {
      const extra = [...set].filter((c) => !LISTABLE_BY_ANY_SIGNED_IN.has(c));
      if (extra.length) throw new Error(`${label} can list without a filter: ${extra.join(', ')} - review the rules or add them to LISTABLE_BY_ANY_SIGNED_IN`);
    }
  });
});

describe('admin-only collections stay closed to every non-admin role', () => {
  const ADMIN_ONLY_READ = ['audit_events', 'fraud_cases', 'app_errors', 'risk_signals', 'rating_flags'];
  for (const c of ADMIN_ONLY_READ) {
    test(`${c}: customer, driver and transporter cannot read`, async () => {
      for (const uid of ['cust1', 'drv1', 'flt1']) {
        const db = as(uid);
        await assertFails(getDocs(collection(db, c)));
        await assertFails(getDoc(doc(db, c, 'x1')));
      }
    });
  }
});
