# LoadGo

Truck and cargo booking app (Flutter + Firebase). Customers post loads; verified drivers accept them, run the trip through its statuses, and both sides rate each other.

## Features

**Everyone**
- Phone (OTP) login with Customer and Driver roles (the role is set once and locked); 12 languages (English, Hindi, Hinglish, Kannada, Tamil, Telugu, Marathi, Gujarati, Bengali, Punjabi, Kashmiri, Urdu), a test checks every key has all 12
- Booking chat with off-platform warning, report and block; support tickets with escalation and a call-support button; in-app notifications and reminders (pickup soon, papers expiring, offers waiting)
- Documents center (invoice with GST, digital LR, proof of delivery with GPS, odometer and receiver signature), cargo document records with history, settings, consent center (location is stored only with consent), My devices (trust, sign out, log out everywhere), delete-account request

- Notification center with categories and switches, dark mode and large-text support, help and FAQ, Terms, Privacy and Refund screens, first-time tour, offline cache with retry, **account deletion** (profile, private data, vehicles and identity entries; Auth user last)
- Claims and disputes with a timeline, ratings both ways with categories, GST invoice PDF with e-way bill fields, transaction history with CSV

**Customer**
- Post loads: goods transport, hourly rental (4/8/12 h) or packers and movers; 0-4 helpers; multi-stop, saved places, fare estimate with breakdown, fragile/high-value flags, payment mode, prohibited-cargo check, repost
- Promo codes, credits and referral code (record only), price offers with one counter, OTP-protected pickup and delivery, tips, ratings
- Analytics, business tools (GSTIN format check, branches, bulk post, route/branch/driver report with CSV, import/export container and seal numbers, two-leg shipments)

- Scheduled bookings, favourite drivers, block list, load templates and "book again", empty-truck board, business team and monthly statements

**Driver**
- Onboarding gate: location consent, then licence, RC, Aadhaar (last 4 digits only) and PAN, then admin approval; duplicate documents are blocked across accounts (`identity_index`)
- Vehicles with profile (size, fuel, body), papers, tyre and service reminders; nearby loads by geohash sorted by distance; planned route; city demand; recommended loads; offers and accept
- Trip: waiting clock, odometer, GPS at pickup/delivery, signature, geofence alerts, SOS, breakdown and accident reports
- Wallet (pending/available/paid-out, payout requests), tips, bonus targets, Free/Pro plan (lower commission), online switch

**Fleet owner**
- Third role: vehicles, invited drivers, assignment, trips on the road, earnings per vehicle

**Admin** (only users with an `admins/<uid>` document; rules enforce it)
- Users and risk tier, driver verification with masked document numbers, vehicles, loads, bookings with manual reassign, tickets, SOS, reports and fraud cases, flagged users with a risk score, risk signals and shared devices, payout requests, promo codes and credits, driver bonuses and plans, audit log, config editors (pricing, vehicle types, support number)

All of the above runs on the free stack: Flutter + Firebase Auth + Firestore. Paid or manual items are listed in `docs/MANUAL_TODO.md`; status per roadmap item is in `docs/ROADMAP_STATUS.md`.

## Setup

Requirements: Flutter SDK (Dart ^3.13), Node 20 + Java (only for the rules tests), a Firebase project.

```bash
flutter pub get
flutter run
```

Firebase config is already in `lib/firebase_options.dart` and `android/app/google-services.json` (project `loadgo-defc2`).

Quality checks:

```bash
flutter analyze        # must report 0 issues
flutter test           # all tests must pass (includes test/e2e_flow_test.dart: customer to driver to payment on fake Firestore + mock Auth)
cd firestore_rules_test && npm install && npm test   # security rules, uses emulators
```

Regenerate icon and splash after changing `assets/branding/*`:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Project layout

- `lib/core` shared: models, services (Firestore access goes through `Backend`, so tests use a fake), l10n, pricing, matching, analytics, enterprise helpers, shared widgets
- `lib/auth`, `lib/customer`, `lib/driver`, `lib/admin` role-specific screens (they never import each other); see `docs/ARCHITECTURE.md`
- `lib/main.dart` app shell and role selection
- `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/` (push sender, needs Blaze)
- `firestore_rules_test/` rules tests against the emulator; CI in `.github/workflows/ci.yml`
- `docs/`: `PROGRESS.md` (task log), `TASK_QUEUE.md`, `NEXT_TASKS.md`, `BLOCKED.md`, `ROADMAP_STATUS.md`, `ARCHITECTURE.md`, `SECURITY_REVIEW.md`, `DATA_RETENTION.md`, `MIGRATIONS.md`, `MANUAL_TODO.md`, `MANUAL_SETUP.md`

## Pending manual tasks

See `docs/MANUAL_TODO.md` for the full list. The short version:

| Task | Why it is manual |
|---|---|
| Deploy Firestore rules: `firebase login`, then `firebase deploy --only firestore:rules` | Needs your Firebase login. Live location and admin rules only work once deployed |
| Deploy Firestore indexes: `firebase deploy --only firestore:indexes` | Needed for newest-first paging (the app falls back until then) |
| Upgrade Firebase to Blaze plan | Required for Firebase Storage (RC photos) and Cloud Functions |
| Deploy storage rules (after Blaze) | `firebase deploy --only storage` |
| Deploy push function: `cd functions && npm install`, `firebase deploy --only functions` (after Blaze) | Sends FCM pushes for new notifications |
| iOS push: upload APNs key in Firebase Console, enable Push + Background Modes in Xcode | Apple developer account needed |
| Google Maps API key, then add `google_maps_flutter` and the map picker/tracking map | Key needs a billing account. See `docs/MANUAL_SETUP.md` |
| Grant admin: in Firebase Console create a document `admins/<your uid>` (any field, e.g. `note: "owner"`) | Then the Admin panel appears in your Profile tab |

## Known limitations

- No real deep links; sharing copies a text summary
- Customer tracking shows coordinates as text, not a map (waiting on the Maps key)
- Distances come from an offline 64-city table, so fares are estimates
- Payments, KYC and GSTIN checks are records and format checks only
- The audit log and fare maths run on the client until Cloud Functions exist (`docs/SECURITY_REVIEW.md`)
