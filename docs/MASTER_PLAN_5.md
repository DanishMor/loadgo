MASTER-5 (single full prompt). Sabse pehle ise bina badle docs/MASTER_PLAN_5.md mein save karke commit karo. Phir neeche ke saare steps ek ke baad ek karo. Permission mat maango. Koi sawaal mat poochho: jahan doubt ho sensible assumption lo aur docs/DECISIONS.md mein ek line likho. Jo pehle se bana hai use check karke skip ya poora karo, duplicate mat banao. Naye bade features nahi, sirf hardening, quality aur chhote free gaps. App ka naam (LoadGo) mat badlo.

STEP 0 - PERMISSIONS (sabse pehle):
Project ki .claude/settings.json mein permissions set karo (valid JSON, apna sahi syntax khud check karo). ALLOW: flutter, dart, git (status, add, commit, push, pull, log, diff, fetch), npm test aur npm install sirf firestore_rules_test mein, ls, cat, grep, sed, mkdir, cp, mv sirf repo ke andar, /tmp/claude-* se padhna aur likhna. DENY hamesha: firebase deploy, git push --force, repo ke bahar rm -rf, .env ya secret files padhna. Phir 5 line mein batao kya allow aur kya deny hai aur aage badho.

RULES:
1. Free stack only. Paid cheez sirf `// LATER(paid)` + docs note.
2. Har task ke baad: flutter analyze 0 issues, us task ke naye aur related tests, rules badle to rules tests, commit. Har 5 tasks ke baad POORA flutter test + rules tests, phir git push. Test fail ho to fix karke aage badho.
3. Har task chhota rakho (10 minute ke andar). Atak jao to docs/BLOCKED.md mein likho aur agle par jao, ruko mat.
4. Naya text 12 languages mein. Paisa integer paise. Server ke bina unsafe cheez "record only" + `// TODO(functions)`.
5. customer/, driver/, fleet/, admin/ ek dusre ko import na karein.
6. Rules/indexes/hosting deploy mat karo. PROGRESS.md har task ke baad update. Context bhar jaye to PROGRESS.md update karke /compact.
7. Shell command block ho (auto mode unavailable) to kuch minute baad dobara try karo, tab tak read/edit wale tasks karo.
8. Restart ke baad MASTER_PLAN_5.md aur PROGRESS.md padh kar wahin se resume.
9. Beech mein rukna nahi. Summary tabhi jab sab khatam ho ya limit aaye.

PHASE A - 50 TASKS (ek ke baad ek):
SECURITY: 1 har collection ke rules audit (deny by default, field whitelist, string/list size limit, server timestamps). 2 har create path par hourly abuse limit coverage. 3 role lock aur identity_index ke tests customer, driver, transporter ke liye. 4 kisi readable doc mein phone number leak na ho (public aur private part alag). 5 admin ke har write par audit log. 6 account deletion mein naye collections (lrs, lr_shares, violations, trip_shares, calls, grants) shamil. 7 data retention doc aur purane records ke expiry fields. 8 Privacy/Terms naye features se match karein.
COST AUR SPEED: 9 har screen ke Firestore listeners: dispose, limit, pagination audit. 10 jahan live stream zaroori nahi wahan one-time fetch. 11 indexes vs queries dobara check. 12 config docs (features, pricing) cache TTL ke saath. 13 build size aur unused assets. 14 app start ka kaam lazy. docs/COST_WATCH.md update.
RELIABILITY: 15 har screen par loading, empty, error, offline state. 16 double tap aur resubmit se duplicate write na ho (idempotent keys). 17 session expire aur token refresh handling. 18 global error handler crash_service se jude, friendly message. 19 back button, navigation stack, deep link consistency. 20 scheduled booking, expiry, inspection grant sab server time se check, device clock galat ho to bhi sahi.
UX: 21 empty states. 22 saare forms ki Indian format validation (vehicle number, pincode, GSTIN, PAN, mobile). 23 accessibility: semantic labels, 48dp tap size, contrast. 24 12 languages QA: missing, duplicate, placeholder mismatch, Urdu aur Kashmiri RTL layout. 25 dark mode ki saari screens. 26 360px aur 1.3x text par saari screens ke layout tests. 27 har role ka pehla-baar tutorial. 28 Driver Simple Mode ki saari screens. 29 notification center polish (grouping, mark all read). 30 search aur filters polish.
CHHOTE FREE GAPS: 31 load post ka step-by-step wizard. 32 cancel reasons aur charge ka saaf message. 33 admin ke liye rating/review moderation. 34 dispute flow mein evidence timeline. 35 driver earnings statement export (CSV aur PDF). 36 invoice PDF polish. 37 transporter party-wise statement export. 38 admin ke saare lists mein CSV export, pagination, saved filters. 39 admin pilot funnel: signup, profile, documents, pehla load, pehli delivery. 40 admin se in-app announcement banner (config se). 41 promo, credits, referral flag OFF mein bhi test mein sahi chalein. 42 Help center FAQ har role ke liye badhao.
TESTING: 43 pure logic ke unit tests (fare, ranker, promo, strike ladder, bilty visibility matrix). 44 rules tests matrix: role x collection x operation (generated). 45 e2e: transporter + bilty + inspection. 46 e2e: chat block, strike ladder, call block. 47 e2e: account deletion har role. 48 layout tests saari screens: 360px, 1.3x, dark. 49 flutter build web aur flutter build apk --debug, saari warnings fix. 50 poora regression, WHERE_IS_WHAT.md, TEST_PLAN.md, BUG_REPORT.md update, push.

PHASE B - BUG HUNT (Phase A ke baad, ya 4 ghante baad, 3 round):
Round 1: lib/ ke har folder (auth, core, customer, driver, fleet, admin) ko ek-ek karke reviewer ki tarah padho: null/crash, galat state, permission-denied (code vs rules), missing index, paise ka galat hisaab, memory leak, text overflow. Har bug docs/BUG_REPORT.md mein (file, kya galat, fix, severity), phir fix aur test.
Round 2: docs/TEST_PLAN.md ke har flow ko test code ke roop mein chalao (customer, driver, transporter, admin, bilty, chat/call), jo toote use fix karo.
Round 3: docs/GAP_AUDIT.md dobara chalao. Naya free gap ya bug mile to fix, tab tak jab tak "Free gaps: 0" aur "Open bugs: 0 (free)". Jo fix paid se hi hoga use Paid/Later likho.

FINAL: poora flutter test, rules tests, analyze 0 issues, git push. Phir summary: kitne tasks hue, kitne bugs mile aur fix hue, kya baaki aur kyun, rules/hosting deploy chahiye ya nahi.
