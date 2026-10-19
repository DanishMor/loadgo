# Security scorecard (Part 5, H34)

By the areas of OWASP MASVS 2.x. Pass = done and proved by a test in this repo. Partial = done in part or proved only on emulators and fakes. Fail = not done. Everything here was tested on emulators and fakes only; no real phone, no deployed server, no external penetration test (`docs/KNOWN_RISKS.md` 11).

| Area | Verdict | Evidence | What is missing |
|---|---|---|---|
| **STORAGE** (data at rest) | Partial | Backups off (`allowBackup=false`); papers only in private Storage paths; no secret in the repo (`docs/SECRETS_SCAN_PART5.md`); logs and crash reports are cleaned (`Redactor`, 3 test files); the picture cache is capped and cleared at sign-out | A queued trip code sits in plain `SharedPreferences` until sent (KNOWN_RISKS 6); admin CSV goes to the clipboard on purpose (8) |
| **CRYPTO** | Pass | No custom crypto; Firebase Auth/TLS; HMAC-SHA256 webhook check with a constant-time compare; trip codes compared by the rules | none found |
| **AUTH** (authentication) | Partial | Phone OTP by Firebase; delivery/pickup code attempts counted and locked (5, 15 minutes, `otp_attempts` rules); payout step-up and maker-checker (flags); session watcher; optional app lock | App Check not enforced (3); no device binding; OTP rate limit for sign-in is Firebase's own |
| **AUTHZ** (authorization, server side) | Pass on rules, Partial overall | 279 attacks all blocked (`docs/REDTEAM_RESULTS.md`); 65 real app flows allowed (`docs/RULES_CONTRACT.md`); every callable re-reads roles from the database (`docs/FUNCTIONS_SECURITY.md`); staff roles split by collection | Extra fields can be planted on a new load (KNOWN_RISKS 1, S3); functions are not deployed (2) |
| **NETWORK** | Pass | HTTPS only, cleartext off in manifest and `network_security_config.xml`; system CAs only in release (`test/android_release_test.dart`); no pinning by decision (`docs/SECURITY_DECISIONS.md`) | none by decision |
| **PLATFORM** (interaction with the OS) | Pass | One exported activity; no debuggable flag; share-link filter limited to https, our host, `/load/`; link ids validated (`test/untrusted_input_test.dart`); no WebView; `url_launcher` only with fixed schemes; minimum permissions listed and tested | none found |
| **CODE** (quality and build) | Partial | `flutter analyze` 0 issues with stricter lints; model fuzz ratchet; start-up fallback; lifecycle and query-cost guards; pinned CI; R8 minify on | the model fuzz shows 77 of about 95 models throw on wrong-typed fields (lists are protected by `SafeDocs`); whole-app obfuscated release build is checked in H33 notes below; major package updates not done |
| **RESILIENCE** (anti tampering) | Partial by decision | Server rules do not trust the client; root warning only (planned flag); no integrity gate | No root/emulator gate, no obfuscation proof on a device; App Check not on |
| **PRIVACY** | Pass on design, Partial on proof | Data map (`docs/DATA_MAP.md`); consent-gated analytics; no phone numbers between parties; Aadhaar last 4 only; account deletion function with tests; hosting pages show only snapshot fields | Deletion runs by hand until the function is deployed; legal text needs a lawyer (`docs/LEGAL_QUESTIONS.md`) |

## Numbers
- Rules tests: 13 + 167 (matrix) + 65 (contract) + 263 (red team) + 31 (storage red team) + 116 + 114 + 126 + 158.
- Functions: lint clean, unit 43, emulator 167 (includes the hostile-input fuzz).
- Bugs found in Part 5: see `docs/BUG_REPORT.md` (H-1 to H-12 plus the two hunts): 1 x S2, 9 x S3, rest S4; open: H-2 (S3), H-6, H-7 (S4).

## Release build check (H9, H33), 2026-10-19
`flutter build apk --release --obfuscate --split-debug-info=build/symbols` built (universal APK 114.5 MB; the arm64-only build is 66.6 MB; debug symbols for crash decoding are in `build/symbols`, keep them private). Read from the built APK with `aapt dump xmltree`: no `debuggable`, `allowBackup=false`, `usesCleartextTraffic=false`, `networkSecurityConfig` present.

The **merged** manifest (our file plus libraries) exports 8 components, not 1. Our own source manifest exports only `MainActivity` (tested). The other 7 come from libraries and are the normal ones: `FlutterFirebaseMessagingReceiver`, `FirebaseInstanceIdReceiver` (both protected by the Google send permission), `GenericIdpActivity` and `RecaptchaActivity` (Firebase Auth sign-in redirects), `RevocationBoundService` (Google sign-in), `androidx.profileinstaller.ProfileInstallReceiver` (system-only action) and `com.razorpay.DeeplinkActivity` (payment return link). A pentester should look at the Razorpay deep link and the Firebase redirect activities first (`docs/PENTEST_CHECKLIST.md` item 11). The Razorpay link is only used when the payment switch is on.
