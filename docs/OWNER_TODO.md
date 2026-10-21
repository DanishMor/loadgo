# OWNER TODO (Z13)

Sirf aapke kaam (jo Claude nahi kar sakta). Upar se neeche order mein. Jo baat is repo se pakka nahi pata use **VERIFY** likha hai: kaam se pehle official page par dekh lein.

## A. Account suraksha (pehle din)
- [ ] GitHub par 2-step verification ON (Settings > Password and authentication). Recovery codes kaagaz par.
- [ ] Google account (jo Firebase / Play Console ke liye hai) par 2-step verification ON.
- [ ] Claude account par 2-step verification ON (jo option available ho; VERIFY kaise).
- [ ] GitHub repo **private** karein (Settings > General > Danger zone > Change visibility). Pehle docs/SECRETS_SCAN_PART5.md padhein.

## B. Firebase tayyari
- [ ] docs/FIREBASE_CONSOLE_CHECKLIST.md poora karein (Auth test numbers +91 9999900001/2/3, code 123456; admin document).
- [ ] `node tool/check_indexes.js` (0 missing), phir indexes publish (docs/RULES_PUBLISH.md section B).
- [ ] Rules publish: pehle purane rules ka text save, phir publish, phir phone par test list (docs/RULES_PUBLISH.md). Rollback ready.
- [ ] Phone par LR register test karein (feedback 1 ka hal): agar ab bhi "taking longer" aaye to Help > Diagnose problem ka report bhejein.
- [ ] Blaze plan aur **budget alert** (docs/BLAZE_GO_LIVE.md, docs/COST_WATCH.md). Blaze free nahi: kharcha pehle samjhein.
- [ ] Secrets (API keys, payment keys, SMS keys) aap khud Console / Secret Manager mein daalein. Kabhi chat, repo ya doc mein na likhein.
- [ ] Functions deploy (docs/BLAZE_GO_LIVE.md): sirf Blaze ke baad, aap khud `firebase deploy` chalayein.
- [ ] Flags **24 ghante ke gap** par ON karein: pehle `uiV2`, 24 ghante dekhein, phir `dispatchV2` (rules publish ho chuke hon). Wallet / server flags sabse baad, ek ek.
- [ ] API keys restrict karein (docs/RELEASE_CANDIDATE.md section H).

## C. Naam, brand, support
- [ ] Naam ka check (docs/NAME_CHECKLIST.md): trademark, Play Store par naam, domain.
- [ ] Support email banayein aur `tool/fill_placeholders.ps1` chalayein (docs/PLACEHOLDERS.md).
- [ ] Logo (docs/LOGO_BRIEF.md), phir docs/ICON_AND_SPLASH.md ke hisaab se icon.
- [ ] Translation review: docs/TRANSLATION_REVIEW.md ki CSV files kisi bhasha jaanne wale se check karwayein.
- [ ] Vakeel ke sawaal: docs/LEGAL_QUESTIONS.md; CA ke sawaal: docs/WALLET_LEGAL.md aur docs/GST_EWAY.md. Policies (TERMS, PRIVACY_POLICY, REFUND_POLICY, DRIVER_AGREEMENT, TRANSPORTER_AGREEMENT) vakeel se review ke bina publish nahi.

## D. Release tayyari
- [ ] Keystore: `tool/make_keystore.ps1` (jab Z15 ki script mil jaye). Password khud chune, kahin na likhe. Keystore repo ke bahar, **backup** do jagah (docs/SIGNING.md).
- [ ] Package id final karein (abhi `com.example.transport_app`, docs/NAME_CHECKLIST.md). Badalna ho to `tool/change_package_id.ps1` (Z16), phir Firebase mein naya Android app, SHA-1/SHA-256, naya google-services.json. Purani app uninstall karni padegi.
- [ ] Release APK/appbundle aap khud banayein (docs/ANDROID_RELEASE.md). Build ke baad `build/symbols` ka **backup** (crash reports padhne ke liye).
- [ ] APK ka size aur KGP warning ka check (Z18 ke baad): build mein "future Flutter versions" wali warning aani band hui ya nahi.
- [ ] Phone par docs/PHONE_SMOKE_SHEET.md poora, phir docs/RELEASE_CANDIDATE.md section G/H tick.

## E. Pilot aur Play Store
- [ ] Pilot: 10 driver + 10 customer (docs/PILOT_KIT.md, docs/OWNER_GUIDE.md). Invite codes se.
- [ ] Logon ko app dene ke tareeke: docs/PILOT_DISTRIBUTION.md (Z17).
- [ ] Play Console: developer account ki fees aur **closed test ki shart** (kitne tester, kitne din) official Google Play Console Help page se VERIFY karein. Is repo mein woh sankhya pakki nahi maani gayi.
- [ ] docs/PLAY_STORE_CHECKLIST.md aur docs/PLAY_SUBMISSION_STEPS.md.
- [ ] Pentest: docs/PENTEST_CHECKLIST.md kisi bahar ke tester ko dein (paid).

## F. Claude kya nahi kar sakta
- `firebase deploy`, Console mein rules / indexes publish, Blaze lena, budget alert.
- Asli phone ya emulator par app chalana, APK / appbundle banana, phone par install (aap `tool/phone.ps1` chalate hain).
- Keystore banana, koi password, key, token, secret dekhna ya rakhna.
- Account banana ya 2-step verification, repo ko private karna, payment, Play Console, vakeel / CA.
- Asli SMS / payment / KYC partner ke saath test (paid hai aur aapke keys chahiye).
- Naam / trademark ka faisla, logo banana, translation ki asli bhasha-jaanch.
- Pentest, aur "kya yeh sach mein sahi hai" ka final faisla: go / no-go aapka.
