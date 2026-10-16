'use strict';
// Shared helpers of every Cloud Function (F15). Plain functions that take the
// Firestore handle as an argument, so the same code runs in the emulator tests
// and in the deployed functions.

const REGION = 'asia-south1';

// All server features are OFF unless config/features.flags.<name> is exactly true
// (the same document and keys the app's Admin > Features screen writes).
const FLAGS = Object.freeze([
  'serverLimits',
  'serverChatScan',
  'serverCredits',
  'serverTrust',
  'serverJobs',
  'serverAdminActions',
  'serverDeletion',
  'serverWallet',
  'pushNotifications',
  'adminBroadcast',
  'photoUploads',
  'paymentGateway',
  'maps',
  'smsGateway',
  'kycVerify',
  'appCheckEnforce',
]);

const FLAG_TTL_MS = 30 * 1000;
const cache = new Map(); // db -> { at, flags }

async function readFlags(db, now = Date.now()) {
  const hit = cache.get(db);
  if (hit && now - hit.at < FLAG_TTL_MS) return hit.flags;
  let flags = {};
  try {
    const snap = await db.collection('config').doc('features').get();
    const raw = snap.exists ? snap.data().flags : null;
    if (raw && typeof raw === 'object') flags = raw;
  } catch {
    flags = {}; // cannot read the switches: everything stays off
  }
  cache.set(db, { at: now, flags });
  return flags;
}

async function flagOn(db, name, now) {
  if (!FLAGS.includes(name)) return false;
  return (await readFlags(db, now))[name] === true;
}

function clearFlagCache() {
  cache.clear();
}

// A defensive read of whole paise: anything that is not a safe integer is 0.
function paise(v) {
  return Number.isSafeInteger(v) ? v : 0;
}

// Strings from documents: never throw, never huge.
function text(v, max = 200) {
  return typeof v === 'string' ? v.slice(0, max) : '';
}

// An id that is safe to use as a document id or a path part.
function safeId(v) {
  return typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v) ? v : null;
}

module.exports = { REGION, FLAGS, readFlags, flagOn, clearFlagCache, paise, text, safeId };
