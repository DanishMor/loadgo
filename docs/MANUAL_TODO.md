# Your manual and paid work

Everything the app could do on the free stack (Flutter + Firebase Auth + Firestore) is built. The items below need your login, a billing account, a paid service, or a business decision. In code they are marked `// LATER(paid)` or `// TODO(functions)`.

## Do first (free, 10 minutes)
- [ ] `firebase login`, then `firebase deploy --only firestore:rules,firestore:indexes` (project `loadgo-defc2`). Nothing from Tasks 3 to 16 works against the live database until the rules are deployed.
- [ ] Make yourself admin: Firebase Console > Firestore > start collection `admins`, document id = your Auth uid (any field, e.g. `note: "owner"`). The "Admin panel" row then appears in your Profile tab.
- [ ] Open the Admin panel > Pricing and Vehicle types once and press Save, so the live `config/*` documents exist (the app uses built-in defaults until then).
- [ ] Replace the placeholder Terms of service and Privacy policy text (Settings screens show "placeholder").

## Needs Blaze (billing account)
- [ ] Upgrade the project to Blaze.
- [ ] Firebase Storage: deploy `storage.rules`, then add photo upload for RC, vehicle papers, pickup/delivery proof (POD screen has the placeholder).
- [ ] Cloud Functions (`functions/` already holds the push sender). Write and deploy functions for:
  - FCM push for new `notifications` (exists, needs deploy)
  - audit events from triggers instead of the client
  - authoritative fare, platform fee, commission and payout
  - OTP attempt rate limit
  - account deletion for `deletion_requests`
  - scheduled reminders (expiring vehicle papers, unpaid trips)
- [ ] iOS push: APNs key in Firebase Console, Push + Background Modes in Xcode.

## Needs a paid service or partner
- [ ] Google Maps / Places / Directions / Distance Matrix key: map picker, live tracking map, real road distance (currently an offline 64-city table x 1.25).
- [ ] Payment gateway (UPI/cards/escrow) and payouts. Today payments are records only.
- [ ] KYC: Aadhaar/PAN/DigiLocker, GST portal (GSTIN verify), RC/insurance/PUC/permit verification. Today all are text and labelled "Unverified" / "Not verified".
- [ ] SMS provider (emergency contacts, OTP fallback) and masked calling.
- [ ] Insurance partner for cargo cover.
- [ ] AI features (smart pricing, document OCR).

## Business and store work
- [ ] Support phone/email shown in Help & support; SOS currently calls 112.
- [ ] Review DPDP Act / privacy obligations with a lawyer (consent center and deletion request exist, retention policy does not).
- [ ] Play Store / App Store listing, signing keys, privacy labels.
- [ ] Decide when to split the app into Customer and Driver apps: see `docs/SPLIT_PLAN.md`.
- [ ] Commission % and cancellation charges are config values; set the real numbers in Admin > Pricing.

## Pilot add-on
- [ ] `firebase deploy --only firestore:rules` once more for the `trip_shares` rules, and `--only hosting` for `/trip/**` and `/load/**` (the earlier rules and indexes are already live).
- [ ] Read docs/ADDON_PILOT.md, docs/LAUNCH_RISKS.md and docs/COST_WATCH.md; set a billing budget alert; check the current Firebase Auth SMS quota.
- [ ] Admin > Features: confirm pilot mode is what you want; Admin > Unit economics: type your real fixed and per-trip costs.
