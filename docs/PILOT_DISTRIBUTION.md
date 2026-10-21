# Pilot ke 10 + 10 logon ko app kaise dein (Z17)

Teen tareeke. Jo baat is repo se pakka nahi pata use **VERIFY** likha hai: kaam se pehle official page par dekh lein (Google / Firebase ke rules aur free limits badalte rehte hain).

| | A. APK sideload | B. Firebase App Distribution | C. Play internal testing |
|---|---|---|---|
| Free? | Haan, koi service nahi | Free ke roop mein diya jata hai: **VERIFY** (Firebase pricing page) | Play Console developer account ki fees alag hai (**VERIFY** amount), testing ka alag charge nahi: **VERIFY** |
| Kisko | Aap seedha phone mein bhejte ho (WhatsApp/pen drive) | Tester ko e-mail invite | Tester ke Google account ko invite (e-mail list) |
| Update | Har baar naya APK haath se | Naya build upload, tester ko notification | Naya build upload, Play Store se update |
| Risk | "Unknown sources" ki permission; log jhijhakte hain | Tester ko Google account / app lagana | Review/setup ka time; pehle Play Console setup |
| Pilot (10+10) ke liye | Sabse jaldi, par gair-technical driver ko mushkil | Achha beech ka raasta | Sabse saaf, par sabse zyada setup |

## A. APK sideload
1. Release APK banayein (aap khud, docs/ANDROID_RELEASE.md). Universal APK ~114 MB hai (docs/SIZE.md dekhein); `--split-per-abi` se chhota (arm64 ~67 MB, Part 5 ka number).
2. APK ko pen drive / Google Drive link / WhatsApp (file ke roop mein) se phone mein bhejein.
3. Phone par: file kholo > "Install unknown apps" ka prompt aaye to us app (Files / WhatsApp / Chrome) ke liye allow karein > Install.
4. Apni taraf se phone par lagana ho to `.\tool\phone.ps1 install` (docs/PHONE_TOOLS.md).
5. Har naya APK pichle ke upar lagta hai agar **signature wahi** ho (wahi keystore).

## B. Firebase App Distribution
1. Firebase Console > Release & Monitor > App Distribution mein app chalu karein.
2. Release APK ya AAB upload karein (Console se; CLI aap khud chalayein). Testers ke e-mail ek group mein jodein.
3. Tester ko e-mail aata hai; wahan se App Tester app / link se install hota hai. Kya yeh Android par bina Play Store ke chalta hai aur kitne tester free hain: **VERIFY**.

## C. Play internal testing
1. Play Console developer account (fees: **VERIFY**), app banayein, App signing ON (docs/SIGNING.md).
2. Release > Testing > Internal testing: AAB upload (`flutter build appbundle --release`, aap chalayein), tester ke Gmail ki list banayein.
3. Opt-in link tester ko bhejein; Play Store se install. Internal testing mein kitne tester allowed hain aur review chahiye ya nahi: **VERIFY** (Play Console Help). Closed test ki shartein bhi official page se dekhein (docs/OWNER_TODO.md section E).

## Signature badle to
Agar test ke liye debug key se bana APK pehle lagaya tha aur ab release key wala (ya Play se aaya build) lagana hai, to phone `INSTALL_FAILED_UPDATE_INCOMPATIBLE` dega. Pehle purani app **uninstall** karein (login aur local data jata hai) ya `.\tool\phone.ps1 install -ReinstallClean`. Play Store wali app aur sideload wali app ki signature alag hoti hai (Play App Signing), isliye dono ek ke upar nahi lagti.

## Pilot ka order (10 driver + 10 customer)
1. Pehle 2-3 driver aur 2-3 customer ko dein (docs/PHONE_SMOKE_SHEET.md khud pehle chala lein).
2. Invite codes (Admin > Invite codes) se login; docs/OWNER_GUIDE.md ka roz ka checklist.
3. Sab theek ho to baaki 7+7.
