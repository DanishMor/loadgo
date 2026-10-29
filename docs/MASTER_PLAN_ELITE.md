LOAD 20 - ELITE MASTER PROMPT (single prompt, three waves). First, save this prompt unchanged as docs/MASTER_PLAN_ELITE.md and commit it. Windows laptop (PowerShell), project C:\projects\loadgo, work only inside this folder. Never ask for permission and never ask questions: when in doubt take the safest sensible assumption and write one line in docs/DECISIONS.md. The app name must always come from AppInfo (never hard-code "Load 20").

MISSION
Take Load 20 (Flutter + Firebase freight marketplace: customer, driver, transporter/fleet, business, admin) from a strong build to a luxury, premium, India-first brand with world-class features. Quality bar: every screen calm, fast, respectful, trustworthy; every feature complete end to end, tested, behind a flag; nothing half-built is ever reachable.

STATE (do not rebuild what exists)
Parts 1 to 5, the U plan (premium flow and bid engine), H plan (security hardening), Z plan (final free work, tag final-free-complete) are done. Existing: instant/bid/scheduled modes, Bid Room, Incoming Load Card, LoadRadar, auto-accept, bilty/LR with 3 copies, e-way bill record, GST invoice, trip share, SOS, safety check-in, chat with contact-sharing strikes, in-app WebRTC call, claims, ratings, tickets, wallet records, payouts, tips, incentives, referral, promo, Pro plan, fleet and business accounts, truck board, import/export, multi-stop, rental, movers, 12 languages, Diagnose screen, kill-switch groups, tools (tool/phone.ps1, tool/status.ps1, tool/run_regression.ps1, tool/check_indexes, tool/rules_app_drift, translation tools). Z9 (test lab) was skipped on purpose. Read first: docs/RESUME.md, PROGRESS.md, KNOWN_RISKS.md, NOT_FREE.md, BLOCKED.md, DECISIONS.md, RULES_CONTRACT.md, RULES_CHANGES_NEEDED.md, FLOW_SPEC.md, DESIGN_SYSTEM.md, WHERE_IS_WHAT.md, SECURITY_SCORECARD.md, COST_WATCH.md, PERFORMANCE.md, TESTING.md, PHONE_SMOKE_SHEET.md, firestore.rules, storage.rules, firestore.indexes.json, functions/, tool/. Reuse everything that exists; never duplicate.
The live Firebase rules may be older than the repo rules until the owner publishes them: the app must degrade gracefully (Diagnose, E-PERM reason codes) and never crash.

OWNER BUGS FROM PHONE TEST: if docs/OWNER_BUGS.md exists, fix every item in it first (E1) with tests; otherwise skip E1.

HARD RULES
1. Nothing may break. Never weaken, skip or delete any test, rule, OTP limit, security check or flag. Everything new is behind a flag that defaults OFF, except the visual upgrade (flag designV3 default ON; Classic theme equals today's look and stays selectable). No half-built screen may be reachable: hide or disable with a clear reason.
2. Never run firebase deploy. Never run the app on a phone or emulator, never install anything on a device, never build an APK or app bundle (the owner builds). flutter build web --release (normal and APP_MODE=admin) only at the very end and only when free memory is above 5 GB and no test is running.
3. No real keys, passwords, tokens, keystores anywhere (code, docs, logs, terminal). All outside services go through an abstract adapter with a fake adapter used by tests and default builds; the real adapter is selected only when its flag is ON and its key exists. No paid call may happen by default. Every paid-capable adapter has cost guards (daily caps, per-user caps, kill switch).
4. Money: integer paise only. No real money moves. Anything regulated (escrow/payment hold, wallet payouts, loans, insurance, credit) sits behind legalGate.<name> flags that need an explicit owner action, ships with disclaimers, and never promises insurance, lending or guaranteed payment. Copy must not make legal or tax claims; calculators carry "check with your CA".
5. Competitor and market research: public pages only (official sites, Play listings, help pages). Take ideas and patterns, never text, images, logos or layouts. Label anything not verified UNVERIFIED. Never draw any manufacturer logo or name on vehicles; use generic names. Do not state facts about other brands in the app.
6. Firestore and Storage rules: additive and tight only, deny by default, field whitelists, types and size limits, server timestamps, legal state transitions. Every new collection gets rules, rules tests, red-team matrix cases, RULES_CONTRACT flows, an index check (tool/check_indexes) and an app/rules drift check (tool/rules_app_drift). The load-create rule already sits near the 1000-expression limit and firestore.rules is about 243 KB (limit believed near 256 KB, UNVERIFIED): keep every new rule compact, reuse helpers, and track size with E2. Anything that must be published goes into docs/RULES_CHANGES_NEEDED.md.
7. Dependencies: add a package only when the feature cannot be built without it. Prefer none. Justify each in docs/LICENSES.md (licence, size impact, maintenance, Kotlin Gradle Plugin compatibility: the release build already warns about KGP for firebase_* and flutter_webrtc, so never add a plugin that worsens it). One package per commit; after each: pub get, analyze, related tests; if anything breaks, revert and log BLOCKED.md. Fonts and images must have open licences recorded in docs/LICENSES.md. APK size growth must be tracked in docs/SIZE.md (prefer vector and procedural art over bitmaps).
8. Architecture: customer/, driver/, fleet/, admin/ never import each other; shared code lives in core/. Design tokens only: no raw Color or TextStyle (guard test). Every new text in all 12 languages (Hindi first); no tofu glyphs; Urdu and Kashmiri RTL.
9. Every task: at most about 20 minutes (split into a, b if larger), flutter analyze 0 issues, related tests only (flutter test --concurrency=1 <path>, never the full suite at once), commit "E<n>: <what>", git push every 3 tasks (DanishMor local config; on 403 just report), tag elite-phase<n> at each phase end, update docs/RESUME.md after every task (LAST_DONE, NEXT, unfinished). If blocked, write docs/BLOCKED.md and move on.
10. Windows: PowerShell only, ASCII output, scripts with Set-StrictMode. Run the regression only through tool/run_regression.ps1 (keep-awake, stall watchdog). Free memory must be above 3 GB before tests; wait 2 minutes if lower. Do not commit generated plugin files, coverage/, build/, android/build/, build/symbols, or line-ending-only diffs (check git diff --ignore-space-at-eol before committing firestore_rules_test/contract/captured.json).
11. Every feature needs: loading, empty, error, offline states; text scale 2.0; light and dark; LowEndMode; reduce-motion; TalkBack labels; tests for logic and widgets; defensive parsing; no unbounded lists or listeners; reads and writes counted in docs/COST_WATCH.md.
12. Honesty: vehicle specs and any numbers you cannot verify are marked approximate and put in an owner review sheet. Demo data lives only in tests. At each wave end print a 10-line checkpoint and continue automatically; never wait for the owner.
13. After every phase run a critic pass: re-read your own diff, remove dead code and duplication, fix naming, and confirm nothing from rule 1 is violated.
14. On restart or limit: read docs/RESUME.md and docs/MASTER_PLAN_ELITE.md and continue exactly where you stopped. If context fills, update RESUME.md and /compact.

WAVES: Wave 1 = phases 0 to 3 (tag elite-wave1). Wave 2 = phases 4 to 14 (tag elite-wave2). Wave 3 = phases 15 to 18 (tag elite-complete).

PHASE 0 - SAFETY NET
E0 Git clean, tag pre-elite, baseline numbers in docs/BASELINE_ELITE.md (test count, analyze, web build size, listeners per screen, rules size, release APK size from docs).
E1 Fix docs/OWNER_BUGS.md items with tests (if the file exists).
E2 Rules budget: measure firestore.rules size and expression use; shrink without changing behaviour (condense comments, merge duplicate helpers); add tool/rules_size.ps1 and a test that fails above 235 KB; document the plan if the budget still runs short (docs/RULES_BUDGET.md).
E3 Flag registry: every new flag listed in docs/FLAGS.md with default, dependency, risk and the order to switch on; admin Features screen groups; guard test that every new entry point checks its flag; kill-switch groups extended.
E4 Connect-ready kit: abstract adapters with fakes and cost guards for Storage/Photo, Maps, Toll, Places, Push, SMS, WhatsApp, Payment, Payout, KYC/Liveness, OCR, Translation, TTS/Speech, Device telemetry, Insurance, Credit partner links, ERP webhooks; config/providers doc; docs/CONNECT_<name>.md per adapter (owner steps, what it needs, cost note marked UNVERIFIED); test that every adapter has a fake, a flag and a cost guard.
E5 docs/LICENSES.md and dependency policy test (no unlisted package).

PHASE 1 - LUXURY BRAND AND DESIGN SYSTEM
E6 docs/BRAND_GUIDE.md: positioning (premium, trustworthy, Indian, respectful to drivers), voice ("aap", short sentences), tagline kept, logo usage, token set, motion principles, sound, haptics, imagery, do and do not. Palette: Navy and Ink with one Gold accent on Ivory; WCAG AA contrast verified by a test.
E7 Themes: Signature (Ivory), Midnight (true-black option, gold accents), Classic (today's look). Switch in Settings, follow-system option, persisted, parity in every component.
E8 Typography: bundle open-licence fonts covering Latin, Devanagari, Kannada, Tamil, Telugu, Marathi, Gujarati, Bengali, Gurmukhi, Arabic script; tabular figures for prices; type scale; fallback chain; a render test per language to catch missing glyphs.
E9 Motion and feedback: spring curves, hero transitions, route-line draw, shimmer skeletons, restrained success moments, haptic map, subtle sound (quiet hours, LowEndMode), reduce-motion respected, animation budget per screen.
E10 Component upgrade: buttons, cards, sheets, nav bar, chips, inputs, price display, badges, avatar, rating, timeline; 12-language overflow safe; widget tests across sizes.
E11 Original vector illustration set (empty, error, onboarding, success, offline) in one consistent style, drawn in code or SVG, no third-party artwork.
E12 docs/COPY_DECK.md and a copy pass on every screen and error message (respectful, short, Hindi-first).
E13 Render pipeline: use the existing PNG screen renderer to build tool/render_gallery.ps1 (key screens x 3 themes x sizes x languages), review the images yourself for spacing rhythm, alignment, truncation, contrast; iterate until clean; keep docs/DESIGN_REVIEW.md with before and after.
E14 Splash, adaptive and monochrome icon variants, store asset specs (docs/STORE_ASSETS.md), and a fast static landing page in hosting/ that keeps all existing rewrites, headers and routes (prove with a test).

PHASE 2 - VEHICLE CATALOG AND IMAGERY
E15 Vehicle catalog data (assets, not Firestore): id, group, name in 12 languages, wheels and axle layout, typical length, width, height, payload range in tons marked approximate, typical goods, "choose when" line, body types, price band hint. Types: bike delivery, 3-wheeler cargo (auto and e-loader), e-rickshaw loader, mini truck, pickup (8 ft), 14, 17, 19, 20, 22, 24 ft, 32 ft single axle, 32 ft multi axle, 6, 10, 12, 14 wheeler, container 20 ft and 40 ft, trailer/flatbed, low-bed, tipper, tanker, reefer, car carrier, hydra/crane. Schema, validator, tests, and docs/VEHICLE_REVIEW.csv for the owner to correct numbers.
E16 One parametric vehicle painter (CustomPainter) with a single refined 3/4-side style: body variants (open, closed, container, flatbed, tanker, tipper, reefer, 3-wheeler, bike), wheel and axle layout, light, dark and gold-outline variants, no brand marks. Render a gallery to docs/gallery/vehicles and golden-test silhouettes.
E17 Vehicle UI: catalog screen, vehicle cards, spec sheet, size comparison (person, car, doorway at true scale), compare 2 or 3 vehicles, "what fits" calculator (goods plus weight plus volume to a suggested vehicle), used in the booking wizard, bid cards and truck board.
E18 Driver vehicle photos [connect-ready, flag vehiclePhotos]: slots front, rear, left, right, load area, number plate, RC (and cab optional) with guide overlays; on-device quality checks (blur, brightness), resize and EXIF strip; PhotoAdapter (fake now); storage.rules with owner-only write, size and type limits; Firestore metadata with compact rules; RC and plate close-ups private to owner and admins, exterior photos visible only to the driver, admins and customers who hold an offer or booking with that driver (pick the cheapest rule and record the trade-off in DECISIONS.md); admin photo review queue; "Photo-verified" badge with 6-month expiry and reminders; customers see verified photos on bid cards; plate text cross-check through OcrAdapter.
E19 Cargo photos [flag cargoPhotos]: customer load photos, seal and loading photos, damage reports with photos, all through PhotoAdapter and the same abuse limits.
E20 Optional turntable view of the vehicle painter: ship only if it meets the animation budget on LowEndMode, otherwise skip and log.

PHASE 3 - HOME LAYOUTS AND NAVIGATION
E21 Customer home v3: sections registry (booking hero, live trip card with route ribbon and ETA, vehicle carousel, repeat and saved routes, offers, "Load 20 Promise" trust strip, Sahayak entry, recent LRs, referral); reorder and hide persisted; skeleton and first-run variants.
E22 Driver home v3: big online switch with radar pulse, earnings ring, document health, level and streak, return-load suggestion, demand strip (connect-ready), quick actions, recent bids.
E23 Transporter and business command center: fleet status board, pending bids, dues, alerts, utilisation.
E24 Admin ops home: live loads and dispatch monitor, queue counts (KYC, photos, claims, tickets), kill-switch shortcuts.
E25 Navigation shell: bottom nav with state kept per tab, deep links, notification center entry, global search across loads, bookings and LRs, TalkBack order.
E26 Onboarding v3: premium 3-slide tour, role pick, value-first permission primers (location, notifications), documents requested right after OTP, customer and driver identity separation preserved.

PHASE 4 - BOOKING, PRICING, QUOTES (Wave 2 starts)
E27 Price transparency card and fair-price meter: full breakdown, range, "why this price", tax shown, no hidden fee (guard test).
E28 Return load and round-trip booking; multi-drop polish; part-load (shared load) model behind flag partLoad.
E29 Bulk load upload (CSV and Excel) for business: template download, preview, per-row errors, limits.
E30 Rate contracts and lane-wise RFQ/tender: business posts a lane, transporters bid, business awards; records only.
E31 Share a booking or quote summary as image or PDF (Hindi-capable) and via share sheet.
E32 Cargo insurance request flow (InsuranceAdapter fake, legalGate.insurance, quote request only, no sale).
E33 Toll and route estimate (TollAdapter and MapsAdapter fakes), include toll in estimate when ON; admin-editable city entry-restriction notes (no unverified claims).

PHASE 5 - DISPATCH AND MATCHING
E34 Driver reliability and acceptance score (formula in docs, tests), shown to customers as badges, not raw numbers.
E35 "I am going to" mode and return-load suggestions from favourite routes; matching function with tests.
E36 Priority dispatch for Black customers (ring bonus config); demand cells read from an aggregated collection written only by functions (skeleton, flag OFF), client read-only.
E37 ETA, geofence arrival and route-deviation alerts (client logic, tests, MapsAdapter fake).
E38 Auto-accept polish and "why this bid is highlighted" explainers.

PHASE 6 - TRUST AND SAFETY
E39 Trust Passport for drivers and customers (verification, document freshness, photo-verified, ratings, completion, tenure), privacy-safe.
E40 Safety suite: silent SOS (shake or button), crash and sudden-stop detection with sensor adapter, config thresholds and synthetic-data tests, long-stop and deviation alerts, fatigue prompts, night-trip protocol, auto-share with emergency contacts, SOS escalation and admin console.
E41 Cargo condition records: seal photo, loading checklist, tamper note, damage report (uses E19).
E42 KYC-ready: selfie plus liveness and document verification adapters (fakes), background-check hook, identity_index protections preserved.

PHASE 7 - MONEY (records and adapters only)
E43 Milestone payments (advance, loading, delivery) records with PaymentAdapter fake; payment hold behind legalGate.escrow; ledger consistency tests (integer paise, property tests, no double entries).
E44 Freight bill, statement and credit-note PDFs in Hindi and English; Tally and Excel export; GST and TDS calculators with CA disclaimer.
E45 Instant payout adapter, FASTag and fuel-card partner links, driver advance as a partner link-out only (legalGate.credit); no lending logic.
E46 Earnings and accounts polish: dues, ageing, reminders.

PHASE 8 - DRIVER TOOLS
E47 Fuel log and mileage, trip P&L, EMI and expense reminders, document wallet with expiry reminders (local notifications).
E48 Voice announcements for new loads and key events in Hindi and regional languages through TtsAdapter (platform TTS, chime fallback, quiet hours), and an icon-first voice-friendly Simple Mode extension.
E49 Nearby services finder (fuel, dhaba, mechanic, tyre, weighbridge) through PlacesAdapter with an admin-curated fallback list; breakdown-help partner directory managed by admin.
E50 Safety training micro-lessons (admin content), levels, streaks, badges with caps and no dark patterns.
E51 Navigation hand-off, ongoing trip notification; home-screen widget only if a safe, compatible approach exists, otherwise log and skip.

PHASE 9 - TRANSPORTER, B2B, ENTERPRISE
E52 Fleet analytics: utilisation, idle, fuel, per-vehicle P&L, maintenance schedule.
E53 Live fleet map (connect-ready), vendor scorecards, SLA reports, vendor onboarding checklist.
E54 ERP, Tally and webhook API design plus server skeleton: hashed API keys, signed webhooks, rate limits, docs/API.md, flags OFF.
E55 CO2 per trip and monthly ESG report (emission factors editable, UNVERIFIED).
E56 Team roles, approvals, cost centres, budgets and alerts polish.

PHASE 10 - COMMUNICATION AND TRACKING
E57 Chat v2: quick-reply chips, auto-translate adapter, voice notes, photo and document sharing (adapters), read receipts; contact-sharing warnings and strikes untouched.
E58 Notification center, categories, quiet hours, push topics (PushAdapter), deep links.
E59 Live tracking v2: map (connect-ready), route playback, premium share page in hosting/ with ETA, battery-aware location sampling policy.
E60 Reefer temperature and GPS device ingestion (DeviceAdapter, model, thresholds, alerts, UI; no hardware).

PHASE 11 - GROWTH AND THE BLACK TIER
E61 Loyalty tiers (Silver, Gold, Black) for customers and levels for drivers, criteria in config, benefits matrix, no money moves, abuse-safe.
E62 Referral upgrades (driver refers driver, corporate plans, gift credits) with caps and abuse checks.
E63 Load 20 Black: eligibility computed from the Trust Passport, badge, priority lane, dedicated support queue with SLA timers; insurance part stays gated.
E64 Invite and share cards, rating tags, driver badges.

PHASE 12 - SMART FEATURES
E65 OCR autofill of DL, RC and plate through OcrAdapter with user confirmation.
E66 Sahayak upgrades (more intents, SpeechAdapter hook, answers about the user's own trips).
E67 Rule-based fraud heuristics (velocity, device, bid and price anomalies) feeding risk_signals and an admin review queue.
E68 Multi-stop route ordering (offline heuristic) and a simple lane-price suggestion from admin-supplied lane data (no ML dependency).

PHASE 13 - ADMIN AND PLATFORM
E69 City-wise pricing and surge rules, commission config with audit and maker-checker.
E70 Funnels and retention analytics (event schema, aggregates, dashboards, export).
E71 Support CRM: SLA timers, macros, escalation, bulk actions on KYC and photo queues, full audit.
E72 Experiments framework (remote config), force-update, maintenance banner, announcements with read and unread.

PHASE 14 - INDIA COMPLIANCE, ACCESS, LOW DATA
E73 Overload and axle-load calculator with editable limits and "verify current rules" notice; editable permit and route info.
E74 Privacy centre: consent management, user data export, deletion cascade tests, grievance page, retention doc, data-protection checklist (not legal advice).
E75 Accessibility: TalkBack semantics on the top 20 screens, tap targets, colour-blind safe palette check, text scale 2.0, reduced motion, automated semantics tests.
E76 Low-data and low-battery mode: image quality, deferred loads, offline queue indicators, size report.
E77 Translations: all new text in 12 languages, pseudo-localisation test, RTL, tofu test, docs/TRANSLATION_REVIEW_ELITE.csv and per-language files using the existing translation tools.

PHASE 15 - HARDENING OF ALL NEW CODE (Wave 3)
E78 Rules and indexes for every new collection (compact), storage.rules for photos, rules tests, red-team matrix additions, RULES_CONTRACT flows, tool/check_indexes, tool/rules_app_drift, tool/rules_size; update RULES_CHANGES_NEEDED.md and docs/RULES_PUBLISH.md.
E79 Cloud Functions for the new server-side parts (skeletons, flags OFF): App Check monitor, schema validation, idempotency, per-user rate limits, secrets only from Secret Manager, redacted logs, unit and emulator tests.
E80 Crash-proofing: error boundaries on every new route, defensive parsing and fuzz tests for every new model, lifecycle audit, permission-denied paths for camera, mic, sensors, location, notifications, chaos tests with fakes.
E81 Performance: startup budget, scroll-jank budget per list, image cache limits, painter cost, listener counts, query shapes, micro-benchmarks with thresholds, comparison with BASELINE_ELITE.md, COST_WATCH update.
E82 Security addendum: threat model for photos, API keys, webhooks, deep links; upload abuse limits; PII-free logs; secrets scan of the full history; dependency audit.

PHASE 16 - BUG HUNT (four rounds over everything new)
Round 1 code review (null, state, permission-denied versus rules, missing index, paise errors, leaks, overflow, dark mode, RTL). Round 2 attacker mindset. Round 3 chaos mindset. Round 4 performance mindset. Every bug goes to docs/BUG_REPORT.md (id, file, issue, severity S1 to S4, fix, test). Continue until open S1 and S2 are zero.

PHASE 17 - DOCUMENTATION AND OWNER KIT
E83 Update WHERE_IS_WHAT, FLOW_SPEC, DESIGN_SYSTEM, TEST_PLAN, RELEASE_CANDIDATE, PHONE_SMOKE_SHEET (new flows, two phones, vehicle photo flow, themes), OWNER_TODO (connect steps in order), FLAGS.md (switch-on order and dependencies), KNOWN_RISKS, NOT_FREE (what is blocked and why), GAP_AUDIT (Free gaps: 0).
E84 Owner review sheets: VEHICLE_REVIEW.csv, TRANSLATION_REVIEW_ELITE.csv, COPY_DECK.md, a one-page "what to look at first" guide.

PHASE 18 - FINAL
E85 Full regression through tool/run_regression.ps1 in batches, analyze 0 issues, rules tests, red-team suite, functions tests, flutter build web --release (normal and admin) if memory allows, size report in docs/SIZE.md, tag elite-complete, push.

END: print a 12-line summary: what was built per phase, what is blocked and why, every new flag and the order to switch it on, rules that must be published, the exact owner steps to connect each paid adapter, test results, size and performance numbers against BASELINE_ELITE.md, open bugs, and what the owner must do next.
