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
