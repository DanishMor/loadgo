# Manual setup pending

## Google Maps location picker (skipped)
Needs a Google Maps API key (Maps SDK for Android/iOS enabled; billing account required).
Steps when you have the key:
1. Add `google_maps_flutter` to pubspec.yaml.
2. Android: add `<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_KEY"/>` inside `<application>` in AndroidManifest.xml.
3. iOS: `GMSServices.provideAPIKey("YOUR_KEY")` in AppDelegate.
4. Add a map picker for Pickup/Drop in the post-load screen. Live tracking currently shows text coordinates, which the map can replace.

## Live location (Task 2)
Uses `geolocator`; Android/iOS location permissions are already declared. Customer sees coordinates as text; swap for a map once the Maps key exists. Firestore rules for `lastKnownLocation` are in `firestore.rules` and need to be deployed.

## Push notifications / FCM (Task 3)
App side is done: `PushService` saves the FCM token to `users/{uid}.fcmTokens`, Android `POST_NOTIFICATIONS` permission declared.
Sending needs a server: `functions/index.js` (`pushOnNotification`) sends a push for every new `notifications` doc.
Manual steps:
1. Upgrade the Firebase project to the **Blaze** plan (Cloud Functions requirement).
2. `cd functions && npm install`, then `firebase deploy --only functions`.
3. iOS only: upload an APNs auth key in Firebase Console -> Project settings -> Cloud Messaging, and enable Push Notifications + Background Modes (Remote notifications) in Xcode.
Until the function is deployed, notifications stay in-app only.

## Admin panel (Task 4)
`AdminVerificationScreen` (lib/features/admin) is intentionally not linked from the app. Firestore rules let only users with the custom claim `admin: true` read drivers and change `verified`/`verificationStatus`. Grant it with the Admin SDK, e.g. `getAuth().setCustomUserClaims(uid, { admin: true })`. TODO before exposing: gate the screen on that claim and add admin login. Rules need to be deployed.

## List pagination / Firestore indexes (Task 7)
Available Loads, My Loads, Trips and customer Bookings load 20 items at a time ("Load more" for more). Newest-first paging uses composite indexes defined in `firestore.indexes.json`. Deploy them (works on the free plan): `firebase deploy --only firestore:indexes`. Until then the app falls back to an unordered page, so lists still work but may not show the newest items first beyond page 1.
Earnings, the active-trip card and home counts still read all items on purpose (they need totals).
