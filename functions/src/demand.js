'use strict';
// E36 (switch: demandFeed, OFF): counts open loads by pickup area (geohash of 4 characters, about 40 km) into
// demand_cells/{cell} = { openLoads, updatedAt }. Counts only: no load id, place name or person. Clients read the
// cells near them (the app's DemandFeed) and never write them (firestore.rules).

const { Timestamp } = require('firebase-admin/firestore');

const CELL_LEN = 4;
const MAX_LOADS = 500;
const MAX_CELLS = 400;

// Open-load counts per cell from load documents. Loads without a usable pickupGeohash are skipped.
function countCells(loads) {
  const out = {};
  for (const l of loads) {
    const g = l && typeof l.pickupGeohash === 'string' ? l.pickupGeohash.toLowerCase() : '';
    if (!/^[0-9b-hjkmnp-z]{4,12}$/.test(g)) continue;
    const cell = g.slice(0, CELL_LEN);
    out[cell] = (out[cell] || 0) + 1;
  }
  return out;
}

// Reads at most MAX_LOADS open loads and writes their cells (at most MAX_CELLS), plus a zero for cells that
// were busy before and are empty now, so a stale count does not linger.
async function writeDemandCells(db, nowMs = Date.now()) {
  const snap = await db.collection('loads').where('status', '==', 'open').limit(MAX_LOADS).get();
  const counts = countCells(snap.docs.map((d) => d.data()));
  const prev = await db.collection('demand_cells').where('openLoads', '>', 0).limit(MAX_CELLS).get();
  const at = Timestamp.fromMillis(nowMs);
  const batch = db.batch();
  let writes = 0;
  for (const [cell, n] of Object.entries(counts).slice(0, MAX_CELLS)) {
    batch.set(db.collection('demand_cells').doc(cell), { openLoads: n, updatedAt: at });
    writes++;
  }
  for (const d of prev.docs) {
    if (!(d.id in counts) && writes < 499) {
      batch.set(d.ref, { openLoads: 0, updatedAt: at });
      writes++;
    }
  }
  if (writes > 0) await batch.commit();
  return { cells: Object.keys(counts).length, writes };
}

module.exports = { CELL_LEN, MAX_LOADS, countCells, writeDemandCells };
