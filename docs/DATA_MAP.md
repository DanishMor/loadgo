# Data map and PII inventory (Part 5, H15)

What personal data Load 20 holds, where, for how long, and who can read it. Built from `firestore.rules`, `storage.rules`, `docs/DATA_RETENTION.md` and the services. "Rules" means the person can read it only through the Firestore rules; "server" means only Cloud Functions / Admin SDK write it.

## Personal data by place

| Data | Where | Who can read | Who writes | Kept | Removed |
|---|---|---|---|---|---|
| Phone number (sign-in), name, language, consents | Firebase Auth; `users/{uid}` | the person; staff (admin console) | the person | while the account exists | account deletion (`deleteAccount`, `docs/DATA_RETENTION.md`) |
| Driver papers: licence number and expiry, RC number, PAN, last 4 of Aadhaar | `users/{uid}.driverKyc` | the person; staff | the person | while the account exists | deletion, or the driver edits |
| Papers as photos | Storage `users/{uid}/docs/{kind}/*` | the person; staff | the person | while the account exists | deletion (`users/{uid}/` is removed) |
| Truck photos, RC photo | Storage `users/{uid}/trucks/*`, `vehicles/{uid}/*` | every signed-in user (a customer sees the truck) | the owner | while the vehicle exists | owner deletes; account deletion |
| Hashes of licence / PAN / RC / GST | `identity_index` | staff | the person's app (create) | while the account exists | deletion |
| Last location (consent) | `users/{uid}.lastLocation` | the person; staff | the person | until the next update | consent off (at once), deletion |
| Trip position of the driver (consent) | `bookings/{id}.lastKnownLocation` | the two parties; staff | the driver | 24 h after the trip | `jobClearLocations`, deletion |
| Emergency contacts (up to 3: name, phone) | `users/{uid}.emergencyContacts` | the person | the person | while the account exists | deletion |
| Payout details (UPI id, holder name) | `users/{uid}.payoutProfile` | the person; staff | the person | while the account exists | deletion |
| Company data (GSTIN, PAN, office city) | `users/{uid}.business`, `.fleet` | the person; staff | the person | while the account exists | deletion |
| Devices (random id, model, last seen) | `users/{uid}/devices`, `device_links` | the person (devices); staff (links) | the app | while the account exists | revoke; deletion |
| Push token | `users/{uid}/devices/*.fcmToken` | the person; server | the app | while the device is active | revoke; deletion |
| Loads (addresses of pickup and drop, goods, weight, price) | `loads` | open loads: every signed-in user (no phone number on them); others: the shipper, the matched driver, staff | the shipper | 8 years (tax and dispute) | personal fields cleared at account deletion |
| Bookings (parties, vehicle number, driver first name, status times) | `bookings` | the two parties, the assigned driver, the transporter, staff | the parties | 8 years | personal fields cleared at deletion |
| Trip codes (pickup and delivery) | `bookings/*/secrets/otp` | the customer only | the customer | with the booking | with the booking; never copied elsewhere |
| Chat messages (text, no numbers) | `bookings/*/messages` | the two parties; staff only through `chat_reviews` after a report | the parties | 8 years with the booking | cleared at deletion |
| In-app call records (who, when, result; no audio, no number) | `calls` | the two parties | the parties | 1 year | TTL policy / admin clean-up |
| Ratings, tips | `ratings`, `tips` | ratings: every signed-in user (profile averages); tips: the two parties | the parties | 8 years | cleared at deletion |
| Money: ledger, payouts, wallet, payment orders | `ledger`, `payouts`, `wallets`, `payment_orders` | the driver; staff (finance) | rules (driver lines) and server | 8 years (tax) | ids only remain after deletion |
| LR (bilty): consignor / consignee names, goods, freight, private parts | `lrs`, `lrs/*/private`, `lr_shares` | issuer and parties; the share link shows a limited snapshot | the issuer | 8 years | share links revoked at deletion |
| Support tickets, SOS, reports | `tickets`, `sos_alerts`, `reports` | the person; staff | the person | 3 years | admin clean-up |
| Audit lines | `audit_events` | staff | the app (own events) and server | 3 years | admin clean-up |
| Risk signals, fraud cases | `risk_signals`, `fraud_cases` | staff | app and staff | 3 years | admin clean-up |
| Share links (trip, LR) | `trip_shares`, `lr_shares` | anyone with the unguessable token (read by id only) | the sharer | 24 h / until revoked | expiry, revoke, deletion |
| Error log lines | `app_errors` | staff | the app, after `Redactor` | 90 days (TTL) | TTL policy |
| Crash reports | Firebase Crashlytics | the owner in the Firebase console | the app, after `Redactor`; no user id | per Crashlytics | per Crashlytics |
| Analytics events | Firebase Analytics | the owner in the Firebase console | the app, only after the person agrees in Settings | per Analytics | consent off stops collection |

## What is never stored
Full Aadhaar number (only the last 4 digits; the rules refuse a longer one), card or bank numbers, passwords, the phone number of the other party (calls and chat are inside the app), audio of calls, photos of the Aadhaar.

## Where personal data must not appear
- Logs, crash reports, analytics: `Redactor` removes phones, e-mails, UPI ids, PAN, GSTIN, vehicle numbers, trip codes, tokens, keys, `Bearer` values and exact positions (`test/redaction_test.dart`, `test/redaction_f5_test.dart`, `test/redactor_part5_test.dart`). A guard test fails if code prints raw text.
- Function logs: a fixed short text and `e.message` only (`functions/test/unit/hardening.test.js`).
- Hosting pages: the trip and LR pages read only the snapshot fields of the share document (route, status, vehicle number, driver first name; no phone, no rate), `no-store`, `noindex` (`test/hosting_headers_test.dart`).

## Account deletion, end to end
1. The person asks (`deletion_requests/{uid}`, one at a time). A person with an open payout, an active trip or a restricted tier goes through support.
2. Staff approve; `deleteAccount` (server, `functions/src/deletion.js`) removes in a fixed order: the user document and everything under it, the sign-in, `users/{uid}/` in Storage, the identity index, referral code, notifications, rate counters, public trust and trip counts, empty-truck posts; it clears name, phone and vehicle number from bookings the other side still needs, and keeps the money records (ids only). Every step can be run again.
3. Tests: `functions/test/emulator/deletion.test.js` (server, emulator) and the app's `AccountDeletionService` tests (export and request); the in-app "Download my data" covers the person's own copy.
4. Until the function is deployed, an admin does step 2 by hand (`docs/KNOWN_RISKS.md` 2).
