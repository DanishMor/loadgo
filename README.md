# LoadGo

Truck and cargo booking app (Flutter + Firebase). Customers post loads; verified drivers accept them, run the trip through its statuses, and both sides rate each other.

## Features

- Phone (OTP) login with Customer and Driver roles, profile setup and editing
- 12 app languages (English, Hindi, Hinglish, Kannada, Tamil, Telugu, Marathi, Gujarati, Bengali, Punjabi, Kashmiri, Urdu); a test checks every key has all 12
- Customer: post loads, My Loads (cancel while open), bookings with live tracking, invoice/summary, rate driver
- Driver: vehicles (RC photo), available loads with search and filters, accept load (atomic), trip flow accepted -> picked up -> in transit -> delivered, cancel before pickup, earnings summary, rate customer
- Live driver location while in transit (text coordinates for the customer)
- In-app notifications and FCM push registration
- Pagination (20 per page + "Load more"), loading/empty/error/offline states
- Share/copy summary of a load or booking
- Admin driver-verification screen (code only, not linked in the UI)

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
flutter test           # all tests must pass
cd firestore_rules_test && npm install && npm test   # security rules, uses emulators
```

Regenerate icon and splash after changing `assets/branding/*`:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Project layout

- `lib/core` models, services (Firestore access goes through `Backend`, so tests use a fake), shared widgets
- `lib/features` screens grouped by area (loads, bookings, vehicle, profile, admin, ...)
- `lib/main.dart` app shell, role selection, and the translation table `T`
- `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/` (push sender)
- `docs/MANUAL_SETUP.md` details for every pending manual step

## Pending manual tasks

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
- Earnings are based on load budgets of delivered trips, and the invoice is a trip summary, not a tax invoice
