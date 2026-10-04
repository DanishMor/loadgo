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
