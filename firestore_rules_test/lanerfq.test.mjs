// E30 lane tenders: lane_rfqs/{id} and lane_rfqs/{id}/bids/{bidderUid}. Run with the emulators (run-tests.sh).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where, deleteDoc } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'loadgo-rules-test', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
after(() => env.cleanup());
const days = (n) => Timestamp.fromMillis(Date.now() + n * 86400000);
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'admins', 'admin1'), { createdBy: 'console' });
    for (const [uid, role] of [['biz1', 'customer'], ['biz2', 'customer'], ['flt1', 'fleet'], ['drv1', 'driver'], ['cust9', 'customer'], ['ban1', 'fleet']]) {
      await setDoc(doc(db, 'users', uid), { role, selectedRole: role, ...(uid === 'ban1' ? { riskTier: 'banned' } : {}) });
    }
    const base = { ownerId: 'biz1', ownerName: 'Shah Textiles', fromCity: 'Surat', toCity: 'Delhi', vehicleType: '32ft', tripsPerMonth: 20, months: 3, note: '', status: 'open', createdAt: Timestamp.now() };
    await setDoc(doc(db, 'lane_rfqs', 'R1'), { ...base, closesAt: days(7) });
    await setDoc(doc(db, 'lane_rfqs', 'RX'), { ...base, closesAt: days(-1) });
    await setDoc(doc(db, 'lane_rfqs', 'RA'), { ...base, status: 'awarded', closesAt: days(7) });
    await setDoc(doc(db, 'lane_rfqs', 'R1', 'bids', 'flt1'), { bidderId: 'flt1', bidderName: 'Co', ratePaise: 6500000, note: '', at: Timestamp.now() });
  });
});

const db = (uid) => env.authenticatedContext(uid).firestore();
const rfq = (over = {}) => ({ ownerId: 'biz1', ownerName: 'Shah Textiles', fromCity: 'Surat', toCity: 'Delhi', vehicleType: '32ft', tripsPerMonth: 20, months: 3, note: 'Weekly', closesAt: days(10), status: 'open', createdAt: serverTimestamp(), ...over });
const bid = (uid, over = {}) => ({ bidderId: uid, bidderName: 'Co', ratePaise: 6400000, note: '', at: serverTimestamp(), ...over });

test('an owner posts a tender with sane numbers; anything off is refused', async () => {
  await assertSucceeds(setDoc(doc(db('biz1'), 'lane_rfqs', 'N1'), rfq()));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N2'), rfq({ ownerId: 'biz2' })));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N3'), rfq({ tripsPerMonth: 0 })));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N4'), rfq({ months: 13 })));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N5'), rfq({ closesAt: days(40) })));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N6'), rfq({ status: 'awarded' })));
  await assertFails(setDoc(doc(db('biz1'), 'lane_rfqs', 'N7'), rfq({ priceHint: 1 })));
  await assertFails(setDoc(doc(db('ban1'), 'lane_rfqs', 'N8'), rfq({ ownerId: 'ban1' })));
});

test('open tenders are listed with a filter; closed ones only by the owner and admins', async () => {
  await assertSucceeds(getDocs(query(collection(db('flt1'), 'lane_rfqs'), where('status', '==', 'open'))));
  await assertFails(getDocs(collection(db('flt1'), 'lane_rfqs')));
  await assertFails(getDoc(doc(db('flt1'), 'lane_rfqs', 'RA')));
  await assertSucceeds(getDoc(doc(db('biz1'), 'lane_rfqs', 'RA')));
  await assertSucceeds(getDoc(doc(db('admin1'), 'lane_rfqs', 'RA')));
});

test('transporters and drivers bid once each (their uid), only while open, never on their own tender', async () => {
  await assertSucceeds(setDoc(doc(db('drv1'), 'lane_rfqs', 'R1', 'bids', 'drv1'), bid('drv1')));
  await assertSucceeds(setDoc(doc(db('flt1'), 'lane_rfqs', 'R1', 'bids', 'flt1'), bid('flt1', { ratePaise: 6300000 })));
  await assertFails(setDoc(doc(db('flt1'), 'lane_rfqs', 'R1', 'bids', 'drv1'), bid('flt1')));
  await assertFails(setDoc(doc(db('cust9'), 'lane_rfqs', 'R1', 'bids', 'cust9'), bid('cust9')));
  await assertFails(setDoc(doc(db('flt1'), 'lane_rfqs', 'RX', 'bids', 'flt1'), bid('flt1')));
  await assertFails(setDoc(doc(db('flt1'), 'lane_rfqs', 'RA', 'bids', 'flt1'), bid('flt1')));
  await assertFails(setDoc(doc(db('drv1'), 'lane_rfqs', 'R1', 'bids', 'drv1'), bid('drv1', { ratePaise: 50 })));
  await assertFails(setDoc(doc(db('drv1'), 'lane_rfqs', 'R1', 'bids', 'drv1'), bid('drv1', { awarded: true })));
  await assertFails(deleteDoc(doc(db('flt1'), 'lane_rfqs', 'R1', 'bids', 'flt1')));
});

test('bids are seen by their bidder and the owner, not by other bidders', async () => {
  await assertSucceeds(getDoc(doc(db('flt1'), 'lane_rfqs', 'R1', 'bids', 'flt1')));
  await assertSucceeds(getDoc(doc(db('biz1'), 'lane_rfqs', 'R1', 'bids', 'flt1')));
  await assertSucceeds(getDocs(collection(db('biz1'), 'lane_rfqs', 'R1', 'bids')));
  await assertFails(getDoc(doc(db('drv1'), 'lane_rfqs', 'R1', 'bids', 'flt1')));
  await assertFails(getDocs(collection(db('drv1'), 'lane_rfqs', 'R1', 'bids')));
});

test('the owner awards a real bid at its own rate, or closes; nobody else; never twice', async () => {
  const award = (uid, over = {}) => updateDoc(doc(db(uid), 'lane_rfqs', 'R1'), { status: 'awarded', awardedTo: 'flt1', awardedRatePaise: 6500000, decidedAt: serverTimestamp(), ...over });
  await assertFails(award('flt1'));
  await assertFails(award('biz1', { awardedRatePaise: 100 }));
  await assertFails(award('biz1', { awardedTo: 'drv1' }));
  await assertFails(award('biz1', { tripsPerMonth: 99 }));
  await assertSucceeds(award('biz1'));
  await assertFails(updateDoc(doc(db('biz1'), 'lane_rfqs', 'R1'), { status: 'closed', decidedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db('biz1'), 'lane_rfqs', 'RX'), { status: 'closed', decidedAt: serverTimestamp() }));
});
