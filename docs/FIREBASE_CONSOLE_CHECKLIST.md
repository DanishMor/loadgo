# Firebase Console checklist (Hinglish)

Project: `loadgo-defc2` (Firebase Console > project kholo). Har step ke neeche **Kaise verify karein** likha hai. Console ke menu ke naam kabhi-kabhi badalte hain; jahan "VERIFY" likha hai wahan official Firebase / Google Cloud docs se menu aur option ka naam ek baar match kar lo. Is file mein koi key ya password nahi likhna.

## 1. Phone login ke test numbers (development ke liye)
1. Authentication > Sign-in method > **Phone** (enabled rakho) > "Phone numbers for testing" mein 1-2 number aur 6 digit code jodo.
2. Test number sirf aapke team ke liye hai; asli users ke liye asli SMS jata hai.
* **Verify:** app mein wo number daalo; SMS ke bina wahi code se login ho jaye. Authentication > Users mein user dikhe.

## 2. SHA-1 aur SHA-256 jodna (phone login aur Google sign-in ke liye)
1. Project settings (gear) > General > Your apps > **Android app** > "Add fingerprint".
2. Debug SHA-1/SHA-256 jodo (laptop par `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android` se; sirf Console mein paste karo, repo mein nahi).
3. Release/upload key ka SHA bhi jodo (`docs/SIGNING.md`), aur Play App Signing ke baad Play Console > App signing wala Google ka SHA bhi.
4. `google-services.json` dobara download karke `android/app/` mein rakho agar app ya SHA badle.
* **Verify:** Android app ke card mein SHA-1 aur SHA-256 dono dikhen; release APK par phone OTP chale (error `app-not-authorized` ya `invalid-app-credential` na aaye).

## 3. Authorized domains
1. Authentication > Settings > **Authorized domains**.
2. `localhost` (testing) aur aapki hosting domain (`loadgo-defc2.web.app`, `.firebaseapp.com` aur aapka custom domain) rakho. Jo domain use nahi hoti wo hatao.
* **Verify:** web app ko custom domain par kholo aur login karo; `auth/unauthorized-domain` na aaye.

## 4. API key ko Android app tak restrict karna
1. Google Cloud Console (console.cloud.google.com) > wahi project > APIs & Services > **Credentials**.
2. "Android key (auto created by Firebase)" kholo > Application restrictions > **Android apps** > Add: package name (abhi `com.example.transport_app`, final `docs/RENAME.md` ke baad) + SHA-1.
3. API restrictions mein sirf wahi APIs rakho jo app use karti hai (Firebase ke saath aane wali: Identity Toolkit, Firestore, Firebase Installations, Remote Config, FCM Registration, Cloud Storage, Crashlytics, App Check ke liye jo dikhen) — VERIFY: Console mein jo API errors aayen unhe dekh kar badhao, andaza mat lagao.
4. Web, iOS aur Windows ki keys alag hoti hain (`lib/firebase_options.dart`); unhe Android key ke saath mat milao. Web key ko "HTTP referrers" se restrict karo (apni domains).
5. Note: Firebase API key secret nahi hoti (`docs/SECRETS_AUDIT.md`), par restrict karna misuse rokta hai.
* **Verify:** restrict karne ke baad release/debug APK par login aur data load chalna chahiye. Agar `API_KEY_ANDROID_APP_BLOCKED` jaisi error aaye to package ya SHA galat hai.

## 5. SMS region policy (SMS fraud rokne ke liye, sirf India)
1. Authentication > Settings > **SMS region policy** (VERIFY: kabhi "SMS Region Policy" ya Settings ke andar alag tab ke naam se milta hai).
2. **Allow** list choose karo aur sirf **India (IN)** jodo, taaki dusre desh ke numbers par SMS na jaye (SMS pumping / toll fraud se bachne ke liye).
3. Apne team ka koi videshi number ho to wo test number se chalao, region allow mat badhao.
* **Verify:** India number par OTP aaye; kisi non-India number par OTP bhejne par error aaye. Official docs: "Firebase Authentication > SMS region policy" (VERIFY ki steps wahi hain).

## 6. Crashlytics aur Analytics on
1. Project settings > Integrations > **Google Analytics** on rakho (agar nahi to enable karo).
2. Release menu > **Crashlytics** > "Enable". App pehli release ya debug crash ke baad data bhejti hai.
* **Verify:** app chalane ke baad Crashlytics dashboard mein "Waiting for first crash" ya session dikhe; Analytics > DebugView mein events aayen. (App Crashlytics mein personal data nahi bhejti: `docs/PRIVACY_POLICY.md`.)

## 7. Rules publish karna
1. Owner `tool\deploy_rules.ps1 -Account <aapka account> -Project loadgo-defc2` chalaye, **ya** Console > Firestore Database > **Rules** mein `firestore.rules` ka poora text paste karke Publish; Storage > Rules mein `storage.rules`.
2. 409 error aaye to Console wala raasta lo (`docs/FIREBASE_SETUP_2.md`).
* **Verify:** Rules tab mein "Published" ka time abhi ka ho; Rules Playground mein ek unauthenticated read deny ho; `firestore_rules_test` mein `npm test` pass.

## 8. Indexes
1. Firestore Database > **Indexes** > Composite: `firestore.indexes.json` ke saare indexes ka status **Enabled** (Building mein kuch minute lagte hain).
2. App mein koi query "requires an index" error de to error mein diya link kholo, wo index pre-fill kar deta hai; fir `firestore.indexes.json` mein bhi jodo.
* **Verify:** sab indexes Enabled, aur app ke list screens khali error ke bina khulen.

## 9. Admin document banana
1. Pehle us admin ko app mein ek baar phone se login karao (Authentication > Users se uska **UID** copy karo).
2. Firestore Database > Start collection `admins` > Document ID = wo UID. Field: `role` = `super` (ya `support`, `verifier`, `ops`). Koi client ye document nahi likh sakta, isliye sirf Console se.
* **Verify:** us user ke Profile mein Admin entry dikhe; kisi aur user ko na dikhe. (`docs/MANUAL_SETUP.md`)

## 10. Budget alert
1. Google Cloud Console > Billing > **Budgets & alerts** > Create budget (project: loadgo-defc2). Amount choti rakho (jaise 500 rupaye) aur 50 / 90 / 100 percent par e-mail alert.
2. Blaze plan abhi nahi liya hai to bhi budget bana lo; Blaze lene ke baad pehle yahi dobara dekho (`docs/PAID_UPGRADE_PLAN.md`).
* **Verify:** Budgets list mein budget dikhe aur alert e-mail ka recipient aap hon. (Budget alert kharcha rokta nahi, sirf batata hai.)

## 11. App Check (baad ke liye)
Abhi app App Check ke bina chalti hai. Public launch ke baad: Console > App Check > Android ke liye **Play Integrity**, web ke liye reCAPTCHA; pehle "Monitor" mode, fir kuch din baad "Enforce". Enforce karne se pehle purane app versions ko nuksan na ho, isliye monitor ke numbers dekho.
* **Verify (jab lagaoge):** App Check dashboard mein verified requests ka percent 95+ ho tab enforce karo.
