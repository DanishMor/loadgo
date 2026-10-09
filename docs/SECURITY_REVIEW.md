# Firestore rules security review

Reviewed 2026-10-04 against `firestore.rules` (every collection) and `firestore_rules_test/rules.test.mjs`.
Method: list each `match`, check who can read, who can create/update/delete, which fields are validated, and whether a test pins it.

## Deny by default
- Firestore denies anything not matched. A final `match /{document=**}` with `allow read, write: if false` states it explicitly; a test checks that a made-up collection is closed, even for admins.
- `delete` is `false` everywhere except for the owner's own convenience data (saved places, branches, favourite routes, blocked list, notifications, vehicles, `vehicle_numbers` while freeing a number, `loads` while still open).

## Admin gate
- `isAdmin()` is `exists(admins/{uid})`. `admins/{uid}` is readable only by that user and never writable from a client, so only the Firebase Console (or Admin SDK) can add an admin. The old `admin` custom claim no longer grants anything (tested).
- Admin powers are explicit per collection: read users/loads/bookings/tickets/SOS/reports/ledger/audit/shipments/deletion requests; decide driver verification; set `riskTier`; suspend vehicles; edit config; handle tickets, SOS, reports, deletion requests; reassign a booking before pickup (one batch: booking + load + audit event). Admins cannot otherwise edit loads or bookings.

## Collections

| Collection | Read | Write | Field validation | Tested |
|---|---|---|---|---|
| `users/{uid}` | owner, admin | owner (no `verified*`, no risk fields, `cancelCount` only +1), admin (verification or risk only) | emergency contacts <= 3, prefs/consents boolean maps, `business.gstin` format | yes |
| `users/*/blocked`, `saved_places`, `branches`, `favourite_routes` | owner | owner | keys whitelist, sizes, enum types | yes |
| `vehicles`, `vehicle_numbers` | vehicles: any signed-in user; numbers: `get` only | owner (admin: availability only) | required keys, type/capacity, docs keys, RC URL must be Firebase Storage, number reserved atomically | yes |
| `loads` | open loads: any signed-in; otherwise shipper, matched driver, admin | shipper (open only), accepting driver (with booking), driver close/reopen, admin reassign | full `validLoad` (stops, estimate shape, prohibited goods regex, container/seal/branch/shipment fields), `canTransact` | yes |
| `bookings` (+ `messages`, `chat_reads`, `secrets/otp`) | the two parties, admin | driver steps one status at a time, OTP must equal the secret; customer: e-way bill + "marked paid"; create has a key whitelist and a timeline of `accepted` only | OTP 6 digits, proof shapes, cancellation shape, `cancelCount` bumped in the same batch | yes |
| `offers` | the two parties | driver/customer transitions in a fixed state machine | price int paise 1..1e8, ids derived from load+driver | yes |
| `ledger` | driver, admin | driver, append-only, together with payment confirmation | earning = amount marked paid, commission <= half | yes |
| `tickets` (+ `replies`), `sos_alerts`, `reports` | owner/reporter, admin | owner create/escalate/close, admin manage | enums, sizes, booking-party checks | yes |
| `audit_events` | admin | any signed-in user appends events about themselves; `verification`, `risk_change`, `reassign` admin only; `createdAt == request.time` | type enum, key whitelist | yes |
| `ratings` | any signed-in | rater after delivery, once | stars 1..5, id = booking + rater | yes |
| `notifications` | recipient | counter-party creates; recipient only marks `read` | type enum, both are booking parties | yes |
| `config` | any signed-in | admin | size caps | yes |
| `shipments` | owner, admin | owner create only (immutable) | enums, container/seal format | yes |
| `deletion_requests` | owner, admin | owner (one pending), admin status | key whitelist | yes |
| `admins` | own doc | nobody | | yes |

## Fixed during this review
- Booking creation had no field whitelist, so a driver could pre-fill fields such as `pickupOtpVerified` or `deliveryProof`, or a timeline that already contained `delivered`. It now requires the exact set of fields the app writes and a timeline of `accepted` only.
- Added the explicit catch-all deny and a test for it.

## Known risks (accepted for the free stack, each needs Cloud Functions / Blaze)
1. **Audit log can be skipped or forged for user events.** Clients write `accept`, `status_change` and `cancel` events themselves. Fix: write them from Firestore triggers. `// TODO(functions)`.
2. **Fares, commission and payout are computed on the client.** Rules only check shapes and limits (commission <= half of the amount). A server must be authoritative before real money moves. `// TODO(functions)`.
3. **OTP guessing is not rate-limited.** A driver can retry the 6-digit delivery OTP. A function should count attempts per booking. `// TODO(functions)`.
4. **Vehicle documents are readable by every signed-in user** (needed for matching and the customer vehicle count), including insurance/PUC policy numbers. Move paper numbers to a private subcollection if this is not acceptable.
5. **Off-platform chat detection runs in the client.** The rules now refuse the plain cases (a 10-digit mobile number or an `@` in a message, `chatTextClean`) and a suspended sender (`chatAllowed`), but spelled-out numbers, apps and "call me" are caught only by the app (`ContactFilter`). A modified client can send those; strikes are recorded by the client too. A server check would stop that. `// TODO(functions)`.
6. **Account deletion is manual.** `deletion_requests` is only a request; an admin deletes data in the Console. A function should do it.
7. **GSTIN, RC, insurance are format-checked only.** Nothing proves they are real (needs paid KYC APIs).
8. **`users` documents allow extra, unvalidated fields from the owner** (for example `language`, `fcmTokens`). None of them grants any permission, because all privileged data lives in server-controlled collections or admin-only fields.

## MASTER-3: Transporter, private chat and call

Reviewed with rules tests written first (`transporter security (Phase 2)`, `private chat and call (Task 68)`, `transporter (Task 67)` in `firestore_rules_test/rules.test.mjs`).

* **Admin comes only from `admins/{uid}`.** The collection cannot be read as a list or written by anyone; a transporter cannot read or write it, a custom claim or a user field changes nothing (tests).
* **Transporters see only their own data.** Books (`transporter_accounts`), invites and members are owner-only; other transporters, customers and drivers get permission-denied on them; `users/{uid}` of someone else is unreadable and not listable.
* **Frozen fields.** `role`, `selectedRole`, `riskTier`, `plan`, `verified`, `verificationStatus`, `reviewFlag`, `cancelCount`, `docOverrideUntil` and the chat strike fields cannot be written by the owner (except the ladder steps). `bookings.fleetOwnerId` is set only at creation, for a user with role `fleet`, and never changes. A ledger (wallet) line needs the booking holder and a confirmed payment.
* **Assignment.** Only the booking holder assigns, only to an active member, only an own or attached vehicle of a member who is still in the fleet, only before loading ends. The assigned driver can move the trip (OTP rules unchanged), share position, chat, and close the load at delivery; cannot change money, papers, the assignment or cancel.
* **Phone numbers.** New bookings cannot store one (`driverPhone == ''`); calls and violations store none; admin views are logged first.
* **Calls.** Only the two people of an unfinished booking, never while suspended, at most 20 per hour, small SDP and candidates, status moves in order.
* **Admin reading a chat** needs a `chat_reviews/{bookingId}` document, which needs a report or a dispute about the same booking.
* **Rule-size limit.** The load-create rule was at the 1000-expression limit; a repeated call (`validPromoShape`) was removed and the new `postedByRole` check is one conditional. Re-run the whole rules suite after any change to `validLoad`.
* **Known gaps** (need Cloud Functions): strikes and audit lines are written by the client; the strike block end may be up to an hour early (phone clock); the contact filter cannot see a picture of a number; calls use STUN only.

## How to re-run
`cd firestore_rules_test && npm ci && npm test` (needs Java for the emulator). CI runs it on every push.

## MASTER-5 Task 2: hourly abuse limits (coverage)
Counted per user per hour in `rate_limits/{uid}_{kind}` (bumped in the same batch, checked by the rules): load 30, offer 60, chat message 120, call 20, **ticket 10 (new)**.
Not counted, and why: one-off or naturally unique documents (ratings = one per booking, invoices = one per booking, claims, deletion requests, `lr_series` counters, `identity_index`), documents that need a confirmed booking with the other party (OTP steps, signatures, cargo docs), and owner-only convenience data (saved places, templates). LR share links and violations are bounded by their parent LR / booking. A server-side counter for the rest is `// TODO(functions)`.

## MASTER-6: threat model, client-only checks, pentest checklist (Task 47)

### Who could attack, and what they want
| Actor | Wants | Main doors | What stops them today |
|---|---|---|---|
| Curious or hostile customer | other people's numbers, free trips, a rival's loads | chat, call, share links, queries | numbers never stored on bookings, chat filter + rules `chatTextClean`, share links with end date and revoke, owner-only reads |
| Dishonest driver or transporter | take the deal off-app, fake delivery, fake documents, many accounts | chat, OTP steps, KYC upload, sign-up | strikes and suspension, pickup/delivery OTP in rules, identity index, role lock, admin review |
| Account farmer (pilot) | free credits, invite abuse, waitlist spam | invite codes, referral, waitlist | one redemption per person (id = code + uid), code use count and expiry in rules, waitlist id = uid + route, rate limits |
| Modified app or script | skip client checks | any Firestore write | rules shape checks (below), but see "client-only checks" |
| Malicious or mistaken staff | read or change too much | admin screens | role-named rules (`super`, `support`, `verifier`, `ops`, `finance`), audit log, undo window on bulk actions, staff never list other staff |
| Someone with a lost phone | use an open session | the app | sign-out and "my devices" screen, session watcher, OTP login |

### New collections reviewed in MASTER-6 (rules tests pin each one)
| Collection | Read | Write | Notes |
|---|---|---|---|
| `invite_codes` | any signed-in person can `get` one code they already know (8 random characters from a 32-letter set, so guessing is impractical); only admins list | super, ops create/edit; the redeemer only adds 1 to `uses` inside the redeem batch | expiry, `active` and max uses are checked in rules; anyone holding a code can see its role/route/expiry |
| `invite_redemptions` | the person, admin | create once per person (doc id is the user id), in the same batch that adds 1 to the code's `uses` | a person redeems one code once; the use count must go up by exactly 1 |
| `pilot_whitelist` | a person reads only the entry of their own phone digits; admin lists | super, ops create | entries are phone digits (10 to 15), keep the list short and delete after the pilot |
| `waitlist` | the person, admin | the person once per route (`uid_from_to`) | route text length capped |
| `dispatch_suggestions` | the suggested driver, admin | super, ops create; id is load + driver so one per pair | the driver can only answer their own |
| `trip_surveys` | admin; the answerer | answerer once per trip and side | counts only, no free text |
| `payment_nudges` | the target person, admin | super, ops, support, finance; id is booking + side, so a nudge is counted, not repeated | no free text, only a count and time |
| `config_history` | admin | admin, append-only | rollback copies; never deleted |
| `strike_appeals` | the person, admin | the person once per strike within 14 days; support/ops decide once | text 10 to 300 characters |
| `bookings/*/inspection_log` | the issuer reads all; the trip driver reads their own lines | append-only | no edit, no delete |
| `app_errors.crumbs` | super, ops | any signed-in user appends (string up to 600) | breadcrumbs hold screen names only and are cleaned (`Redactor`) |

### Checks that run only in the app (a modified app can skip them)
Everything here needs a server (Cloud Functions, Blaze) before it can be trusted with real money or real abuse. Each is marked `TODO(functions)` in code.
1. Chat contact filter and strike counting (rules refuse plain 10-digit numbers and `@`; spelled-out numbers and "call me" pass if the app is modified).
2. Fare, commission, GST, cancel charge and payout amounts (rules check shape and limits, not the maths).
3. Pickup/delivery OTP guess limit (an attacker with a valid session can keep guessing 6 digits).
4. Invite code rules for "open sign-up when the switch is off": the gate is in the app; a modified app can still create a profile. Rules protect the codes, not the sign-up.
5. Trust numbers on the driver's own screen are computed on the phone; showing them to others needs a server-written summary.
6. Rate limits per hour are counted in the app and checked by rules only where a `rate_limits` document exists.
7. Time: some windows use the phone clock (strike block end, drafts, appeals window); rules use `request.time` where it matters (appeals window, invites).
8. KYC numbers, GSTIN, RC and insurance are format checked only.
9. Account deletion is a request an admin carries out.
10. Release build shrinking (R8) is untested here (no Android SDK).

### Pentest checklist for the owner (or a hired tester)
Do this on a test project, with test accounts, never on real users. Write each result in docs/BUG_REPORT.md.
1. **Rules:** with the Firestore emulator or a second test project, run `firestore_rules_test` (`npm test`); then try, with a plain signed-in customer token, to read `users` of someone else, `admins`, `audit_events`, `app_errors`, `invite_codes`, `strike_appeals` of another person. All must be denied.
2. **Role lock:** change `role` on your own profile through a REST call. Must be denied.
3. **Booking tamper:** as a driver set `pickupOtpVerified: true` or a `delivered` step without the code. Must be denied.
4. **Numbers:** send a chat message with a 10-digit number through the REST API (skip the app). Must be denied by rules; then send "nau aath saat..." (spelled digits): this passes today (known gap 1).
5. **OTP guessing:** count how many wrong delivery codes are accepted before any block (known gap 3).
6. **Invite:** redeem the same code twice, an expired code, a code at its max uses, someone else's whitelist. All must fail except the first valid one.
7. **Share links:** open an LR link after it is revoked and after it ended. Must show "not available". Try changing the id in the link: must show nothing.
8. **Admin roles:** sign in as `support` and try a payout (finance) and a verification decision (verifier). Must be denied.
9. **Storage:** `storage.rules` tests (`npm test` runs them): upload a 6 MB image and a PDF as a normal user. Must be denied.
10. **Hosting:** check headers of every page (`test/hosting_headers_test.dart` lists them): nosniff, frame deny, referrer policy; the legal pages carry the DRAFT mark until a lawyer signs off.
11. **Secrets:** search the repo and the APK for keys and passwords (`git grep -nEi "apikey|secret|password" -- ':!*.md'`); the only values allowed are the public Firebase client config. `android/key.properties` and keystores must not be in git.
12. **Dependencies:** run `flutter pub outdated` and `npm audit` in `firestore_rules_test` once a quarter and note the result.
