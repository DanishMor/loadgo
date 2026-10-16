# App Check (G15)

App Check lets Firebase and our functions tell the real Load 20 app from a copy or a script. It matters most for the calls that cost money (payment, maps, SMS, ID checks) and for sign-in SMS pumping (docs/OTP_SECURITY.md, point 5).

## What is built

| Part | Where | Default |
|---|---|---|
| Phone: sends the proof | `lib/core/services/app_check_setup.dart`, started in `main.dart` | **asleep**; starts only for a build made with `--dart-define=APP_CHECK=on` |
| Provider | debug builds: debug provider; release Android: **Play Integrity**; web and other platforms: none | - |
| Server: callable functions | `functions/src/appCheck.js` used by `paymentCreateOrder`, `paymentVerify`, `paymentRefund`, `mapsRoute`, `smsSend`, `kycVerify` | **monitor**: a call without proof is only counted in the logs (`app_check_missing`, function name only) |
| Server: refuse | switch `appCheckEnforce` (Admin > Features) | OFF |
| Firebase products (Firestore, Storage, Auth) | Firebase Console > App Check > Apps > Enforce | OFF (never enforced by the code) |

## Order to turn it on (owner)

1. **Register the app**: Console > App Check > Apps > Android app > **Play Integrity**. Give the SHA-256 of the Play App Signing key (Play Console > App integrity). Link the Google Cloud project in Play Console (App integrity > Play Integrity API).
2. **Debug phones**: build a debug app with `--dart-define=APP_CHECK=on`; the log prints a debug token at the first start. Add it in Console > App Check > Apps > Manage debug tokens. Do not paste it in chat or in the repository.
3. **Build the release** with `--dart-define=APP_CHECK=on` (the same line in the release command in docs/ANDROID_RELEASE.md) and ship it to the testers.
4. **Monitor for a week**: Console > App Check > Metrics for each product shows verified and unverified requests. For our functions search the logs for `app_check_missing`. Old app versions still in use will show as unverified: wait until the share is tiny or force an update (App control screen).
5. **Enforce one product at a time**, least risky first: Cloud Functions callables (switch `appCheckEnforce`), then Storage, then Firestore, then Authentication (phone). After each, test sign-in, a booking, a photo and a payment on a real phone.
6. **Rollback**: switch `appCheckEnforce` off (functions) or "Unenforce" in the Console (the products). It takes effect in minutes.

## Risks

- Enforcing Firestore before nearly all phones send tokens locks those users out. Never enforce on the first day.
- Phones without Google Play services (some custom ROMs) cannot get a Play Integrity token. The pilot should check its phones; the admin web build is not covered (it would need reCAPTCHA Enterprise and a site key).
- Play Integrity has a daily free quota; at pilot size it is far below it. Check the current limit before a large launch.
