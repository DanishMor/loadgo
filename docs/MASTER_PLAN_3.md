MASTER-3. Pehle ise docs/MASTER_PLAN_3.md mein bina badle save karke commit karo. Permission mat maango, beech mein mat ruko, jab tak sab khatam na ho. Jo pehle se bana hai use skip ya poora karo, duplicate mat banao.

PHASE 1 - TASK 67 TRANSPORTER (fleet role ko upgrade karo, naya role mat banao):
1. "Fleet owner" ki jagah har jagah "Transporter" (12 languages). Flag config/features.transporter, testing ke liye default ON.
2. Profile: company naam, GST (format check), PAN, office city, operating routes, vehicle types, vehicle count. Admin approval ke baad "Verified transporter" badge.
3. Vehicles: apne + attach kiye hue (owner driver ki consent se, phone invite). Documents expiry reminders.
4. Loads dekhna, company ki taraf se bid, jeetne par vehicle + driver assign, reassign (audit log). Booking mein fleetOwnerId.
5. Transporter khud load post kar sake ("posted by transporter" tag). Role lock aur identity rules na tootein.
6. Trips list, status, ETA delay alert, LR/bilty.
7. Hisaab (record only): trip par margin, driver ko dena, party-wise baaki rakam.
8. docs/TRANSPORTER.md.

PHASE 2 - SECURITY (rules tests pehle likho): transporter admins collection na padh/likh sake, dusre transporter, customer ya driver ka data na dekh sake, role/fleetOwnerId/riskTier/plan/wallet na badal sake. Admin sirf admins/{uid} se bane.

PHASE 3 - TASK 68 PRIVATE CHAT AUR CALL:
1. Customer, driver, transporter ko ek-dusre ka number kahin na dikhe: tel: tap-to-call hatao, sirf naam, rating, vehicle number, verified badge. SOS aur 112 alag. Admin ko dono ka number dikhe, har baar audit_events mein likha jaye.
2. Chat mein phone number, UPI id, WhatsApp/Telegram/"call me", digits, Hindi aur Hinglish shabd, toote hue number ("nau aath teen", dots, spaces) pakdo. Message BHEJNE SE PEHLE block ho aur warning dikhe.
3. Strike ladder: violations/{id} create-only, users.chatStrikes +1 same batch mein (rules enforce, jaise cancelCount). 1-2 warning, 3: chat+call 24 ghante band, 4: 3 din, 5: 7 din + admin review. 30 din saaf rehne par strikes ghatein. chatBlockedUntil rules mein check ho (message aur call create refuse), blocked user ko saaf message (12 languages).
4. "Number maanga ya bheja" report button.
5. In-app voice call: interface CallProvider, free WebRTC (flutter_webrtc, signaling Firestore, STUN), tabhi ring jab app khula ho, sirf confirmed booking mein, mic permission dialog. // LATER(paid): masked-number provider + push.
6. Admin: violations list, chat sirf report ya dispute par dekhna, suspend badhana/hatana.
7. Privacy Policy aur Terms mein likho ki safety ke liye admin chat aur call metadata dekh sakta hai. docs/PRIVATE_COMM.md.

PHASE 4 - FEATURE MAP: docs/WHERE_IS_WHAT.md banao: har role (customer, driver, transporter, admin) ke liye har feature UI mein kahan hai (kaun si screen, kaun sa menu) aur kaun sa feature flag ON/OFF hai. Admin > Features screen mein har flag ke saath ek line ka matlab dikhao. Jo naye features Profile menu mein chhupe hain unhe Home par saaf entry do (driver aur customer, simple).

PHASE 5 - NAAM KI TAIYAARI: app ka display name aur tagline ek hi constant (core/app_info.dart) se aaye, strings, splash, Terms, Privacy, hosting/*.html, Android label, web title aur manifest sab usi se. Abhi naam mat badlo, sirf ek jagah se badalne layak banao. docs/NAMING.md mein likho ki naam badalne ke liye kaunsi file aur kya kya badalna hai.

PHASE 6 - BUG HUNT: Phase 1-5 ke naye code par rules vs code (permission-denied), indexes vs queries, crash paths (null, purane documents, offline), security abuse (chat, strike, transporter, role), paise ka logic. flutter build web aur apk --debug chalao. test/e2e mein transporter + private chat flow ka test. docs/BUG_REPORT.md update.

PHASE 7 - LOOP: docs/GAP_AUDIT.md dobara chalao. Naya FREE gap mile to task banao aur karo, tab tak jab tak "Free gaps: 0".

RULES:
1. Sirf FREE stack (Flutter, Firebase Auth, Firestore, Hosting, free packages). SMS, FCM sender, Maps API, payment, KYC API, masked calling, Cloud Functions, AI API: sirf `// LATER(paid)` + docs.
2. Har task ke baad: flutter analyze 0 issues, naye tests, flutter test pass, rules tests pass, commit, har 3 par push. PROGRESS.md update.
3. Naya text 12 languages mein. Paisa integer paise. Server ke bina unsafe cheez "record only" + `// TODO(functions)`.
4. customer/, driver/, transporter(fleet)/, admin/ ek dusre ko import na karein.
5. Rules/indexes/hosting khud deploy mat karo. Context bhar jaye to /compact. Block ho to docs/BLOCKED.md.
6. Restart ke baad MASTER_PLAN_3.md, PROGRESS.md padh kar resume.

FINAL: regression test, ROADMAP_STATUS.md aur GAP_AUDIT.md final counts, README, push. Summary: kya bana, kya baaki, rules/indexes deploy chahiye ya nahi.
