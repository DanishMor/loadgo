MASTER-6 (single full prompt). Sabse pehle ise bina badle docs/MASTER_PLAN_6.md mein save karke commit karo. ORDER: pehle MASTER-5 ke jo tasks aur bug-hunt abhi baaki hain (docs/MASTER_PLAN_5.md aur PROGRESS.md dekho) unhe poora karo, uske baad is plan ke 50 tasks apne aap shuru karo. Beech mein mere kisi message ka intezaar mat karo. Permission mat maango. Koi sawaal mat poochho: doubt ho to sensible assumption lo aur docs/DECISIONS.md mein ek line likho. Jo pehle se bana hai use check karke skip ya poora karo, duplicate mat banao. App ka naam (LoadGo) mat badlo. Koi asli API key, password ya secret code ya docs mein mat likho.

RULES:
1. Free stack only. Paid cheez sirf `// LATER(paid)` + docs note.
2. Har task ke baad: flutter analyze 0 issues, us task ke naye aur related tests, rules badle to rules tests, commit. Commit message "M6-<task number>: ..." se shuru ho. Har 5 tasks ke baad POORA flutter test + rules tests, phir git push. Test fail ho to fix karke aage badho.
3. Har task chhota rakho (10 minute ke andar). Atak jao to docs/BLOCKED.md mein likho aur agle par jao.
4. Naya text 12 languages mein. Paisa integer paise. Server ke bina unsafe cheez "record only" + `// TODO(functions)`.
5. customer/, driver/, fleet/, admin/ ek dusre ko import na karein.
6. Rules/indexes/hosting deploy mat karo (firebase deploy deny). PROGRESS.md har task ke baad update. Context bhar jaye to PROGRESS.md update karke /compact.
7. Shell command block ho (auto mode unavailable) to kuch minute baad dobara try karo, tab tak read/edit wale tasks karo.
8. Restart ke baad MASTER_PLAN_5.md, MASTER_PLAN_6.md aur PROGRESS.md padh kar wahin se resume.
9. Summary tabhi jab sab khatam ho ya limit aaye.

PHASE A - 50 TASKS (ek ke baad ek):
PILOT OPERATIONS:
1 Invite codes: admin route/role ke saath code banaye, use count aur expiry, signup sirf code ya whitelist se (pilot mode mein). 2 Waitlist: "service nahi hai" screen se waitlist, admin list aur CSV, route khulne par in-app notice. 3 Admin Pilot control room: aaj ke signups, online drivers, open aur unfilled loads, chalte trips, open SOS aur tickets ek screen par. 4 Admin manual dispatch: unfilled load par driver suggest ya assign (audit log), call-back note. 5 Daily aur weekly pilot report: sirf numbers, copy-paste text (WhatsApp ke liye). 6 Time-to-first-bid, time-to-fill, repeat rate, cancel reasons ke cohort numbers, CSV. 7 Trip ke baad 1-tap survey "dobara use karoge?" dono taraf, admin view. 8 Driver payment aging tracker: pending confirmations, admin nudge list.
OWNER AUR ADMIN:
9 Staff roles (super, ops, support, finance) permission matrix rules mein enforce, UI mein jo na use ho wo chhupa. 10 Admin global search (naam, vehicle no, booking id, LR no) role ke hisaab se. 11 Admin user 360 view: profile, documents, trips, ratings, strikes, tickets, risk, audit trail. 12 Bulk actions confirmation aur undo window ke saath. 13 Config JSON editors par schema validation, diff preview, rollback. 14 Admin alerts center: SOS, fraud flag, strikes, ek saath expire hote documents.
CUSTOMER JOURNEY:
15 Load draft save aur resume. 16 Smart defaults: pichla pickup/drop, weight se vehicle suggestion, goods presets. 17 Fare transparency screen aur cancel charge preview. 18 Tracking timeline polish: ETA delay ka karan, trip share link. 19 Address book, har address par GST invoice detail, favourite drivers aur transporters. 20 Delivery ke turant baad rating, issue report aur 1-tap reorder.
DRIVER JOURNEY:
21 Onboarding progress bar, document checklist, reject ka karan aur dobara submit flow. 22 Driver Today home: earnings, upcoming trips, document expiry, recommended loads. 23 Offline-first trip actions: status updates queue, OTP retry, sync indicator. 24 Bid assistant: fare estimate se suggested range aur wajah (30% se 300% rule ke andar). 25 Wallet aur ledger clarity, "paisa kab milega" timeline polish, kisi katautee par dispute. 26 Safety: raat ke trip ka prompt, rest reminder, emergency contact ka in-app check.
TRANSPORTER:
27 Onboarding aur verification polish, fleet attach invite flow tests. 28 Dashboard: trips status-wise, vehicle utilisation, driver-wise trips, party-wise pending amount. 29 Load board filters, saved routes, margin rule ke saath bulk bid. 30 Party aur month-wise statement export (CSV aur PDF).
BILTY, CHAT, CALL, SAFETY:
31 LR register: list, search, status, share links ka management (active, expired, revoked). 32 Inspection mode polish: owner approval screen mein trip context, grant history. 33 Chat quick replies (Hindi, Hinglish), read receipts, rate limit. 34 Strike appeal: user appeal kare, admin review, strike ghate ya bahal. 35 Call UX: states, failure par saaf message aur chat fallback, "Test my mic" screen. 36 Trust badges: on-time %, completion %, repeat customers, record se compute, display rules.
QUALITY AUR PERFORMANCE:
37 Performance pass: asset sizes, list virtualization, unnecessary rebuilds, const widgets, profile-mode checks doc mein. 38 Startup: lazy init, Remote Config fetch fail ho to default values. 39 Offline matrix: har screen par kya chalta hai, kya stale dikhta hai, tests. 40 Low-end device mode: animations kam, text scale 2.0 par safe layout. 41 Error taxonomy: permission-denied, unavailable, deadline-exceeded sab ke friendly translated messages har jagah. 42 Crash breadcrumbs bina PII ke, PII redaction ke tests.
RELEASE TAIYAARI:
43 Android release config: package id ek jagah se badalne layak (abhi com.example hi, naam mat badlo), icon placeholders, unused permissions hatao, docs. 44 PLAY_STORE_CHECKLIST update: data safety form ke jawab ka draft, content rating notes, screenshots plan, listing text draft (Hindi, English, Hinglish). 45 Legal drafts: Privacy, Terms, Refund, Driver aur Transporter agreement, sab par "DRAFT, vakeel se review zaroori", hosting pages. 46 Paid-readiness: SMS OTP, push, maps, payments, KYC, storage ke liye clean adapter interfaces + fake implementations + contract tests, docs/PAID_ADAPTERS.md (taaki paid service baad mein plug ho). 47 Security review doc update: threat model, client-only checks ki list, owner ke liye pentest checklist.
DOCS AUR TESTS:
48 docs/OWNER_GUIDE.md (Hinglish): pilot kaise chalayein, roz ki checklist, har admin screen ka kaam, SOS, accident, fraud, dispute ka playbook. 49 Tests: generated rules matrix badhao, naye screens ke layout aur golden tests, pilot flows ka e2e (invite code, waitlist, dispatch). 50 Poora regression, WHERE_IS_WHAT.md, TEST_PLAN.md, BUG_REPORT.md update, push.

PHASE B - BUG HUNT (Phase A ke baad, ya 4 ghante baad, 3 round):
Round 1: lib/ ke har folder (auth, core, customer, driver, fleet, admin) ko reviewer ki tarah padho: null/crash, galat state, permission-denied (code vs rules), missing index, paise ka galat hisaab, memory leak, text overflow. Har bug docs/BUG_REPORT.md mein (file, kya galat, fix, severity), phir fix aur test.
Round 2: docs/TEST_PLAN.md ke har flow ko test code ke roop mein chalao (customer, driver, transporter, admin, bilty, chat/call, pilot), jo toote use fix karo.
Round 3: docs/GAP_AUDIT.md dobara chalao. Naya free gap ya bug mile to fix, tab tak jab tak "Free gaps: 0" aur "Open bugs: 0 (free)". Jo fix paid se hi hoga use Paid/Later likho.

FINAL: poora flutter test, rules tests, analyze 0 issues, flutter build web aur apk --debug, git push. Phir summary: kitne tasks hue, kitne bugs mile aur fix hue, kya baaki aur kyun, rules/hosting deploy chahiye ya nahi.
