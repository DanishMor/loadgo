'use strict';
// G15: App Check on our callable functions, in two stages.
//   1. MONITOR (default): a call that arrives without a valid App Check token is only counted in the logs
//      ("app_check_missing" with the function name; no user id, no data), so the owner can see how many real
//      calls would be refused before turning enforcement on.
//   2. ENFORCE: when config/features.flags.appCheckEnforce is exactly true, such a call is refused.
// Firebase fills request.app only when the token is valid, so this needs nothing else. Enabling order: docs/APP_CHECK.md.

const { flagOn } = require('./common');

class AppCheckError extends Error {
  constructor() {
    super('app check');
    this.code = 'failed-precondition';
  }
}

// request: the onCall request. log: console-like (tests pass a fake).
async function guard(db, request, fnName, log = console) {
  if (request && request.app) return { checked: true };
  log.warn(JSON.stringify({ event: 'app_check_missing', fn: String(fnName).slice(0, 40) }));
  if (await flagOn(db, 'appCheckEnforce')) throw new AppCheckError();
  return { checked: false };
}

module.exports = { guard, AppCheckError };
