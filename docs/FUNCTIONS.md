# Cloud Functions (functions/)

Node 22, region **asia-south1** (Mumbai), written for the Firebase v2 SDK. **Nothing here is deployed by Claude.** The app works without any of it (every server feature has a client fallback and a switch that is OFF).

## Layout

```
functions/
  index.js              the entry: sets the region and exports every function
  src/common.js         region, the list of switches, helpers (flagOn, paise, text, safeId)
  src/*.js              one module per feature (limits, chatScan, credits, trust, jobs, adminActions, deletion, wallet, push, ...)
  test/unit/            tests with no database (node:test)
  test/emulator/        tests against the local Firestore emulator
  test/helpers.js       a Firestore handle on the emulator and a way to empty it
  run-emulator-tests.sh starts the emulator, runs test/emulator, stops it
  eslint.config.js      lint rules
```

Each feature is plain functions that take the Firestore handle (`db`) as an argument, and a thin wrapper in `index.js` that wires it to a trigger. Tests call the plain functions.

## Switches (all default OFF)

Every function first asks `flagOn(db, name)`: it reads `config/features.flags.<name>`, which the owner sets in the app (Admin > Features). Only an explicit `true` turns a feature on. If the document cannot be read, everything stays off.

| Switch | Function(s) | Task |
|---|---|---|
| `serverLimits` | hourly limits for bids, chat, code requests | F16 |
| `serverChatScan` | second scan of chat messages | F17 |
| `serverCredits` | promo, credits and referral settlement | F18 |
| `serverTrust` | trip counts and the public trust summary | F19 |
| `serverJobs` | scheduled jobs (expiry, activation, document suspension) | F20 |
| `serverAdminActions` | admin actions as callable functions | F21 |
| `serverDeletion` | account deletion cascade | F22 |
| `serverWallet` | wallet summary, reconciliation, payout checks | F23 |
| `paymentGateway` | Razorpay order, signature check, webhook, refund, ledger lines (test mode first) | F34, G9 |
| `kycVerify` | ID check answers for the admin (kycVerify) | G13 |
| `smsGateway` | trip SMS fallback and the SOS text (MSG91) | G12 |
| `rateRange` | usual price of a route from finished trips | G20 |
| `payHold` | online payment held until delivery | G21 |
| `maps` | road distance and time (mapsRoute) and the trip map | G10 |
| `pushNotifications` | push on events | F25 |
| `adminBroadcast` | admin announcement push | F27 |
| `photoUploads` | photo upload helpers | F28 to F31 |

## The functions (34)

| Function | Trigger | Switch | What it does |
|---|---|---|---|
| limitLoad, limitOffer, limitBookingMessage, limitLinkMessage, limitGroupMessage, limitCall, limitTicket | a document is created | serverLimits | counts the creator's real documents in the last minute and hour; over the limit the new document is removed and one audit line is written |
| scanBookingMessage, scanLinkMessage, scanGroupMessage | a chat message is created | serverChatScan | the contact filter again, on the server; a hit removes the message and gives a strike (same ladder as the app) |
| creditsBalance | a credit line is written | serverCredits | adds up the lines into credit_balances/{uid}; an overspend marks the load and is audited |
| referralCheck | a referral is created | serverCredits | voids both bonus lines when the referral is not valid (own code, too late, unknown person, more than 20) |
| tripDelivered, ratingAdded | a booking becomes delivered, a rating is created | serverTrust, payHold, rateRange | counts the trip once (trip_counts) and writes public_trust/{uid} with safe fields only (serverTrust); G21 `payHold`: releases an online payment held since before delivery into the driver's ledger (earning, commission), less any refund meanwhile; G20 `rateRange`: adds the final amount to `route_rates/{from}_{to}_{type}` (last 30 amounts, no ids) |
| jobClearLocations | every day 04:30 (India time) | serverJobs | G11: removes the driver position (and its time) from a delivered or cancelled booking a day after the last update |
| jobExpireLoads, jobHoldScheduled, jobSuspendExpiredDocs | every day 03:00, every 15 minutes, every day 03:30 (India time) | serverJobs | closes old open loads; marks the vehicle busy one lead time before a scheduled pickup; holds vehicles and drivers with expired papers (an admin override wins) |
| adminSetRiskTier, adminDecideDriver | callable | serverAdminActions | the admin action done by the server with the staff role checked and the audit line written by the server |
| serverStatus | callable | none (works with every switch off) | any admin asks "is the server there?"; returns the region and which server switches are on, no personal data. Admin > System health > "Check server" |
| deleteApprovedAccount | deletion_requests/{uid} becomes approved | serverDeletion | removes the data, the sign-in and the files; keeps money records; blocks on an open payout |
| walletOnLedger, walletOnPayout, walletReconcile, adminPayoutDecision | ledger or payout written, every day 04:00, callable | serverWallet | recomputes wallets/{uid}, rejects an impossible payout request, writes the daily report, approve / pay / reject / reverse with maker-checker |
| pushOnNotification, pushOnOffer, pushOnOfferSelected, pushOnChat, pushOnSos, pushOnPayout, pushNewLoad, pushWaves, pushDocExpiry | events and schedules | pushNotifications | push messages (see below) |
| paymentCreateOrder, paymentVerify, paymentRefund, paymentWebhook | callable (3), HTTPS POST from Razorpay | paymentGateway | G9. The amount is the booking's own, never from the phone. A good payment (phone verify or signed webhook, whichever comes first, counted once) marks the order and the booking paid and writes the driver's two ledger lines (earning, commission at the config/pricing rate, Pro rate while the plan lasts). A refund (finance or super only, reserved before the call, capped at what was paid) writes one adjustment line. Webhook events are claimed once in `payment_events`. |
| kycVerify | callable | kycVerify | G13. ID check of licence, RC, PAN, GSTIN and the last four Aadhaar digits through a provider (sandbox or none today); result in `kyc_checks/{uid}` for admins; format checked again, daily limits (6 per person, 300 total); the number is not kept. docs/KYC_PARTNER_CHECKLIST.md |
| smsSend, smsOnNotification | callable, a notification is created | smsGateway | G12. MSG91 through the key in the secret MSG91_AUTH_KEY and template ids in `config/sms`. `smsSend` only texts the caller's own emergency contacts; `smsOnNotification` sends one short trip SMS to a person with a phone and no push token. Daily limits per person and in total (`quota_usage`). Setup: docs/SMS_SETUP.md |
| mapsRoute | callable | maps | G10. Road distance and time for two places inside India from Google Routes, cached 30 days per pair (about 1 km grid) in `route_cache`, at most `perUserPerDay` (20) turns per person and `totalPerDay` (2000) for everybody, counted in `maps_usage`; the key is the secret MAPS_SERVER_KEY. Setup: docs/MAPS_SETUP.md |
| adminBroadcast | callable | adminBroadcast | an announcement push to a role or to everyone (super, support, ops) |

### Push messages

* The text is short and fixed, in the person's language (12 languages, `functions/src/pushText.js`). The data holds only the type and ids. **No phone number, no name, no chat text.**
* Switches (users.notificationPrefs) are honoured; safety alerts (accident, breakdown, SOS) cannot be switched off.
* Quiet hours 22:00 to 07:00 India time hold back offers, ratings and reminders. At most 20 ordinary pushes per person per hour.
* New load waves: 3 km at once, 7 km after 3 minutes, 15 km after 6 minutes, only for drivers who agreed to share their place (consents.location), with a position newer than 2 hours, and an account in good standing. Nobody gets the same load twice.
* Dead tokens are removed. The in-app notification list always has everything, so a missing push loses nothing.
* Channels on the phone: bookings, chat, payments, offers, admin (created in MainActivity.kt).

### Indexes the functions need

The new queries need the indexes added to `firestore.indexes.json` (offers, calls, tickets, loads, messages, bookings, users). The owner deploys them with `firebase deploy --only firestore:indexes` (never Claude).

### Two files that must match the app

* `functions/test/fixtures/contact_cases.json`: what the app's contact filter answers for 893 texts; `functions/src/contactFilter.js` must give the same (made by `flutter test tool/make_contact_fixture_test.dart`).
* `functions/test/fixtures/wallet_cases.json`: 400 random books with the boxes the app's WalletBook works out; `functions/src/wallet.js` must give the same (`flutter test tool/make_wallet_fixture_test.dart`).

If the app's code changes, a Dart test fails until the file is made again; then the JavaScript test shows what to change.

## Run the tests (on this laptop, no deploy)

```powershell
cd functions
npm install            # once
npm run lint
npm run test:unit
# Firestore emulator tests need Java: use Android Studio's jbr only for this command
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;C:\Program Files\Git\bin;" + $env:Path
npm run test:emulator
```

`run-emulator-tests.sh` uses `firebase-tools` from `../firestore_rules_test/node_modules`. It starts only the Firestore emulator on the project id `loadgo-functions-test`; it cannot reach a real project.

## Deploy steps (for the OWNER; Claude never runs these)

Only after `docs/BLAZE_GO_LIVE.md` steps 1 to 3 (Blaze plan, budget alert, App Check decision).

1. `cd functions; npm ci; npm test` (lint and unit tests must pass).
2. `npm run test:emulator` (must pass).
3. From the project root, in a PowerShell window where you are logged in as the owner: `firebase deploy --only functions --project <your project id>`.
4. Open the Firebase Console > Functions: every function is listed in `asia-south1`.
5. Switch on ONE switch in Admin > Features. Watch Console > Functions > Logs for one day. Then the next switch.

Rollback: turn the switch OFF (takes effect within 30 seconds). To remove a function: `firebase functions:delete <name> --region asia-south1`.

## Costs

Each switch lists its trigger in `docs/COST_WATCH.md`. A budget alert must exist before any switch is turned on.

## Integration tests through the emulators (F44)

`functions/integration/` runs the functions for real inside the local Auth, Firestore, Functions, Storage and Pub/Sub emulators (`firebase.integration.json`, project id `loadgo-integration`). It proves the wiring that the faster tests cannot: a real trigger fires when a document is written, a callable checks a real sign-in token, account deletion removes a real file and a real sign-in.

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;C:\Program Files\Git\bin;" + $env:Path
cd functions
npm run test:integration
```

- It takes about 2 to 3 minutes (the functions cache the switches for 30 seconds, so the test waits once).
- The first run downloads the Pub/Sub emulator (a Google developer tool) once.
- `integration/run.sh` writes a `.secret.local` with two fake Razorpay values for the emulator only and deletes it at the end. Nothing reaches a real project.
- Covered: switches OFF do nothing; `serverStatus`; limits; chat scan; credits; trust; wallet and the impossible payout; admin risk tier; broadcast guard; payment guards; account deletion with Storage; push triggers with nobody to send to.
- Not covered (no emulator exists): the real FCM send, the Razorpay call, the schedules. Those stay in `docs/KNOWN_ISSUES.md`.

If a run stops with "Port 8087 is not open ... could not start Pub/Sub Emulator", an emulator from an earlier run is still alive: end the leftover `java` process of that emulator (Task Manager) and run again.
