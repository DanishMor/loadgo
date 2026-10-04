# Splitting into a Customer app and a Driver app (notes only)

Nothing here is done yet. The code was arranged in Task 17 so that the split is mostly moving folders, not rewriting. `test/structure_test.dart` keeps it that way: `customer/` and `driver/` never import each other, and `core/` imports neither.

## Target layout

```
packages/
  loadgo_core/        <- today's lib/core        (Dart package, no screens that belong to one role)
  loadgo_customer/    <- lib/auth (customer part) + lib/customer + main_customer.dart
  loadgo_driver/      <- lib/auth (driver part)   + lib/driver   + main_driver.dart
  loadgo_admin/       <- lib/admin (optional: keep inside one of the apps, or a small web app)
```

Both apps use the same Firebase project (`loadgo-defc2`), the same Firestore rules and the same `users/{uid}` documents, so one phone number can be both a customer and a driver, as today.

## Steps

1. **Make core a package.** Move `lib/core` to `packages/loadgo_core/lib`, add its own `pubspec.yaml` (firebase_core, cloud_firestore, firebase_auth, shared_preferences, url_launcher, geolocator, connectivity_plus). Replace `package:transport_app/core/...` and relative `../core/...` imports with `package:loadgo_core/...`. A search-and-replace plus `dart fix` does it; the structure test already guarantees core has no upward imports.
2. **Split `lib/auth`.** Today it holds both roles' flows. Keep `splash_screen`, `otp_verification_screen`, `start_resolvers` generic, then create `customer_login_screen` + `customer_profile_setup_screen` in the customer app and `driver_login_screen`, `driver_profile_setup_screen`, `driver_pending_screen` in the driver app. `role_selection_screen` disappears from both apps (the app itself is the role).
3. **Two entry points.** `main_customer.dart` and `main_driver.dart` copy today's `main.dart`, register `AppRoutes.roleSelection` (point it at that app's login screen) and start at the right resolver. Give each app its own application id (`com.loadgo.customer`, `com.loadgo.driver`), icon and splash (`flutter_launcher_icons` / `flutter_native_splash` per app).
4. **Re-point shared hooks.** `AppRoutes.logout` already goes through a registered builder, and `ProfileView` takes `extraTiles`, so the home screens do not change. Each app registers its own `AppRoutes.adminEntry` or leaves it null (admin stays in one app only).
5. **Firebase per app.** Register a second Android/iOS app in the same Firebase project, download its `google-services.json` / `GoogleService-Info.plist`, regenerate `firebase_options.dart` with FlutterFire. Phone Auth needs the SHA-1/SHA-256 of each app.
6. **Translations.** `core/l10n` tables are shared. Optionally split the key lists by role so each app ships only its own strings (a size win, not a requirement).
7. **Tests.** Move `test/` files next to the code they cover. Tests that use both roles in one flow (accept a load, advance a trip, offers) stay in core as service tests: they use `Backend.useFakes`, not screens.
8. **CI.** Run `flutter analyze` and `flutter test` per package (melos or a matrix job). The rules tests stay in `firestore_rules_test/` and run once.
9. **Releases.** Separate store listings, privacy labels, and versioning. Keep `core` on a shared version so rules and data shapes stay compatible; deploy `firestore.rules` before releasing an app that needs a new field.

## Things to decide before splitting

- Where the admin panel lives (inside the driver app is awkward; a Flutter web build of `lib/admin` is a good fit).
- Whether a user can switch roles. Today one account can be both; with two apps this just means installing both.
- Deep links: customers share a load or booking, drivers open it. Needs Firebase Dynamic Links alternatives (App Links / Universal Links) per app.
- Push: topic or token per app. `users/{uid}.fcmTokens` is already a map of tokens, so both apps can register.
