'use strict';
// G13: ID checks (driving licence, RC, PAN, GSTIN, Aadhaar LAST FOUR) behind a provider interface.
// No partner is chosen yet, so two providers exist:
//   * sandbox     : deterministic, for tests and demos. The last character decides: 0 = not found,
//                   9 or Z = mismatch, anything else = verified with a made-up name. It never calls out.
//   * unavailable : the default when config/kyc.provider is not "sandbox" - the app falls back to the
//                   format check and the admin looks at the papers (manual review).
// A real partner is one more provider with the same two-line interface: lookup(kind, number) -> {status, holderName?}.
// The server:
//   * accepts the caller only when signed in, checks the FORMAT again (a modified app is not trusted),
//   * never accepts a full Aadhaar number: only exactly 4 digits and nothing is looked up for them,
//   * limits each person per day and everybody per day (quota.js),
//   * writes the result (status and time, plus the name the record carries for the admin to compare) to
//     kyc_checks/{uid}, which only the Admin SDK writes and only admins read - the user document is not used,
//     because a user can edit their own user document;
//   * keeps the number itself out of every log and out of kyc_checks.

const { safeId, text } = require('./common');
const { consume } = require('./quota');

class KycError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code; // 'invalid-argument' | 'unauthenticated' | 'unavailable'
  }
}

const KINDS = Object.freeze(['licence', 'rc', 'pan', 'gstin', 'aadhaar']);
const FORMAT = Object.freeze({
  licence: /^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$/,
  rc: /^(?:[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}|[0-9]{2}BH[0-9]{4}[A-Z]{2})$/,
  pan: /^[A-Z]{5}[0-9]{4}[A-Z]$/,
  gstin: /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/,
  aadhaar: /^[0-9]{4}$/, // the last four digits only
});
const DEFAULTS = Object.freeze({ perUser: 6, total: 300 });

function normalise(s) {
  return typeof s === 'string' ? s.toUpperCase().replace(/[^A-Z0-9]/g, '') : '';
}

const sandboxProvider = {
  name: 'sandbox',
  async lookup(kind, number) {
    if (kind === 'aadhaar') return { status: 'unavailable' }; // nothing is looked up from four digits
    const last = number[number.length - 1];
    if (last === '0') return { status: 'not_found' };
    if (last === '9' || last === 'Z') return { status: 'mismatch', holderName: 'Sandbox Other Person' };
    return { status: 'verified', holderName: 'Sandbox Holder' };
  },
};

const unavailableProvider = {
  name: 'unavailable',
  async lookup() {
    return { status: 'unavailable' };
  },
};

async function providerFor(db, injected) {
  if (injected) return injected;
  const cfg = ((await db.collection('config').doc('kyc').get()).data()) || {};
  return cfg.provider === 'sandbox' ? sandboxProvider : unavailableProvider;
}

async function verify(db, callerUid, input, { provider, nowMs = Date.now() } = {}) {
  if (!safeId(callerUid)) throw new KycError('unauthenticated', 'sign in first');
  const kind = input && input.kind;
  if (!KINDS.includes(kind)) throw new KycError('invalid-argument', 'kind');
  const number = normalise(input.number);
  if (!FORMAT[kind].test(number)) throw new KycError('invalid-argument', 'format');
  const cfg = ((await db.collection('config').doc('kyc').get()).data()) || {};
  const p = await providerFor(db, provider);
  // A provider that cannot answer costs nothing and uses no quota: the admin reviews by eye.
  if (p.name === 'unavailable') return { status: 'unavailable' };
  await consume(db, 'kyc', callerUid, DEFAULTS, cfg, nowMs);
  let r;
  try {
    r = await p.lookup(kind, number);
  } catch {
    throw new KycError('unavailable', 'partner not reachable');
  }
  const status = ['verified', 'mismatch', 'not_found', 'unavailable'].includes(r && r.status) ? r.status : 'unavailable';
  const holderName = status === 'verified' || status === 'mismatch' ? text(r.holderName, 60) : '';
  await db.collection('kyc_checks').doc(callerUid).set(
    { [kind]: { status, ...(holderName ? { holderName } : {}), at: new Date(nowMs), provider: p.name } },
    { merge: true },
  );
  return { status, ...(holderName ? { holderName } : {}) };
}

module.exports = { verify, KycError, KINDS, FORMAT, normalise, sandboxProvider, unavailableProvider, DEFAULTS };
