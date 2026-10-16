# Release candidate checklist (F40)

One page to tick before a build goes to testers or to Play. Nothing here is done by Claude on the owner's behalf: signing, upload and deploy are the owner's steps (`docs/PLAY_SUBMISSION_STEPS.md`, `docs/BLAZE_GO_LIVE.md`).

## A. Code is clean (on the laptop)
- [ ] `flutter analyze`: 0 issues.
- [ ] Tests in batches with `--concurrency=1` (never the whole suite at once): all pass. Last full run is written in `docs/PROGRESS.md`.
- [ ] Rules tests (`firestore_rules_test`, `npm test`): pass.
- [ ] Functions: `npm run lint`, `npm run test:unit`, `npm run test:emulator`: pass.
- [ ] `flutter build web --release` (normal) and with `--dart-define=APP_MODE=admin` build without errors (`docs/ADMIN_WEB.md`).
- [ ] Secrets scan clean (`docs/SECRETS_AUDIT.md`): no key, password, keystore or token in the repo.

## B. Version and name
- [ ] `pubspec.yaml` version raised (`+N` for every upload).
- [ ] Display name "Load 20" everywhere users read it; package id decision made (`docs/RENAME.md`, `docs/NAME_CHECKLIST.md`).
- [ ] Final logo in (`docs/LOGO_BRIEF.md`); icon and splash regenerated (`docs/ICON_AND_SPLASH.md`).

## C. Store forms
- [ ] Listing text and screenshots (`docs/PLAY_LISTING.md`), only for features that are ON in this build.
- [ ] Data safety form matches the build (`docs/PLAY_STORE_CHECKLIST.md`, "Data safety additions for Part 2").
- [ ] Privacy policy page deployed with the same text as `docs/PRIVACY_POLICY.md` (photos, push token, earnings records, login safety).
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

## F. Known gaps
- [ ] `docs/KNOWN_ISSUES.md` read; nothing in it is a surprise for the testers.
- [ ] Native reader has returned `docs/TRANSLATION_REVIEW.csv`.
- [ ] Lawyer and CA answers (`docs/WALLET_LEGAL.md`, `docs/LEGAL_QUESTIONS.md`) in hand before real money moves.
