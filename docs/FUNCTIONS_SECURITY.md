# Cloud Functions security checklist (Part 5, H5 to H8)

Nothing is deployed. This is the review of the code as written, with the test that keeps each line true.

## The checklist (applies to every callable, HTTP function and trigger)

| # | Check | How it is met | Pinned by |
|---|---|---|---|
| 1 | Switch first | Every function reads `config/features.flags.<name>` and does nothing unless it is exactly `true` (all OFF). `serverStatus` is the one exception: staff only, to test a deploy. | `test/unit/hardening.test.js` "every callable ... switch" |
| 2 | Authentication | Callables that act for a person use `request.auth.uid`; `safeId()` refuses a missing or odd uid (`unauthenticated`). Staff actions call `requireStaff(db, uid, roles)`. | `fuzz.test.js` (every caller value), `adminActions.test.js` |
| 3 | App Check | `appCheckGuard` on the paid or ID-touching callables (payments, KYC, SMS, maps). Monitor first, `appCheckEnforce` flag later (`docs/SECURITY_DECISIONS.md`). Staff-only callables do not use it (the staff check is stronger). | `appCheck.test.js` |
| 4 | Input schema | Every action validates types, lengths and enums itself and refuses with a typed `invalid-argument`; unknown extra fields are ignored, never written. Ids go through `safeId` (no `/`, no `..`, length). Money goes through `paise()` / `validPaise()` (safe integers only). | `fuzz.test.js`: 36 hostile values x 11 callers x 6 actions, plus the webhook |
| 5 | Authorization re-read from the database | Roles come from `admins/{uid}`, never from the request. A payout's state, a booking's parties and a driver's papers are read inside the transaction. Unknown staff role = no rights (BUG_REPORT H-1). | `adminActions.test.js`, `fuzz.test.js` |
| 6 | Idempotency | Payout decisions move through states and refuse a repeat (`failed-precondition`); the approver cannot pay (maker-checker); webhook events are recorded by event id and a repeat is a 200 that does nothing; ledger and wallet recompute is a pure function of the lines. | `fuzz.test.js` "replay and double calls", `razorpay*.test.js` |
| 7 | Per-user rate and cost limits | `quota.consume` (per person and total, per day) for SMS, maps and KYC; `limits.enforce` for loads, offers, messages, calls, tickets; `maxInstances` on every function. | `quota`, `limits`, `sms`, `maps`, `kyc` tests |
| 8 | No internal errors to the caller | Wrappers turn a typed error into an `HttpsError` with its short text and everything else into `HttpsError('internal', 'failed')`; the log line carries `e.message` only. | `hardening.test.js` "never return or log a raw error" |
| 9 | Timeout and memory | Explicit: 60 s, 256 MiB, 10 instances (`setGlobalOptions`). Schedules are idempotent per page. | `hardening.test.js` "limits are explicit" |
| 10 | Retry safe | Triggers read the document they react to and write with set-by-id or in a transaction; a retry gives the same state. The wave and the jobs skip work already done. | `dispatch`, `jobs`, `wallet` tests |
| 11 | Secrets | Only `defineSecret` (Razorpay key id and secret, webhook secret, MSG91 key, Maps server key). No literal in `src` or `index.js`. | `hardening.test.js` "secrets come from Secret Manager only" |
| 12 | Logs redacted | `console.error` prints a short fixed text and `e.message`; App Check logs the function name only; no user id and no request data in a log line. | `hardening.test.js` "logs" |

## Payment webhook (H6)
- The raw body (`req.rawBody`) is verified against `x-razorpay-signature` with the webhook secret (HMAC SHA-256, constant-time compare). A bad or missing signature gives 400 and nothing is read.
- Replay: the event id (`x-razorpay-event-id`, 1 to 64 safe characters) is claimed with `payment_events/{id}.create()`; a repeat gets 200 'duplicate' and does nothing. If processing fails, the claim is deleted so Razorpay can retry.
- Amounts: `settleOrder` compares the amount reported by the webhook with the amount stored on our own order. A difference marks the order `mismatch` and pays nothing. A settled order is never settled again (a second payment id is refused).
- Timestamp tolerance: Razorpay signs only the body, with no timestamp header, so tolerance cannot be checked on the request. A very old replay of a signed body is stopped by the event-id claim and the order state. Keep `payment_events` for at least 30 days (do not put a short TTL on it).
- Switch off: 200 and nothing is read, so Razorpay does not retry for days.
- Tests: `razorpay.test.js` (unit, signature), `razorpayStale.test.js`, `razorpayHold.test.js`, `fuzz.test.js` "webhook: junk bodies".

## Fuzz tests (H7)
`functions/test/emulator/fuzz.test.js` (emulator): wrong types, 200 KB strings, NaN, Infinity, `__proto__` bodies, a path in an id, 500-level nesting, someone else's uid, undefined and object callers, a replayed approval, two finance people paying at once, ten parallel risk-tier changes. Outcome rule: finish, or refuse with a typed error; never a `TypeError`, never a stack line in a message, never a change to a user or payout that the caller had no right to change.

## Dependencies (H8)
- `npm audit`: functions 0 vulnerabilities. `firestore_rules_test` (test tools only) 16 findings in `firebase` / `firebase-tools` and their dependencies; not shipped; fixing means major upgrades, so left for a planned tools upgrade (`docs/KNOWN_RISKS.md` 13).
- `functions/package.json`: `engines.node` is `22`, lockfile committed, only `firebase-admin` and `firebase-functions` as runtime dependencies (nothing unused). CI uses `npm ci` for the rules tests.

## Gaps (not closed by code today)
- The functions are not deployed; until then the rules are the only server-side layer (`docs/KNOWN_RISKS.md` 2).
- `adminCallable` (staff actions) has no App Check call on purpose; revisit when enforcement is on.
