# Threat model (Part 5, H1)

Method: STRIDE on each asset, then the top attacks. "Caught by" names the test that fails if the defence is removed. `RT` = the red-team suite (`firestore_rules_test/redteam.test.mjs`, H2). `rules` = `firestore_rules_test/rules.test.mjs`. `fn` = `functions/test`.

Trust boundary: the phone app is **untrusted** (a modified client can send anything). Firestore rules and Cloud Functions are the only enforcement. Functions are written but not deployed (BLOCKED.md); until then rules are the only server-side layer.

STRIDE letters: S spoofing, T tampering, R repudiation, I information disclosure, D denial of service, E elevation of privilege.

## Assets

| Asset | S | T | R | I | D | E | Main defence | Gap |
|---|---|---|---|---|---|---|---|---|
| Accounts and OTP | Phone OTP by Firebase Auth; delivery/pickup OTP stored in `bookings/*/secrets/otp`, compared in rules | role, riskTier, plan, verified frozen for the owner | audit_events append-only | users readable by owner and admin only | SMS pumping limited by `limitCall`/sms quota | role escalation blocked (frozen fields) | OTP attempt counter is a function (not deployed) | App Check not enforced |
| Driver documents and photos | owner path in storage | immutable once verified | audit on decision | vehicle papers readable by any signed-in user (risk 4 in SECURITY_REVIEW) | size/type limits in storage.rules | only admin sets verification | KNOWN_RISKS |  |
| Wallet and ledger | ledger rows tied to driver uid | append-only, integers, no update/delete | ledger is the record | owner and admin read | reconcile job | only server writes balance (function) | functions pending deploy | client-written ledger lines until deploy |
| Bids and dispatch | ids derived from load+driver | price int paise, band 30%..300%, state machine | offers kept | a driver cannot read other drivers' bids | per-load/hourly limits | only the winner transaction creates the booking | wave enforcement is server-side only after deploy | ring visibility is a client layer |
| Chat and call | party check | content filter (`chatTextClean`) | messages immutable | admin reads only with `chat_reviews` | 20 calls/hour | suspended sender blocked | spelled-out numbers (client filter only) |  |
| Bilty and share links | long random token | share doc immutable snapshot | | token is the secret; snapshot fields only | | | no PII in snapshot (H12) |  |
| Admin panel | `admins/{uid}` doc | writes only through explicit rules | audit_events | staff roles see only their slice | | maker-checker on money | `admins` not writable by clients | staff role escalation test (RT) |
| Cloud Functions | auth + App Check (monitor) | input schema | structured logs | no internals in errors | maxInstances, timeouts | authorization re-read from DB | see FUNCTIONS_SECURITY.md | |
| Hosting pages | | | | noindex, no-store on token pages | | | headers (H12) | |
| Payment webhook | raw-body signature | amount from server | idempotent event id | | timestamp tolerance | | H6 | not live until keys exist |
| Push | tokens per user | server sends | | no payload secrets | topic limits | | payload treated as untrusted in client (H10) | |

## Top attacks

| # | Attack | Defence today | Gap | Caught by |
|---|---|---|---|---|
| 1 | Account takeover (SIM swap, stolen phone) | Phone OTP, optional biometric lock, session list | no device binding | rules (frozen fields), fn auth tests |
| 2 | Fake driver or customer | admin verification, riskTier, document checks | KYC is format-only | RT: verified flag self-set |
| 3 | Fare or bid manipulation | band 30%..300% of estimate, int paise, one active bid per driver | estimate is client computed until fn | RT: negative/zero/float/huge price |
| 4 | Commission bypass (go off-platform) | contact filter in rules and app, strikes | spelled-out numbers | rules chat tests, contact_filter tests |
| 5 | Wallet or payout fraud | append-only ledger, maker-checker payout, reconcile | deploy pending | RT: ledger update/delete, self-approval; fn wallet tests |
| 6 | Scraping and enumeration | no unfiltered list on private collections, ids unguessable | trucks board/ratings open by design | matrix.test.mjs frozen LISTABLE list, RT list-without-filter |
| 7 | Admin takeover | `admins` doc only from console, no claim grants | console account security | rules admins tests, RT staff escalation |
| 8 | SMS pumping, OTP abuse | Firebase quotas, `limitCall`, sms quota | not enforced until deploy | fn limits/sms tests |
| 9 | Cost attack (bill increase) | per-user/hour limits in rules, query limits, listener caps, COST_WATCH | alert thresholds (H32) | cost_guards_test, RT: oversize array/map |
| 10 | Insider misuse | audit_events, chat_reviews gate, admin views logged | staff with console access | rules audit tests |
| 11 | Replay | state machine (no jump back), request.time on timestamps, webhook event id | | RT: replay old doc, timestamp spoof |
| 12 | Race (two drivers accept) | transaction + rules (open to matched once) | | concurrency tests U41, RT race |
| 13 | Supply chain | pinned lockfiles, no major bumps, workflows pinned (H14) | transitive packages | H8/H14 audit docs |

## How to read a gap
Gaps marked "deploy pending" close when `docs/BLOCKED.md` steps are done. Gaps marked "client only" go to `docs/KNOWN_RISKS.md` (H34).
