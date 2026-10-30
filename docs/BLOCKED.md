# Blocked items

Things the autonomous runs could not finish because they need something outside the free stack or outside the code. Each has what is needed.

| Item | Why blocked | What is needed |
|---|---|---|
| A2 Google sign-in | Needs the app's SHA-1 fingerprint registered in the Firebase Console and a `google-services.json` update; cannot be tested here | Add SHA-1 in Console, enable the Google provider, then add the `google_sign_in` package and link the credential |
| BE5 App Check | Needs Play Integrity set up in the Firebase Console; enforcing it without that would lock every user out | Register the app for App Check (Play Integrity), add `firebase_app_check`, enable enforcement after a monitoring period |
| Real document / KYC verification | Paid provider (Parivahan, NSDL, UIDAI, GST portal) | Provider contract |
| Push notifications | Needs Cloud Functions (Blaze) to send | Blaze plan |
| Maps, live map, road ETA | Needs a Maps API key and billing | Maps account |
| Payments, payouts, refunds | Needs a payment gateway | Gateway account |

## Re-checked 2026-10-06 (Task 40)

Nothing moved into the free stack: every item above still needs a paid service, a provider contract or a manual Console step. A2 and BE5 are manual (`docs/MANUAL_SETUP.md`); all other rows are listed with their cost reason in `docs/NEXT_TASKS.md`. Rules and indexes changed since the last deploy (Tasks 15-39) are **not deployed**.

## MASTER-3 (2026-10-08)

| Item | Why blocked | What is needed |
|---|---|---|
| A real two-phone voice call test | WebRTC cannot be exercised in unit tests or here; the tests use a fake `CallProvider`. | Two devices on different networks; if the call does not connect behind strict networks a TURN server is needed (`// LATER(paid)`). |
| Push to ring a closed app, missed-call push | Needs a sender (FCM + Cloud Functions, Blaze) | Blaze plan |
| Masked-number calling | Paid telephony provider | Provider contract; plug into the `CallProvider` interface |
| GST / PAN check of a transporter | Paid KYC API | Provider contract (the badge is an admin decision today) |
## Windows laptop (2026-10-10)

| Item | Why blocked | What is needed |
|---|---|---|
| Run the app on the emulator | The debug APK builds (216 MB) but `emulator-5554` (Android 16, 2 GB RAM) crashes system_server / package service while installing it (`DeadSystemException`, `Broken pipe`). It is an emulator problem, not an app error. | Owner: cold boot or wipe the AVD and raise its RAM to 4 GB, or connect a real phone with USB debugging. |

## Part 2 (2026-10-15)

| Item | Why blocked | What is needed |
|---|---|---|
| Fingerprint / screen lock on the earnings screens (F11 `appLock`) | The lock logic, the Settings switch and the gate are built and tested with a fake. The real prompt needs the `local_auth` plugin, the `USE_BIOMETRIC` permission and `MainActivity` as a `FlutterFragmentActivity`, and a test on a real phone (no emulator or phone run is allowed here). | Owner: on a real phone add `local_auth`, switch `MainActivity`, plug an adapter into `AppLock.authenticator`, then try. Until then the Settings switch says the phone has no lock and stays off; the flag is OFF anyway. |
| Real fresh-code check (F11 `walletStepUp`) | The code path (SMS to the signed-in number, re-authentication, token refresh, rules check of `auth_time`) is tested with fakes and the rules emulator. A real SMS needs the Firebase project and a phone. | Owner: turn the flag on in a test project with a test number, then a real phone. |
| Screenshot block (F4 `secureScreens`) | `FLAG_SECURE` is a window flag set from `MainActivity`; only a real phone shows that it works. | Owner: release build on a phone, open the login code screen, try a screenshot. |

## Part 4 (2026-10-19)

| Item | Why blocked | What is needed |
|---|---|---|
| Push that rings a closed app (Incoming Load Card) | Needs the Cloud Functions sender (Blaze) | Deploy functions, turn `dispatchV2` ON after the rules are published |
| Server wave and server auto-accept | Functions are written and tested on the emulator but not deployed | Same deploy |
| Skip reason storage | A new field needs a rules and functions change that only the owner publishes | Owner decision |
| Real phone run of rows 1 to 13 in docs/RELEASE_CANDIDATE.md section G | No phone run is allowed here | Owner |

## Load 20 FINAL2 (2026-10-21)

| Item | Why blocked | What is needed |
|---|---|---|
| Z9 Admin "Test lab" (fake drivers bid, fake driver accepts, one-tap driver approval) | The rules only let a driver create their own bid (`offers` create needs `validOfferCreate`, which ties `driverId` to `request.auth.uid`) and only the real driver accept an instant load. Letting an admin write bids or bookings for another user id would open a path to fake bids, fake bookings and fake money lines on a real project, which weakens the rules. The plan says to skip in that case. | Owner decision. Safer options that need no rule change: test with the three test numbers (+91 9999900001/2/3) on two phones, or run the Bid Room through the emulator tests that already exist (`test/` and `firestore_rules_test`). A server-side Test lab (a Cloud Function that writes demo documents with the admin SDK, flag OFF) is possible after Blaze; it is a paid-plan item (see docs/NOT_FREE.md). |
| Z1 server time difference | No free read returns the server clock without a write, and the Diagnose screen never writes. | None; the report says "not measured". |

## Elite plan (2026-10-30)

| Item | Why blocked | What is needed |
|---|---|---|
| E20 turntable view of the vehicle painter (optional) | Skipped as the plan allows. The E16 painter draws one fixed 3/4-side view, so a real turntable would need a second drawing per vehicle body for every angle (or a 3D model plus a renderer package, against rule 7). A fake one (skewing the flat drawing) would look wrong and teach nothing about the size. The plan ships it only if it meets the animation budget on LowEndMode, and that can only be measured on a real low-end phone, which no run here may use. | Owner decision. If wanted later: draw front and rear views in the painter (procedural, no images), cross-fade four views on a swipe (no timer, nothing animates in LowEndMode or with reduce-motion), and measure on a low-end phone before turning it on. |
