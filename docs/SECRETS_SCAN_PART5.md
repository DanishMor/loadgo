# Secret scan of the whole git history (Part 5, H13)

Method: every added line of every commit on every branch (`git log --all -p`) was checked against patterns for Google API keys, private-key blocks, Razorpay keys, GitHub / Slack / AWS tokens, service-account files, signing passwords, and "name = long quoted string" assignments. Only the file and the first commit are listed here, never a value. Script: kept out of the repo (it prints no values by design).

Result: **14 file/pattern pairs, 0 real secrets.**

| Pattern | File | Verdict |
|---|---|---|
| Google API key | `android/app/google-services.json`, `lib/firebase_options.dart` | Public identifiers of the Firebase project, shipped in every app. Not secret, but must be **restricted** in Google Cloud (below). |
| Signing password | `android/app/build.gradle.kts` | Reads `keystoreProps.getProperty(...)` from the git-ignored `key.properties`. No literal. |
| Signing password | `docs/ANDROID_RELEASE.md`, `docs/SIGNING.md`, `test/android_release_test.dart` | Names of the properties in the instructions, no values. |
| Long quoted "secret/password/token" assignments | `functions/test/emulator/razorpay*.test.js`, `functions/test/unit/razorpay.test.js`, `functions/integration/helpers.js`, `functions/integration/part3.test.js`, `firestore_rules_test/rules.test.mjs` (lines 4971, 5277) | Constants used in emulator tests (signing a fake webhook, a fake sign-in). The lines say test / fake. Not usable against any real service. |
| Private key block, service account JSON, Razorpay key, GitHub / Slack / AWS tokens, keystore files | none found | |

## What is public-safe and what to restrict
- `google-services.json` and `firebase_options.dart` hold the Firebase web/Android API key and app ids. They identify the project; security comes from the rules, Auth and App Check, not from hiding them. **Restrict the keys** in Google Cloud > APIs & Services > Credentials:
  - Android key: restrict to the Android app (package name + the SHA-1 of the release and Play signing keys) and to the APIs the app uses (Identity Toolkit, Firestore, Storage, FCM registrations, Firebase Installations, Remote Config, Maps SDK for Android if the Maps key is the same).
  - Web key: restrict by HTTP referrer to the hosting domain, and the same API list.
  - The Maps key (`MAPS_API_KEY`) comes from build properties; restrict it to the Android app and to Maps SDK for Android only. A server Maps key (`MAPS_SERVER_KEY`) is a Functions secret, restricted by API (Directions, Distance Matrix, Geocoding), never in the app.
- Secrets (Razorpay key id / secret / webhook secret, MSG91 auth key, Maps server key) live only in Secret Manager (`defineSecret`). Nothing of them is in the repo or in the history.
- The release keystore and `key.properties` are git-ignored (checked by `test/android_release_test.dart`).

## Owner steps
1. Restrict the three keys as above. 2. Keep `key.properties` and the keystore out of the repo and back them up offline. 3. If any key was ever pasted into a chat or an issue, rotate it.
