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
