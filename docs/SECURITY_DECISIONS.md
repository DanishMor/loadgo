# Security decisions (Part 5, H11)

Each decision: what we do, why, and what would change it.

## 1. Certificate pinning: not used
- **Decision:** the app trusts the system certificate authorities only (`network_security_config.xml`); it does not pin a certificate or a public key.
- **Why:** every call goes to Google services (Firebase Auth, Firestore, Storage, Functions, Maps) behind Google-managed certificates that rotate on Google's schedule. A pin that we cannot update without a store release would lock every installed app out when Google rotates (the whole app stops, including the SOS path). Pinning Firebase SDK traffic is also not supported by the SDKs. App Check and the rules are the real server-side gate.
- **Mitigation instead:** HTTPS only (cleartext off in the manifest and the network config), user-installed CAs are trusted in debug builds only, App Check (below).
- **Revisit when:** we call a first-party API on our own domain with our own certificate. Then pin the public key with a backup key and a remote kill switch (flag), never the leaf certificate.

## 2. Root / jailbreak detection: warning only, behind a flag
- **Decision:** if added, it only shows a warning and writes a risk signal. It never blocks sign-in, a trip, an SOS or a payout request.
- **Why:** detection is easy to bypass (Magisk hide), so it cannot be a gate; blocking would lock out real drivers on cheap rooted or custom-ROM phones. Server rules do not trust the client anyway.
- **Flag:** `rootWarning` (default OFF). Nothing ships until a real phone test shows no false positives on common devices (`docs/KNOWN_RISKS.md`).

## 3. App Check (Play Integrity): monitor first
Order (the code already supports it, `functions/src/appCheck.js`, `docs/APP_CHECK.md`):
1. Register the app with Play Integrity in the Firebase console, turn on the debug provider for the emulator only.
2. Ship the build that sends App Check tokens. The functions only count missing tokens (`app_check_missing` log line).
3. Watch the count for one to two weeks. Real users on the new build must show about zero missing tokens.
4. Turn on **enforcement for Cloud Functions callables** (`appCheckEnforce` flag) first: it only affects calls that cost money (SMS, payments, KYC, maps).
5. Only after that, turn on enforcement for Firestore and Storage in the console. Old app versions stop working at that moment, so combine it with a minimum-version notice (`app_control` gate).
6. Rollback: switch the console enforcement off (immediate) and `appCheckEnforce` off.

## 4. Secrets
- No secret in the repo; function secrets come from Secret Manager (`defineSecret`). `google-services.json` and the Firebase web config are public identifiers, not secrets; the API keys in them must be restricted (package + SHA-1 for Android, HTTP referrer for web) in Google Cloud. See `docs/SECRETS_AUDIT.md`.

## 5. Backups
- `allowBackup=false`: nothing from the app goes to Google Drive backups or device-to-device copies.

## 6. Clipboard
- Admin screens copy CSV (payout queue, cohorts) to the clipboard on purpose. This is an accepted admin convenience; on Android 13 and later the system shows a "copied" notice and hides the content from other apps' previews. Listed in `docs/KNOWN_RISKS.md`.
