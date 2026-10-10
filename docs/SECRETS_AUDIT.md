# Secrets audit (P7), 2026-10-11

Scope: poori working tree aur poori git history (253 commits, saari branches). Values kahin print ya likhe nahi gaye; neeche sirf file aur line hain.

## Kya dhundha
Google/Firebase API key pattern, private key blocks (`BEGIN ... PRIVATE KEY`), AWS access key, GitHub / Slack / Stripe / Razorpay style tokens, `password`, `secret`, `token`, `api_key`, `storePassword`, `keyPassword` ke saath quoted value, aur filenames: `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.pem`, `*.key`, `key.properties`, service-account files, `.env`, `GoogleService-Info.plist`.

## Nateeja
| Jagah | Mila | Kya karna hai |
|---|---|---|
| Working tree, token / password / private key patterns | **kuch nahi** | - |
| Git history, wahi patterns (kabhi add ya remove hue) | **kuch nahi** | - |
| Keystore, `key.properties`, service account, `.env` kabhi commit hue? | **nahi** (sirf `android/app/google-services.json` ka naam sensitive-list se match hua) | - |
| Firebase API key (public-type) | `android/app/google-services.json` line 18; `lib/firebase_options.dart` lines 44, 54, 62, 71, 80 (web, android, ios, macos, windows). History mein bhi sirf yahi do files. | Rotate karne ki zaroorat nahi; **restrict** karo (`docs/FIREBASE_CONSOLE_CHECKLIST.md` step 4). |
| `android/key.properties`, `*.jks`, `*.keystore` | repo mein nahi, `.gitignore` mein hain, `test/signing_ignore_test.dart` is par pehra deta hai | Keystore repo ke bahar rakho (`docs/SIGNING.md`). |

Is audit ke baad bhi `test/security_doc_test.dart` lib, docs aur android mein secret-jaisi values dhundhta rehta hai (har test run par).

## `google-services.json` mein kya hai, aur wo public-safe kyun hai
Fields: `project_info` (project id, project number, storage bucket), `client_info` (Android app id aur package), `api_key.current_key`, `oauth_client`, `configuration_version`. Isme **koi password, private key ya service-account secret nahi hota**.
* Ye file har APK ke andar hoti hai; koi bhi APK kholkar padh sakta hai. Isliye Firebase isse secret nahi maanta.
* Firebase "API key" sirf project ko pehchanta hai (ye server ki chaabi nahi hai). Asli suraksha Firestore/Storage **rules** aur Auth se aati hai (`firestore.rules`, 449 rules tests).
* Phir bhi key ko **restrict** karo: Google Cloud Console > Credentials mein sirf apna package + SHA (Android), apni domains (web). Isse doosre log aapki key se apne app ke liye quota kharch nahi kar paate (`docs/FIREBASE_CONSOLE_CHECKLIST.md` step 4).
* Is file mein `oauth_client` abhi **khali** hai: matlab Firebase ke Android app mein abhi **SHA-1/SHA-256 nahi jude**. SHA jodne ke baad `google-services.json` dobara download karke yahan badlo (ye commit karna theek hai).

## Jo kabhi repo mein nahi jaana chahiye
Upload keystore aur uske password, `android/key.properties`, Firebase Admin / service-account JSON, Razorpay ya SMS provider ki secret key (paid adapters ke baad: `docs/PAID_ADAPTERS.md`), `.env` files, personal phone numbers ya Aadhaar/PAN ke asli namune (tests mein sirf nakli values).

## Dobara chalane ka tareeka
```powershell
git grep -I -n -E "BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[0-9A-Za-z]{30,}|sk_(live|test)_" 
git log --all --name-only --pretty=format: | Select-String "\.jks|\.keystore|key\.properties|serviceAccount"
flutter test test/security_doc_test.dart test/signing_ignore_test.dart
```
Agar kuch mile: pehle us key ko rotate/revoke karo (Console se), phir history se hatao; sirf file delete karna kaafi nahi.
