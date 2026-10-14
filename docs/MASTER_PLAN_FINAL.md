LOAD 20 MASTER (single prompt). Sabse pehle ise bina badle docs/MASTER_PLAN_FINAL.md mein save karke commit karo. Windows laptop (PowerShell), project C:\projects\loadgo, sirf is folder mein kaam karo. Permission mat maango, sawaal mat poochho: doubt ho to sensible assumption lo aur docs/DECISIONS.md mein ek line likho. Pehle docs/PROGRESS.md, PAID_UPGRADE_PLAN.md, PAID_ADAPTERS.md, WHERE_IS_WHAT.md dekho. Jo pehle se bana hai (theme, core/widgets, tool/rename_app.ps1, LowEndMode, Redactor, adapters, functions/ folder, FCM token code) use reuse ya poora karo, duplicate mat banao. App ka naam ab "Load 20" hai (purana rule "LoadGo mat badlo" hata diya).

GLOBAL RULES:
1. Koi purana feature, feature flag, rules test ya security limit kamzor ya delete mat karo. Design se sirf dikhna badle, behaviour nahi.
2. firebase deploy KABHI mat chalao. Android emulator, phone par flutter run ya naya apk build mat karo (jo tab pehle se chal raha ho use mat chhedo). flutter build web --release allowed. Sab server kaam local emulator aur fakes par test ho.
3. Koi asli key, password, keystore, token ya secret code, docs ya terminal output mein mat likho (config env se, steps docs mein).
4. Package id com.example.transport_app abhi mat badlo, sirf display name badlo.
5. Har naya server feature config/features mein flag ke peeche, default OFF. Function deploy na ho to app current client behaviour par bina toote chale (fallback).
6. Har task chhota (15 minute): flutter analyze 0 issues, related tests, commit "L<n>: ...", har 3 task par git push (DanishMor ka local git config laga hai; 403 aaye to sirf batao, credentials mat badlo). PROGRESS.md har task ke baad. Block ho to docs/BLOCKED.md mein likho aur aage badho.
7. Naya user text 12 languages mein. Paisa integer paise. customer/, driver/, fleet/, admin/ ek dusre ko import na karein.
8. Har screen 360x640, 2.0x text, light aur dark, LowEndMode, RTL (Urdu, Kashmiri) aur Hindi mein theek dikhe.
9. Poora flutter test, firestore_rules_test npm test aur functions tests har phase ke end mein, baaki task mein sirf related tests.
10. Restart ke baad docs/MASTER_PLAN_FINAL.md aur PROGRESS.md padh kar wahin se resume. Context bhar jaye to PROGRESS.md update karke /compact.

PHASE 1 - BRAND:
L1 tool/rename_app.ps1 -Name "Load 20" -Tagline "Maal bhejo, bharosa ke saath": pehle DryRun, phir asli, sirf display name (core/app_info.dart, 12-language strings, splash, Terms/Privacy/hosting pages, Android label, web title aur manifest, README, Play listing drafts). User ko dikhne wala purana naam nahi bachna chahiye (test se check).
L2 docs/BRAND.md: naam, tagline, tone of voice (Hindi, Hinglish, English: seedha, bharosemand, chhote vaakya), logo, colour aur font rules, do aur dont.
L3 docs/NAME_CHECKLIST.md: owner ke checks (Play Store, Google, ipindia.gov.in class 39 aur 42, domain) aur package id badalne ke steps (docs/RENAME.md ka link, naya Firebase Android app aur naye SHA ka note).

PHASE 2 - DESIGN SYSTEM:
L4 lib/core/theme mein design tokens ek jagah: colour, type scale, spacing 4/8 grid, radius, elevation, motion. Direction: gehra navy (bharosa) + saffron/amber accent (action) + success, warning, error + neutral slate. Exact hex tum chuno, par test prove kare: text 4.5:1 se upar, UI components 3:1 se upar, light aur dark dono mein.
L5 Material 3 ThemeData light aur dark (dark mode kala-neela, pure black nahi), roles (customer, driver, transporter) ke liye halka accent, admin ka alag "Admin mode" banner waisa hi.
L6 Typography: ek brand font (OFL license, assets mein bundle, license file ke saath) + Devanagari, baaki scripts ke liye system fallback, 12 languages ka rendering test.
L7 Guard test: theme ke bahar hard-coded Color(0x...) ya TextStyle nahi (purane exceptions ki list docs mein).

PHASE 3 - COMPONENTS AUR SCREENS:
L8-L12 core/widgets mein shared components: buttons (primary, secondary, danger, Driver Simple Mode ke bade), cards, status badges (sab statuses ke ek jaise rang), inputs aur OTP field (6 box, auto-advance, countdown), app bar, bottom nav, dialogs aur sheets, snackbars, skeleton loading, empty aur error states ke vector illustrations (CustomPainter, offline), fare aur paise display, verified aur trust badges. Phir purani screens inpe move karo area-wise: auth, customer home, post load, tracking, driver home, loads, trips, wallet, chat, LR/bilty, transporter, admin (admin saada par consistent).

PHASE 4 - LOGO, ICON, POLISH:
L13 vector logo mark + wordmark (CustomPainter ya SVG, kisi aur brand jaisa ya copyrighted nahi). L14 app icon, adaptive icon, splash, flutter_launcher_icons aur flutter_native_splash config, docs mein likho ki final logo designer se approve karwana hai.
L15-L18 splash, role select, login/OTP aur pehle-baar tutorial ko premium feel; micro-animations (disableAnimations aur LowEndMode ka dhyan), key actions par haptics,
