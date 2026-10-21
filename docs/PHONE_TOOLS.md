# Phone tools (Z10)

`tool/phone.ps1` is for the OWNER's real Android phone. Claude never runs it (adb only lives in this file).

| Kaam | Command |
|---|---|
| Phone dikh raha hai? | `.\tool\phone.ps1 devices` |
| APK lagao | `.\tool\phone.ps1 install` (default `build\app\outputs\flutter-apk\app-release.apk`) ya `-Apk C:\path\app.apk` |
| Signature badli (purani app alag key se thi) | `.\tool\phone.ps1 install -ReinstallClean` (pehle uninstall, phir install; is app ka local data jata hai) |
| App kholo | `.\tool\phone.ps1 run` |
| Log lo (30 second) | `.\tool\phone.ps1 logs -Seconds 30` -> `build\phone_logs.txt` |

## Rules of the tool
- Real phone = koi bhi device jo `emulator-*` na ho. Emulator hamesha ignore hota hai. Do phone ek saath lage hon to ek hata dein.
- Phone `unauthorized` / `offline` / koi nahi: tool Hinglish mein batata hai kya karna hai (USB mode File transfer, USB debugging ON, "Always allow from this computer", Samsung par "Revoke USB debugging authorizations" aur cable dobara lagana).
- Connection beech mein toote to adb 3 baar try hota hai, har baar `adb wait-for-usb-device`.
- `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: tool saaf likhta hai ki signature alag hai; `-ReinstallClean` se hal.
- Package id `android/gradle.properties` (`loadgo.applicationId`) se aata hai; wahan nahi mila to `com.example.transport_app`.
- Logs: sirf `flutter`, `AndroidRuntime`, `FATAL` aur `E/` lines; phone number, email, link, token, key, 6 digit code, vehicle number waghera mask (app ke Redactor jaise). **Bhejne se pehle khud padh lo** (`build\phone_logs.txt` repo mein commit nahi hoti, `build/` git-ignored hai).

## Tests
`flutter test --concurrency=1 test/phone_tool_test.dart` pasted adb output se parsing, advice, install errors, package id aur masking check karta hai (koi phone ya adb nahi chalta).
Helper functions: `tool/phone_lib.ps1`.
