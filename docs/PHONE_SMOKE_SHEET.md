# Phone smoke sheet (Z12)

Do phone chahiye: **Phone C** = customer, **Phone D** = driver (ya ek phone aur ek emulator-free dusra phone). Test numbers: customer `+91 9999900001`, driver `+91 9999900002`, teesra (fleet / transporter) `+91 9999900003`. OTP code hamesha `123456` (Firebase Console > Authentication mein test numbers pehle se jode hon).

**Shuru karne se pehle (ek baar):**
1. Admin ka document banao: Console > Firestore > `admins/<apna uid>` mein `role: "super"` (docs/MANUAL_SETUP.md). Admin web ya admin phone se login.
2. Flags ka order: pehle `uiV2` ON, test karo; phir 24 ghante baad `dispatchV2` ON (Admin > Features). Dono ke beech ek din ka gap rakho. Wallet wale rows tabhi jab `walletHub` ON ho.
3. Rules aur indexes publish ho chuke hon (docs/RULES_PUBLISH.md).
4. APK install: `.\tool\phone.ps1 install` (docs/PHONE_TOOLS.md).

**Har row mein:** Expected padho, kaam karo, `Pass` ya `Fail` mein X lagao. **Fail par bhejo:** screen ka screenshot, Help > Diagnose problem ka "Copy report" (padh kar), aur `.\tool\phone.ps1 logs` ki file (padh kar). Neeche "Bhejo" column mein extra cheez likhi hai.

| # | Phone | Step | Expected | Pass | Fail | Fail par bhejo |
|---|---|---|---|---|---|---|
| 1 | C | App kholo (pehli baar) | Tour (intro) dikhe, skip ho sake | [ ] | [ ] | screenshot |
| 2 | C | Login: +91 9999900001, code 123456 | Role chunne ki screen, phir customer home | [ ] | [ ] | Diagnose report |
| 3 | C | Profile bharo (naam, kaam) | Save ho, home par naam dikhe | [ ] | [ ] | screenshot |
| 4 | D | Login: +91 9999900002, code 123456, driver chuno | Profile -> documents ki screen | [ ] | [ ] | screenshot |
| 5 | D | Driver documents bharo (DL, RC, Aadhaar last 4, PAN) | "Waiting for our team" chip, "Do this next" nahi; Refresh dabane par "Coming Soon" nahi, saaf message | [ ] | [ ] | screenshot |
| 6 | Admin | Driver ko approve karo (Admin > Drivers) | Phone D par Refresh se driver home khule | [ ] | [ ] | admin screenshot + Phone D Diagnose |
| 7 | C | Booking wizard: Instant mode se load post | Load ban jaye, "searching" status | [ ] | [ ] | Diagnose report |
| 8 | C | Booking wizard: Bid mode se load post | Bid Room khule | [ ] | [ ] | wahi |
| 9 | C | Booking wizard: Scheduled / rental / movers (teeno mode) | Har mode mein load post ho | [ ] | [ ] | wahi |
| 10 | D | Load dikhe; Incoming Load Card (dispatchV2 ON hone par) | Card aaye, accept / skip chale | [ ] | [ ] | screenshot |
| 11 | D | Bid Room mein bid bhejo | Phone C par bid dikhe | [ ] | [ ] | Diagnose |
| 12 | C | Counter bhejo; D counter accept kare | Counter dono taraf dikhe | [ ] | [ ] | Diagnose |
| 13 | C | Bid select + accept; D confirm | Booking bane | [ ] | [ ] | Diagnose |
| 14 | D | Instant load accept karo | Booking bane, load band | [ ] | [ ] | Diagnose |
| 15 | D+C | Trip OTP: pickup aur delivery par code | Galat code par rok; sahi par aage | [ ] | [ ] | Diagnose |
| 16 | D | POD (delivery proof) photo | Upload ho, customer ko dikhe | [ ] | [ ] | screenshot |
| 17 | C+D | Rating do | Dono taraf save | [ ] | [ ] | Diagnose |
| 18 | C | Bilty (LR) banao | 3 copy: full, driver, consignee | [ ] | [ ] | screenshot |
| 19 | C | Driver copy kholo | Rate / paisa **nahi** dikhna chahiye | [ ] | [ ] | screenshot |
| 20 | C | Inspection mode on/off | Compliance fields chhupein / dikhein | [ ] | [ ] | screenshot |
| 21 | C | LR register kholo | LR ki list aaye; links ka hissa na aaye to bhi LR dikhein | [ ] | [ ] | Diagnose report (LR rows) |
| 22 | C+D | Chat: phone number likhne ki koshish | Warning dikhe, message rok/mask ho | [ ] | [ ] | screenshot |
| 23 | D | Wallet / earnings (sirf `walletHub` ON par) | Balance aur lines dikhein; OFF par tile hi na dikhe | [ ] | [ ] | screenshot |
| 24 | C+D | Help > Diagnose problem > Run check | Har row OK ya saaf code (E-PERM, E-INDEX, E-NET, E-TIMEOUT) | [ ] | [ ] | Copy report |
| 25 | C | Settings > Dark mode | Har screen padhne layak, overflow nahi | [ ] | [ ] | screenshot |
| 26 | C | Phone ka font size sabse bada | Text kate nahi, buttons dikhein | [ ] | [ ] | screenshot |
| 27 | C | Language Hindi | Saare label Hindi, koi English key (jaise `dgTitle`) nahi | [ ] | [ ] | screenshot |
| 28 | C | Airplane mode ON | Offline banner; list cache se; error par E-NET + Diagnose | [ ] | [ ] | screenshot |
| 29 | C | Share: trip link / LR link | Share sheet khule, link kholne par sahi copy | [ ] | [ ] | link ka screenshot (link bhejna mat agar asli data ho) |
| 30 | C | LR / invoice ka Hindi PDF | PDF mein Hindi sahi dikhe (toote akshar nahi) | [ ] | [ ] | PDF ka screenshot |
| 31 | C+D | Call button (in-app call) | Ringing, awaaz dono taraf; mic permission maange | [ ] | [ ] | logs file |

**Sab pass:** is sheet ko `docs/RELEASE_CANDIDATE.md` ke section G/H mein tick karein. **Koi fail:** neeche likho kaun sa row, aur upar wala "Fail par bhejo" bhejein.
