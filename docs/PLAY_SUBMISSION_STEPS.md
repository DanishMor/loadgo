# Play Store submission steps (P13, Hinglish)

Is file mein commands **likhi hain, chalayi nahi**. Pehle ye karein: `docs/RENAME.md` (naam aur package id final), `docs/SIGNING.md` (upload keystore), `docs/PLACEHOLDERS.md` (support e-mail/phone bharein, `check_placeholders.ps1` clean), `docs/FIREBASE_CONSOLE_CHECKLIST.md`, `docs/PLAY_STORE_CHECKLIST.md` aur `docs/PLAY_LISTING.md` (listing text).

## 0. VERIFY (naye accounts ki shart)
Official Play Console Help page "Testing requirements for new personal developer accounts" (support.google.com/googleplay/android-developer/answer/14151465), jo **2026-10-11 ko padhi gayi**, ye kehti hai:
* Personal developer account jo **13 November 2023 ke baad** bana ho, use production access ke liye pehle **closed test** chalana hota hai.
* Closed test mein **kam se kam 12 testers opted-in** hone chahiye, aur wo production access ke liye apply karte waqt **pichhle 14 din se lagatar** opted-in rahe hon.
* Page mein organization accounts ke baare mein kuch likha nahi dikha.
**VERIFY:** ye sankhya aur din Google kabhi badal sakta hai. Apply karne se pehle wahi page dobara kholkar padh lein; is file ke number ko aakhri na maanein. (Aapka account personal hai ya organization, aur kab bana, Play Console > Settings se dekhein.)

## 1. Play Console account
1. play.google.com/console par developer account banayein (ek baar ki fees; abhi ka rate Console mein dekhein). Personal ya organization chunna aapke upar hai; organization ke liye kagaz (D-U-N-S jaisi cheezein) Console batayega, **VERIFY** wahin.
2. Identity verification, contact e-mail aur phone dein. Verification mein kuch din lag sakte hain, isliye pehle shuru karein.
3. **Create app**: naam (final), default language, App ya Game = App, Free ya Paid (Free), declarations tick.

## 2. App tayyar karna (release bundle)
Release `.aab` **upload key** se sign hona chahiye (`docs/SIGNING.md`). `android/key.properties` ke bina build debug key se sign hoti hai aur Play use reject karega.
```powershell
flutter build appbundle --release
# output: build\app\outputs\bundle\release\app-release.aab
```
Pehle: `pubspec.yaml` ka `version:` (jaise `1.0.0+1`; har upload par `+N` badhao), `flutter analyze` 0 issues, `flutter test`, `npm test` (rules), aur release APK phone par chala kar dekho (login, call, map link, crash report). Is laptop par pehli release APK bani thi par phone par chali nahi (`docs/BLOCKED.md`).

## 3. Store listing aur policy forms (Console > App content)
* Listing text, icon 512x512, feature graphic 1024x500, screenshots: `docs/PLAY_LISTING.md`, `docs/ICON_AND_SPLASH.md`.
* **Privacy policy URL**: hosted page (`hosting/privacy.html`), deploy owner karega.
* **Data safety**: `docs/PLAY_STORE_CHECKLIST.md` ka table (phone, location, audio call, crash logs, ids...).
* **Content rating**, **target audience** (18+ / adults), **ads** (nahi), **government app** (nahi), **financial features** (abhi paisa app se nahi guzarta; fir bhi sahi jawab dein).
* **Permissions declarations**: location (trip tracking), microphone (call/voice), notifications; Console jo bhi form maange use `docs/ANDROID_RELEASE.md` ke permission table se bharein.
* **App access**: login phone OTP se hai. Reviewer ke liye ek **test phone number + fixed code** dein (Firebase Console > Authentication > Phone numbers for testing, `FIREBASE_CONSOLE_CHECKLIST.md` step 1) aur Console mein instructions likhein. Isko asli users ke liye mat khulwayein.
* **App signing**: "Use Play App Signing" rakhein (`docs/SIGNING.md` section 6).

## 4. Internal testing (sabse pehle, 1 din)
1. Testing > **Internal testing** > Create release > `.aab` upload > release notes > Save > Review > **Start rollout**.
2. Testers list banayein (apni aur team ki Gmail IDs, 100 tak). Opt-in link mile ga; us link se app install karwayein.
3. Check: install, login (test number), ek trip ka flow, call, notification, crash nahi. Play Console > Pre-launch report bhi dekhein.
4. Install hone ke baad Firebase mein **Play App Signing ka SHA** jodein (`docs/SIGNING.md` section 5) warna phone login Play se aayi app par fail ho sakta hai.

## 5. Closed testing (production se pehle)
1. Testing > **Closed testing** > track banayein > testers ki list (Google Group ya e-mail list) > release (wahi ya naya `.aab`) > rollout.
2. Naye personal account ke liye: section 0 ki shart (VERIFY wale number) poori karni hai. Isliye testers pehle se taiyaar rakhein: `docs/PILOT_KIT.md` ke 10-20 log, har ek ne opt-in link se join kiya ho aur **din bhar app rakhi ho**.
3. Tester ke liye message: opt-in link, "app install karke 14 din tak hata mat dena, 2-3 baar kholna".
4. Feedback `docs/PILOT_KIT.md` ke sawaal se lein; crashes Crashlytics mein dekhein; zaroori fix ke baad **naya versionCode** upload karein (opted-in testers ko update milta rahega).
5. Din poore hone par Console > Dashboard mein "Apply for production" dikhega (**VERIFY**: wahan shart dobara dikhengi).

## 6. Production
1. "Apply for production": Console kuch sawaal puchhta hai (app kaise test hui, testers ka feedback, production ke liye taiyari). Sachchai se likhein; `docs/PROGRESS.md` aur pilot numbers kaam aayenge.
2. Google review mein kuch din lag sakte hain. Approve hone par Production > Create release > countries (**India**) > staged rollout (pehle 10-20%) > Start.
3. Rollout ke baad: Crashlytics, Play Console Android vitals, reviews roz dekhein; dikkat par rollout **Halt** karke fix.

## 7. Aksar wali galtiyan
* Debug-signed `.aab` upload (key.properties nahi mila).
* Package id `com.example.*`: Play accept nahi karta (`docs/RENAME.md`).
* Phone login nahi chalta: SHA-1/SHA-256 Firebase mein nahi jude, ya naya `google-services.json` nahi lagaya.
* Privacy policy ka link kaam nahi karta ya "add" wale khali fields baaki.
* Data safety form app ke asli behaviour se mel nahi khata.
* `versionCode` dubara use kiya.
