# Play Store checklist

Status key: [x] done in the repo, [ ] needs you (account, keys, decisions).

## App identity
- [x] App label `LoadGo` (AndroidManifest). Package id is still the Flutter default: decide the final id BEFORE the first upload, it cannot change later.
- [ ] App icon and feature graphic (512x512 icon, 1024x500 banner), 2-8 phone screenshots per language you list (plan and caption ideas: docs/PLAY_LISTING.md).
- [x] Short and full description drafts in English, Hindi and Hinglish: docs/PLAY_LISTING.md (owner reviews; a test keeps them within the store limits).
- [ ] Category: Maps & Navigation or Business. Contact e-mail and phone for the listing.

## Signing and build
- [x] Package id in one place and release signing from `android/key.properties`: steps in docs/ANDROID_RELEASE.md. [ ] You create the upload key and `key.properties`, and choose the final package id.
- [ ] `flutter build appbundle --release`; test the release build on a phone (Crashlytics, Remote Config, maintenance screen).
- [ ] Put the SHA-1 / SHA-256 of the signing key in the Firebase Console (needed for Google sign-in and App Check later).
- [ ] Deploy `firestore.rules` and `firestore.indexes.json` (see docs/MANUAL_TODO.md).
- [ ] Demo data removed from the live project (Admin > Demo data shows 0).

## Policy pages (required)
- [x] Privacy policy, terms and account-deletion pages are in `hosting/` (draft wording).
- [ ] `firebase deploy --only hosting` (not done by the run), then paste `https://<site>/privacy` into Play Console > App content > Privacy policy and `https://<site>/delete-account` into the Data deletion question.
- [x] The same links show in the app (Settings > Terms / Privacy, "Public web page"). Change the host with `config/app.policyBaseUrl`.
- [ ] Lawyer review of the three texts; fill in `[add support email and phone]` everywhere.

## Shared load links (App Links)
- [x] The manifest opens `https://loadgo-defc2.web.app/load/{id}` in the app; the web page `hosting/load.html` shows when the app is not installed.
- [ ] For verified links (no chooser dialog): copy `docs/assetlinks.template.json` to `hosting/.well-known/assetlinks.json`, put the FINAL application id and the SHA-256 of the release signing key (Play Console > App signing shows it), then `firebase deploy --only hosting`. Test with `adb shell pm get-app-links <application id>`. Without it the link still works but Android may ask which app to use.
- [ ] If the host changes, change `ShareLinks.host`, `PolicyLinks`, the manifest host and `config/app.policyBaseUrl` together.

## Permissions (declared in the manifest)
| Permission | Why | In-app explanation |
|---|---|---|
| ACCESS_FINE_LOCATION / COARSE | nearest city, nearby loads, trip progress | shown once before the first request |
| POST_NOTIFICATIONS | booking, offer and payment alerts | Settings > Phone alerts, shown once |
| RECORD_AUDIO | speech to text on the mic button, and the in-app voice call | shown once before the first use of each |
| INTERNET | sign-in, data and the in-app call | none (normal permission) |
| MODIFY_AUDIO_SETTINGS | speaker on / off during an in-app call | none (normal permission) |
| ACCESS_NETWORK_STATE | the call checks that the network is there | none (normal permission) |
| CHANGE_NETWORK_STATE | the call (WebRTC) may switch between Wi-Fi and mobile data | none (normal permission) |
No background location, no contacts, no SMS, no storage permission.

## Data safety form (answers)
- Data collected: Personal info (name, phone number, e-mail, address, user ids), Financial info (payment records only, no card data), Location (approximate and precise), Messages (in-app chat and call records: who called whom, when and how it ended), Photos: none yet, Audio: used live for in-app calls and not recorded or stored, App activity and diagnostics (crash logs, performance), Device or other ids (fraud checks).
- Purpose: app functionality, account management, fraud prevention, analytics, communications.
- Shared with third parties: no sale; Google Firebase acts as processor. The other party of a booking sees trip details (name, rating, vehicle number, verified badge). Phone numbers are not shown between customers, drivers and transporters. Call audio goes directly between the two phones (WebRTC; Google's public STUN servers see the network addresses needed to connect).
- Encrypted in transit: yes (HTTPS). Users can request deletion: yes (in app and the web page). Data you collect is optional: location and microphone are optional.
- Government ID: licence number, PAN and last 4 Aadhaar digits are collected from drivers and fleet owners; mark "Personal info / Other" and explain they are format-checked, not verified.

## Data safety additions since the first draft (MASTER-6)
- Invite codes and waitlist: a code you typed, and the route you asked for (from, to) with your user id; used to open the pilot area by area. Deleted with the account.
- Trip survey ("would you use again?") and ratings: tied to the trip, shown to admin as counts.
- Chat strikes and appeals: the cut-out kind of text (phone, UPI, app link) and your appeal text, used to enforce the no-number rule.
- Crash breadcrumbs: the last 25 screen names before a crash, no names, numbers or typed text; error text is cleaned of phone, e-mail, ids and links before it is stored (90-day expiry).
- Trust numbers (on-time, completion, repeat customers) are calculated on the phone from the person's own trips, not stored or shared.
- Saved places: addresses and optional GST invoice details the person types, kept in their own account.
- Still true: no ads, no sale of data, no card data, call audio is not recorded.

## Content rating and target
Content rating notes for the questionnaire (IARC): no violence, no sexual content, no gambling, no drugs, no ads, no purchases in the app, no location sharing with strangers (location goes to the booking party only), users can talk to each other only inside a booking (private chat and call, no public posts); expect "Everyone" or "3+", target audience 18+. Say "yes" to user-to-user communication and "no" to sharing location publicly.
- [ ] Complete the questionnaire (no ads, no user-generated public content, chat only between booking parties). Target audience 18+.
- [ ] Declare "Financial features: none" (no payments are processed).
- [ ] News / government / health declarations: not applicable.

## Before pressing publish
- [ ] Internal test track with 3 testers (one customer, one driver, one fleet owner) following docs/TEST_PLAN.md.
- [ ] Closed testing: Google may require 12 testers for 14 days on new personal developer accounts, check the current rule in Play Console.
- [ ] docs/PAID_UPGRADE_PLAN.md reviewed: what stays "record only" in version 1.
