LOAD 20 - PART 4: PREMIUM FLOW + BID ENGINE (single prompt). Sabse pehle ise bina badle docs/MASTER_PLAN_PART4.md mein save karke commit karo. Windows laptop (PowerShell), project C:\projects\loadgo, sirf is folder mein kaam karo. Permission mat maango, sawaal mat poochho: doubt ho to sensible assumption lo aur docs/DECISIONS.md mein ek line likho. App ka naam "Load 20". Pehle docs/PROGRESS.md, RESUME.md, KNOWN_ISSUES.md, BLOCKED.md, WHERE_IS_WHAT.md, DESIGN_SYSTEM.md, ROADMAP_STATUS.md, FLOW docs aur lib/core/widgets padho. Jo bana hai (offers aur counter-offer, geohash nearby, ranker, trust card, rate range, safety check-in, adapters, flags, wallet) reuse karo, duplicate mat banao.

OWNER KA FEEDBACK (asli emulator test se): "Pichle design round mein sirf rang aur font badle, layout aur flow andar se bilkul pehle jaise hain. Mujhe naya premium layout, naya booking tarika, aur driver ke paas load ka alag unique tareeka chahiye (Uber, Rapido, WheelsEye jaisa feel, par original), aur usme bidding (boli) ho." Ye is round ka asli maqsad hai.

GLOBAL RULES:
1. Koi purana feature, flag, OTP ya security limit, rules test ya guard test kamzor ya delete mat karo. Purani screens delete mat karo: naya UI flag uiV2 ke peeche (default ON), naya dispatch aur bid engine flag dispatchV2 ke peeche (default OFF, kyunki naye rules deploy hone ke baad hi chalenge). dispatchV2 OFF par naya UI purane data model (open load + offers) ke saath chale.
2. firebase deploy KABHI mat chalao. Phone, emulator ya flutter run mat chalao, naya apk mat banao. Koi asli key ya secret kahin mat likho. Package id mat badlo.
3. Har task chhota (15 minute): flutter analyze 0 issues, related tests, commit "U<n>: ...", har 3 task par git push (DanishMor ka local config; 403 aaye to sirf batao). Har phase ke end par git tag ux-v2-phase<n>. docs/RESUME.md har task ke baad update (LAST_DONE, NEXT, unfinished). Block ho to docs/BLOCKED.md.
4. Naya text 12 languages mein, Hindi-first aur chhote vaakya. Paisa integer paise. customer/, driver/, fleet/, admin/ ek dusre ko import na karein. Hard-coded Color ya TextStyle nahi (guard test).
5. MEMORY: flutter test sirf chhote hisson mein, flutter test --concurrency=1 <path>. Test se pehle free memory dekho, 3 GB se kam ho to 2 minute ruko. Sirf PowerShell. Generated plugin files, coverage/, android/build/ commit mat karo.
6. Competitor research mein sirf public pages (official sites, Play Store listings, help pages). Kisi ka text, logo, illustration ya screen copy mat karo, sirf pattern seekho aur original banao. Verify na ho to UNVERIFIED likho.
7. Restart ya limit ke baad docs/RESUME.md aur MASTER_PLAN_PART4.md padh kar wahin se resume. Context bhar jaye to RESUME.md update karke /compact.

PHASE 1 - RESEARCH AUR SPEC:
U1 docs/UX_RESEARCH.md: Uber, Rapido, Porter, WheelsEye, Vahak, BlackBuck, inDrive (bidding), Ola ke public pages se: load request driver tak kaise jaata hai, accept timeout, bidding aur counter flow, customer kaise chunta hai, trust cues. Table: pattern, kis app mein, hamare liye kya apnayen. U2 docs/FLOW_SPEC.md: customer, driver aur dispatch ke poore flows aur states. U3 docs/DESIGN_UPGRADE_SPEC.md: principles (har screen par ek primary action, thumb zone, bade targets, kam text, progressive disclosure, trust cues, motion budget, kam padhe-likhe driver ke liye icon-first), Load 20 ke apne signature elements (route ribbon, price meter, countdown ring, slide to confirm, live bid cards), screen inventory before aur after. U4 docs/OWNER_REVIEW_UX.md: 1 page, kaam rukna nahi chahiye.

PHASE 2 - COMPONENT KIT (core/widgets/ds):
U5 RouteRibbon (pickup to drop, distance, CustomPainter, offline), FareMeter (price range bar, estimate marker, hint text). U6 CountdownRing, SlideToConfirm (haptic, accessibility ke liye button fallback), BidCard, DriverMiniCard (naam, rating, trips, verified, trust card flag), StatusTimeline v2. U7 BottomSheet kit, skeletons, empty aur error illustrations, quick-chip rows. U8 FeedbackKit: haptics, ek chhota sound alert (asset, quiet hours aur LowEndMode ka maan), in-app heads-up banner. U9 Har component ke widget tests (360x640, 2.0x text, light, dark, RTL, LowEndMode) aur ek tool jo key components ko PNG mein render kare (fonts load karke) taaki tum khud dekhkar overlap aur ugly spacing theek karo.
Phase end: tag ux-v2-phase2.

PHASE 3 - DISPATCH AUR BID ENGINE (flag dispatchV2):
U10 DATA MODEL: loads.mode = instant | bid | scheduled; bidWindowEnds; autoAccept {maxPaise, minRating, verifiedOnly}; config/dispatch {ringsKm [3,7,15], ringDelaySeconds [0,30,60], acceptSeconds 30, bidWindowMinutes 10, city-wise override}; offers mein etaMinutes, note chip, tags (bestPrice, nearest, topRated computed). Purane documents ke liye safe defaults (mode instant). Rules, indexes aur rules tests. tool jo purane loads ko migrate kare (dry-run default).
U11 WAVE VISIBILITY (client): driver ki feed mein load tabhi dikhe jab uski ring unlock ho (driver ki lastLocation se pickup tak distance aur load ke server timestamp se bita time). Pure Dart DispatchWindow aur tests. Docs mein likho: ye client-side UX layer hai, asli enforcement server wave (functions, push flag) deploy ke baad.
U12 INSTANT MODE: customer apna price chunta hai (FareMeter ke range mein), nazdeeki drivers ko wave mein request jaati hai, driver 30 second (config) mein accept ya bid kare, pehla valid accept jeete (Firestore transaction: open se matched, baaki ko "kisi aur ne le liya"), koi na le to ring chhoti se badi, customer "price badhao +5% ya +10%" ya "range badhao" kar sake.
U13 BID MODE (boli): Bid Room kholte hi bidding window start. Drivers price bhejte hain (30% se 300% fare estimate rule ke andar), ek driver ek active bid, ek baar edit ya withdraw. Customer sab bids dekhe, ek baar counter kare, accept kare. Window khatam ya customer accept par baaki bids band. Koi bid na aaye to saaf suggestions (price badhao, time badhao, instant par jao, schedule karo).
U14 AUTO-ACCEPT: customer rule set kare (max price, minimum rating, verified only). Jab tak customer ka app khula hai client bid evaluate karke accept kare (transaction). Server function skeleton (flag OFF) jo baad mein app band hone par bhi kare. Docs mein limit likho.
U15 FAIRNESS AUR ABUSE: driver doosre drivers ki bids na dekhe (rules), customer sabki dekhe; per-load aur hourly limits (purani limits intact); off-platform detector chat mein pehle jaisa; cancel aur no-show records; price floor aur ceiling. Rules tests, concurrency test (do drivers ek saath accept).
U16 INCOMING-LOAD CONTRACT: driver app mein full-screen ya heads-up card ke liye single stream (LoadRadar service) jo sirf unlock hui, driver ke vehicle type se match hone wali, abhi tak open loads de; dedupe, expiry, ek ke baad ek queue.
U17 ADMIN DISPATCH MONITOR: live loads (ring, kitne drivers ko dikha, kitne bids), time-to-first-bid, time-to-fill, acceptance rate, price vs estimate, kitne loads bina bid ke expire hue. Staff roles ke hisaab se.
Phase end: rules tests, tag ux-v2-phase3.

PHASE 4 - CUSTOMER UX V2 (flag uiV2):
U18 HOME: ek bada "Truck book karo" action, 3 mode ek line mein samjhaye (Turant, Boli, Schedule), recent routes aur templates chips, chalta hua trip card, trust strip. Bottom nav: Home, Trips, Help, Profile (kamai aur hisaab tab sirf flag ON par).
U19 BOOK WIZARD (5 steps, har step par ek sawaal, progress, draft autosave, back safe): 1 Route (recent, saved, city typeahead, RouteRibbon). 2 Maal (goods preset chips, weight slider jo vehicle suggest kare). 3 Gaadi (vehicle cards: capacity, typical range). 4 Price aur Mode (FareMeter, rateRange flag ka data, mode picker, schedule). 5 Review (RouteRibbon, total, promo ya credits agar on, terms) aur slide to confirm.
U20 BID ROOM: live bid cards (DriverMiniCard, price, ETA, tags), sort chips (Best price, Nearest, Top rated, Fastest), CountdownRing, accept aur counter, "price badhao" aur "time badhao", auto-accept rule sheet, chat (number chhupa hua).
U21 TRIP TRACKING V2: StatusTimeline, pickup aur delivery OTP bade cards, trip share, SOS, safety check-in (flag), ETA; map flag ON ho to map, warna RouteRibbon.
U22 DELIVERY: POD, payment record, tip, rating, 1-tap reorder.
U23 TRIPS tab: active, upcoming, past, filters, reorder.
U24 BILTY DISCOVERABLE: booking detail mein "Bilty banao" ka saaf button (customer aur transporter), 3 copy preview (Full, Driver, Consignee), kya hide hoga ka preview, share. Pehle ye chhupa tha, owner ko mila nahi.
U25 Profile, settings, help polish. U26 Har naye screen par loading, empty, error, offline states.
Phase end: tag ux-v2-phase4.

PHASE 5 - DRIVER UX V2:
U27 HOME: bada online/offline switch, aaj ki kamai, vehicle selector, "Radar" status (load dhoondh raha hai), upcoming trips, document expiry alert, Simple Mode ke saath compatible.
U28 INCOMING LOAD CARD (signature): full-screen card, RouteRibbon, pickup tak driver ki doori, trip km, goods aur weight, fare, CountdownRing (config se), SlideToConfirm "Accept at fare", "Apna price bhejo" (chips -5, +5, +10 aur custom, FareMeter), "Skip" (optional wajah), foreground sound aur vibration (quiet hours ka maan), ek se zyada load ho to queue, expired par "Load kisi aur ne le liya". App background mein ho to push flag ke baad, abhi sirf in-app.
U29 BID SHEET: range hints, ETA chips, note chips, edit aur withdraw. U30 LOADS FEED (browse): filters, saved routes, match reasons. U31 MY BIDS: statuses (pending, countered, selected, lost).
U32 TRIP FLOW: bade buttons (pahuncha, loading proof, in transit, delivered OTP), check-ins, offline queue.
U33 EARNINGS aur payout timeline polish. U34 ONBOARDING aur documents: progress bar, clear states, reject ka karan.
Phase end: tag ux-v2-phase5.

PHASE 6 - TRANSPORTER AUR ADMIN:
U35 Transporter dashboard v2: Bid Room se company ki taraf se bid, bulk bid margin rule (purana BulkBid reuse), vehicle aur driver assign. U36 Admin screens naye component kit se (saada, consistent), dispatch monitor. U37 Staff roles aur Admin mode banner waise hi.

PHASE 7 - BAKI KAAM:
U38 docs/KNOWN_ISSUES.md, BLOCKED.md ke free items, ROADMAP_STATUS Partial aur Todo-free, code mein TODO (LATER(paid) aur TODO(functions) chhod ke): sab poore karo. Naye flows ko docs/WHERE_IS_WHAT.md, docs/FLOW_SPEC.md, docs/DESIGN_SYSTEM.md, TEST_PLAN.md, RELEASE_CANDIDATE.md (screen-by-screen phone test sheet naye flows ke saath) mein update karo.

PHASE 8 - QA AUR BUG HUNT:
U39 Layout tests har naye screen par (360x640, 2.0x text, light, dark, RTL, LowEndMode). U40 e2e tests: instant booking, bid booking, auto-accept, bid expiry, koi bid nahi, do drivers ka ek saath accept (race), counter-offer, bilty banana. U41 Rules aur concurrency tests. U42 Key screens ke PNG render karke khud dekho aur overlap, kata hua text, kharab spacing theek karo. U43 Bug hunt 3 round (null aur crash, permission-denied code vs rules, missing index, paise ka galat hisaab, race, memory leak, overflow, dark mode, RTL, abuse), har bug docs/BUG_REPORT.md mein, fix aur test. U44 Poora regression (chhote batch), analyze 0 issues, flutter build web --release, GAP_AUDIT "Free gaps: 0, Open bugs: 0 (free)".

END: 12 line ka summary: kya bana, kya block hua aur kyun, naye flows ka short walkthrough (customer aur driver), kaunse flag on karne hain aur kis order mein (rules publish ke baad dispatchV2), test results, mujhe kya karna hai.
