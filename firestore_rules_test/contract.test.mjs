// Rules vs real app writes (Part 5). contract/captured.json is produced by
// test/rules_contract_capture_test.dart from the REAL Dart services (what the app sends, field for field).
// Each scenario: seed the "before" database with the rules off, then replay the app's writes, as the same
// person, as ONE batch against firestore.rules. Every one must be allowed. If a rule rejects a field the app
// really sends, fix the RULE (the app is already in people's hands).
import { existsSync, readFileSync } from 'node:fs';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
import { assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { GeoPoint, Timestamp, deleteDoc, deleteField, doc, serverTimestamp, setDoc, terminate, updateDoc, writeBatch } from 'firebase/firestore';

const FILE = new URL('./contract/captured.json', import.meta.url);
if (!existsSync(FILE)) throw new Error('contract/captured.json is missing: run flutter test test/rules_contract_capture_test.dart');
const { scenarios, capturedAtMs } = JSON.parse(readFileSync(FILE, 'utf8'));
// Dates in the fixture (a bid window, a pickup date, a promo expiry) are relative to the day it was recorded: move them to today.
const SHIFT = Date.now() - capturedAtMs;

let env;
const opened = new Set();
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'loadgo-rules-test', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
after(() => env.cleanup());
afterEach(async () => {
  const list = [...opened];
  opened.clear();
  await Promise.all(list.map((d) => terminate(d._delegate ?? d).catch(() => {})));
});
beforeEach(() => env.clearFirestore());

// {"$ts": ms, "$server": bool} -> a Timestamp (seeds) or the server time (the app's own writes).
function decode(v, live) {
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map((x) => decode(x, live));
  if ('$ts' in v) return live && v.$server ? serverTimestamp() : Timestamp.fromMillis(v.$ts + SHIFT);
  if ('$geo' in v) return new GeoPoint(v.$geo[0], v.$geo[1]);
  return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, decode(x, live)]));
}
const ref = (db, path) => doc(db, ...path.split('/'));

describe('what the app really sends is allowed by the rules', () => {
  for (const s of scenarios) {
    test(`${s.name}  [${s.covers.join(', ')}]`, async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        for (const [path, data] of Object.entries(s.before)) await setDoc(ref(db, path), decode(data, false));
        await setDoc(ref(db, 'admins/admin1'), { createdBy: 'console' });
      });
      const db = env.authenticatedContext(s.actor).firestore();
      opened.add(db);
      // One commit per step: the app sometimes writes in two commits (a guess is stored first, then the step).
      for (const ops of s.steps) {
        const b = writeBatch(db);
        for (const op of ops) {
          if (op.op === 'create') b.set(ref(db, op.path), decode(op.data, true));
          else if (op.op === 'update') {
            const fields = decode(op.changed, true);
            for (const k of op.removed) fields[k] = deleteField();
            b.update(ref(db, op.path), fields);
          } else b.delete(ref(db, op.path));
        }
        await assertSucceeds(b.commit());
      }
    });
  }
});

test('the fixture covers what docs/RULES_CONTRACT.md says', () => {
  const covered = new Set(scenarios.flatMap((s) => s.covers));
  for (const c of ['loads', 'offers', 'bookings', 'vehicles', 'rate_limits']) if (!covered.has(c)) throw new Error(`${c} is not covered`);
  if (scenarios.length < 30) throw new Error(`only ${scenarios.length} scenarios`);
});
void updateDoc; void deleteDoc;
