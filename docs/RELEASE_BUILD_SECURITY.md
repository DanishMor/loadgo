# Release build: hiding code and keeping crash reports readable (F5)

Do these when the owner builds the Play Store bundle. **Claude does not run them** (no new builds without the owner).

## 1. Obfuscate the Dart code
Obfuscation makes the app harder to read if someone unpacks the APK. It does not hide secrets (there must be none in the app anyway, see SECRETS_AUDIT.md).

```powershell
flutter build appbundle --release --obfuscate --split-debug-info=build\symbols
```

- `build\symbols` holds the files that turn a scrambled crash trace back into readable names. **Keep that folder for every released version** (zip it with the version number, store it outside git; `build\` is ignored by git).
- Upload the same symbols to Crashlytics so traces are readable there: with the Firebase CLI installed and logged in as the owner, run `firebase crashlytics:symbols:upload --app=<Android app id> build\symbols`. (This uploads symbols only; it is not a deploy.)
- Without the symbols a crash report is unreadable but still safe.

## 2. Shrink the Java/Kotlin side
R8 is on in release (`android/app/proguard-rules.pro`). A release build was tested earlier on this laptop; test again on a real phone before every upload.

## 3. What logs and crash reports may contain
- Never: OTP or trip codes, phone numbers, UPI ids, bank account or IFSC, Aadhaar, PAN, GST, links, tokens, verification ids, coordinates.
- `Redactor.clean` / `Redactor.safe` (lib/core/services/breadcrumbs.dart) remove them. `CrashService.record` sends only a cleaned message (`RedactedError`), `debugPrint` of any value goes through `Redactor.safe`, no user identifier is set in Crashlytics.
- Guards: `test/redaction_test.dart`, `test/redaction_f5_test.dart` (fails if a new `debugPrint` of a value skips the Redactor, if `print()` appears, or if Crashlytics gets a raw error).

## 4. How to check by hand
1. Install the release build on a test phone, trigger a test error with a test number in the text.
2. In the Firebase Console, Crashlytics: the message shows `#` where the number was.
3. In `app_errors` (Admin > Health) the same.
