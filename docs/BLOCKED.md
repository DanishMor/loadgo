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
- M6-43: flutter build apk (release or debug) not possible here (no Android SDK); minify rules untested. Owner: build once on a PC with Android Studio and test on a phone.
## Windows laptop (2026-10-10)

| Item | Why blocked | What is needed |
|---|---|---|
| git push | Windows credential is `Safar143`; the repo is `DanishMor/loadgo` (403 Permission denied). | Owner: add `Safar143` as a collaborator with Write, or run `cmdkey /delete:git:https://github.com` and sign in as the repo owner on the next push. |
| Run the app on the emulator | The debug APK builds (216 MB) but `emulator-5554` (Android 16, 2 GB RAM) crashes system_server / package service while installing it (`DeadSystemException`, `Broken pipe`). It is an emulator problem, not an app error. | Owner: cold boot or wipe the AVD and raise its RAM to 4 GB, or connect a real phone with USB debugging. |
