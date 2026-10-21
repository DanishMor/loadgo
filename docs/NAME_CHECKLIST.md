# Naam ke owner-checks aur package id (Load 20)

Ye list **owner ke haath ki** hai: Claude ye online checks nahi karta. Har check ka jawab neeche likhte jaiye (tareekh ke saath). Naam ka code-wala kaam ho chuka (`docs/RENAME.md`, `docs/BRAND.md`).

## 1. Naam check karne ke 4 jagah
| Check | Kahan | Kya dekhna hai | Jawab (tareekh) |
|---|---|---|---|
| Play Store | play.google.com par "Load 20" aur "Load20" search | usi naam ya milte-julte naam ka transport/logistics app | |
| Google search | google.com par "Load 20", "Load 20 truck", "Load 20 app" | pehle se kaun si company ya brand | |
| Trademark (India) | ipindia.gov.in > Trade Marks > Public Search | **Class 39** (transport, freight, goods delivery) aur **Class 42** (software, SaaS, app) mein "Load 20" ya milta-julta (phonetic: "Load Twenty", "Lod 20") | |
| Domain | koi bhi registrar par | load20.in, load20.com, getload20.in jaisi domain; social handles (Instagram, X, YouTube) | |
Ye sirf shuruaati search hai. Asli opinion aur filing ke liye vakeel (`docs/LEGAL_QUESTIONS.md` section E).

## 2. Naam theek na nikle to
`tool\rename_app.ps1 -Name "<naya naam>" -Tagline "<tagline>"` (pehle dry run, phir `-DryRun false`), phir `docs/RENAME.md` ke steps. Dusri lipiyon mein naam aur tagline `lib/core/app_info.dart` mein haath se likhne padte hain.

## 3. Package id badalna (Play Store upload se PEHLE, ek hi baar)
Abhi id `com.example.transport_app` hai. Play Store `com.example.*` accept nahi karta, aur ek baar upload ke baad id **kabhi nahi badalti**. Isliye naam final hote hi id final karein.
1. `tool\rename_app.ps1 -Name "Load 20" -PackageId "in.<aapka>.load20" -DryRun false` (ya `android/gradle.properties` mein `loadgo.applicationId` haath se). Details: **`docs/RENAME.md`**.
2. **Firebase mein NAYA Android app register karein** (Project settings > Your apps > Add app > Android) naye package id ke saath. Purana app alag entry hai.
3. **Naya `google-services.json`** download karke `android/app/` mein rakhein.
4. **Naye SHA-1 aur SHA-256** jodein: debug (laptop ka), release/upload key (`docs/SIGNING.md`), aur Play App Signing ke baad Google ka SHA. Bina SHA ke phone OTP login fail hota hai.
5. API key ko naye package + SHA tak restrict karein (`docs/FIREBASE_CONSOLE_CHECKLIST.md` step 4).
6. `hosting/.well-known/assetlinks.json` mein naya id aur release SHA-256 (`docs/assetlinks.template.json`); hosting deploy owner karega.
7. Kotlin `namespace` (`com.example.transport_app` in `android/app/build.gradle.kts`) sirf code package hai; id badalne se nahi badalta, na badalein.
8. Naya debug/release build bana kar phone par login test karein.

## 4. Naam final hone ke baad
- [ ] `docs/PLAY_LISTING.md`, hosting pages, support e-mail (`docs/PLACEHOLDERS.md`).
- [ ] Domain le li ho to `ShareLinks`, `PolicyLinks`, manifest aur `config/app.policyBaseUrl` mein host badlein (`docs/PAID_UPGRADE_PLAN.md`).
- [ ] Trademark filing ka faisla (vakeel).

## Script se package id badalna (Z16)
`.\tool\change_package_id.ps1 -NewId in.load20.app` pehle DRY RUN deta hai (kya badlega ki list). `-Apply` se likhta hai; `-MoveNamespace` se Kotlin package folder aur namespace bhi. Aakhir mein Firebase ke steps (naya Android app, SHA-1/SHA-256, naya google-services.json, test numbers) aur chetavni (purani app uninstall karni padegi) chhapta hai. `google-services.json` ko script chhoota nahi. Test repo ki copy par chalta hai: `flutter test --concurrency=1 test/change_package_id_test.dart`.
