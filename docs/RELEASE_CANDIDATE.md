# Release candidate checklist (F40)

One page to tick before a build goes to testers or to Play. Nothing here is done by Claude on the owner's behalf: signing, upload and deploy are the owner's steps (`docs/PLAY_SUBMISSION_STEPS.md`, `docs/BLAZE_GO_LIVE.md`).

## A. Code is clean (on the laptop)
- [ ] `flutter analyze`: 0 issues.
- [ ] Tests in batches with `--concurrency=1` (never the whole suite at once): all pass. Last full run is written in `docs/PROGRESS.md`.
- [ ] Rules tests (`firestore_rules_test`, `npm test`): pass.
- [ ] Functions: `npm run lint`, `npm run test:unit`, `npm run test:emulator`: pass.
- [ ] `flutter build web --release` (normal) and with `--dart-define=APP_MODE=admin` build without errors (`docs/ADMIN_WEB.md`).
- [ ] Secrets scan clean (`docs/SECRETS_AUDIT.md`): no key, password, keystore or token in the repo.

- [ ] Part 3: `tool/regression_batches.ps1` (all Flutter tests in batches), `functions` unit + emulator + `npm run test:integration`, rules tests, `powershell -File tool\golive_check.ps1` shows nothing marked [todo] that you did not expect. Results of the last run: `docs/PROGRESS.md` (G42).

## B. Version and name
- [ ] `pubspec.yaml` version raised (`+N` for every upload).
- [ ] Display name "Load 20" everywhere users read it; package id decision made (`docs/RENAME.md`, `docs/NAME_CHECKLIST.md`).
- [ ] Final logo in (`docs/LOGO_BRIEF.md`); icon and splash regenerated (`docs/ICON_AND_SPLASH.md`).

## C. Store forms
- [ ] Listing text and screenshots (`docs/PLAY_LISTING.md`), only for features that are ON in this build.
- [ ] Data safety form matches the build (`docs/PLAY_STORE_CHECKLIST.md`, "Data safety additions for Part 2").
- [ ] Privacy policy page deployed with the same text as `docs/PRIVACY_POLICY.md` (photos, push token, earnings records, login safety, and for Part 3: live trip location, maps, text messages, ID checks, analytics consent, app integrity, khata and business card).
- [ ] Data safety form also answers "Data safety additions for Part 3" in `docs/PLAY_STORE_CHECKLIST.md` (precise location, foreground service use, phone numbers of emergency contacts, device or other IDs for App Check).
- [ ] Content rating, target audience 18+, financial features answer matches the `paymentGateway` state.
- [ ] Permissions in the merged manifest equal the table in the checklist (no new one by surprise).

## D. Server
- [ ] Rules, indexes and (if used) functions deployed in the order of `docs/BLAZE_GO_LIVE.md`.
- [ ] Budget alert exists. Admin > System health > Check server answers (if functions are deployed).
- [ ] Every switch you do not want yet is OFF. The pilot list is in `docs/ADDON_PILOT.md`.

## E. Real phone tests (laptop cannot do these)
- [ ] Login code by SMS; wrong code lock; resend wait.
- [ ] Trip code lock after 5 wrong guesses (customer sees the notice).
- [ ] Push arrives with the app closed; tap opens the right screen.
- [ ] Camera photo upload on mobile data; offline queue sends later.
- [ ] Screenshot block on earnings and papers screens.
- [ ] Hindi, Urdu (right to left), largest font size, dark mode, low-end mode: no cut-off text.
- [ ] TalkBack reads buttons and photo cards sensibly.
- [ ] Part 3 on a real phone: `docs/PHONE_TEST_SHEET.md` (every row passes for the switches you turn on; switches you leave OFF need no test).
- [ ] Live location: one real hour of driving with the screen off; the customer's "Last seen" stays fresh; battery drop noted.
- [ ] Razorpay checkout window opens, a test payment verifies; the release build does not lose the plugin class (R8).
- [ ] Fingerprint lock prompt opens, a wrong finger stays locked.
- [ ] Trip map shows with a restricted Android key; blank map means the key or SHA is wrong (`docs/MAPS_SETUP.md`).

## F. Known gaps
- [ ] `docs/KNOWN_ISSUES.md` read; nothing in it is a surprise for the testers.
- [ ] Native reader has returned `docs/TRANSLATION_REVIEW.csv`.
- [ ] Lawyer and CA answers (`docs/WALLET_LEGAL.md`, `docs/LEGAL_QUESTIONS.md`) in hand before real money moves.

## G. Part 4 screens on a real phone (screen by screen)
Switch `uiV2` is ON by default. `dispatchV2` stays OFF until the rules are published (`docs/BLAZE_GO_LIVE.md` order), then turn it ON and repeat rows 6 to 9.
- [ ] 1. Customer home: one big Book action, three modes in one line, recent routes, bottom bar Home / Trips / Help / Profile.
- [ ] 2. Book wizard: five steps, back keeps the answers, kill the app mid-way and the draft comes back, slide to confirm posts the load.
- [ ] 3. Bid Room: bids appear live, sort chips work, accept asks first, counter once.
- [ ] 4. Trip page: OTP cards are big, SOS works, Bilty card shows Full / Driver / Consignee copies.
- [ ] 5. Delivered trip: payment, rating, papers, Book again.
- [ ] 6. Driver home: online switch, Radar line, truck for today.
- [ ] 7. Incoming Load Card: rings with sound and vibration (not in quiet hours), slide to accept, Skip, back counts as Skip, a taken load says so.
- [ ] 8. Bid sheet: percent chips, range, ETA and note chips, change once, withdraw.
- [ ] 9. Loads feed: sort chips, saved route chips, reasons on cards. My bids: four groups.
- [ ] 10. Trip step card: Step n of 6, pickup photo and code, delivery code and confirm, airplane mode keeps the step and sends it later.
- [ ] 11. Earnings: Today, Where your money is. Set-up card: Done / Do this next / Later, rejection reason and send again.
- [ ] 12. Transporter: bid for the company through the sheet; bulk bid. Admin: five groups, role shown, Dispatch monitor.
- [ ] 13. Hindi, Urdu, largest font, dark: no cut-off text on rows 1 to 12.

## H. Part 5 (security and stability): owner steps and phone rows

Server (owner, after Blaze and the keys are ready; nothing was deployed by Claude):
1. Publish `firestore.rules` and `storage.rules` (they changed: load `createdAt` is a server time, the RC image path accepts only the five image types, cheaper load checks for promo and credits).
2. Deploy `firestore.indexes.json` (new index: notifications by user and time).
3. Deploy the functions (admin role fix, explicit timeout and memory). Then open Admin > Features and test the emergency card on a test project first.
4. Restrict the Google API keys (`docs/SECRETS_SCAN_PART5.md`), create the security mailbox and put it in `hosting/.well-known/security.txt` and `docs/VULNERABILITY_DISCLOSURE.md`.
5. Deploy hosting (new `hosting/assets/`, new headers). Check a trip link and an LR link in a browser: the page must still load (the policy now allows only our own script).
6. Set the budget alerts of `docs/ALERT_THRESHOLDS.md`.

Phone rows (add to the phone sheet):
| # | Check | Expected |
|---|---|---|
| H1 | Fresh install with the internet off, open the app | one calm screen with Try again; with the internet on, Try again opens the app |
| H2 | Open a shared load link from WhatsApp | the load opens (or "not available"); a link with odd characters does nothing |
| H3 | Cancel an open load with a price estimate; cancel an accepted trip as the driver | both work |
| H4 | Post a load with a promo code and credits (switches on) | it posts |
| H5 | Driver feed with 200+ loads | scrolls smoothly, no pause when the list updates |
| H6 | Admin > Features: emergency card, switch off "Push messages", confirm, then set it back to On below | saved both times, the app obeys within a minute |
| H7 | Profile / long lists on a 2 GB phone after 20 photos | no crash, memory falls after leaving the screen |
