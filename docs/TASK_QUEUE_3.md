# Task queue 3 (built 2026-10-06 from docs/MASTER_PLAN_2.md, Phase 2)

Source: `docs/GAP_AUDIT.md` (FREE gaps only). Same RULES as MASTER_PLAN_2. After each task: analyze 0, tests pass, rules tests if rules changed, PROGRESS.md, commit; push every 3 tasks. Rules/indexes are never deployed by the run. Status is `[ ]` open / `[x]` done.

**TASK 41 - Cost control and offers switch (G5.1, G5.2, G6.1-G6.4):**
1. `OffersSwitch` model for `config/offers` (`promoEnabled`, `creditsEnabled`, `referralEnabled`), all default OFF when the doc or field is missing.
2. App: hide promo field, credits line, referral screen/entry when the switch is off (customer post-load and offers screen).
3. Rules: promo on a load, `creditsUsedPaise > 0`, credit `spend`/`referral` lines and `referrals` create need the switch ON.
4. Admin offers screen: three switches, saved to `config/offers` (super admin).
5. Rules tests for switch on/off for promo, credits, referral.
6. Reminder tick 1 min -> 5 min and emit only when the computed list changed.
7. Nearby streams: cap cells at 4 (precision tuned to radius) and debounce origin changes.
8. TTL cache helper (`TtlCache`) for config reads; `refreshAppConfig` skips when fresh (15 min).
9. Page size limits on `watchMine`/`watchOpen` (limit 100) so no listener is unbounded.
10. Tests for each.

**TASK 42 - Crashlytics, Analytics, Remote Config, app control (G4.1-G4.5, G5.6):**
1. Add `firebase_crashlytics`, `firebase_analytics`, `firebase_remote_config`, `package_info_plus` and the Android gradle plugin.
2. `CrashService.init` wiring `FlutterError.onError` and `PlatformDispatcher.onError`; a no-op when Firebase is unavailable.
3. `AnalyticsEvents` wrapper (screen/event names, never personal data), safe in tests.
4. `AppControl` model: `minVersionCode`, `maintenance`, `maintenanceMessage`, feature flags map; parsed from Remote Config with `config/app` Firestore fallback.
5. Pure `VersionGate` (compare current vs minimum).
6. Force-update screen and maintenance screen (12 languages), shown from the app shell.
7. `FeatureFlags.isOn(name)` with safe defaults.
8. Remote Config defaults documented; fetch interval 1 h.
9. Rules for `config/app` already covered by `config/{docId}`; test added.
10. `docs/FIREBASE_SETUP_2.md`: google-services, Crashlytics, Analytics, Remote Config steps.
11. Tests for version gate, flags, control parsing.

**TASK 43 - Share, call and navigation (G1.1, G1.2, G2.5, G3.2, G3.3):**
1. Add `share_plus`.
2. `ShareLinks`: load deep link `https://loadgo-defc2.web.app/load/{id}` (host configurable), plus parse of the id.
3. Share button on load card / load detail using share_plus (link + text).
4. WhatsApp share via `https://wa.me/?text=` with url_launcher.
5. Phone visibility rule (`PhoneVisibility.canShow(status)`): driver/customer phone only after the booking is confirmed (`accepted` onwards).
6. Tap-to-call buttons on booking cards using that rule.
7. Hide raw phone in `booking_widgets` until confirmed.
8. `NavLinks`: Google Maps directions URL (`https://www.google.com/maps/dir/?api=1&destination=...`), no API key.
9. Navigate buttons for pickup and drop on the driver trip screen.
10. Android manifest `queries` for `https`, `tel`, `whatsapp`, `geo`.
11. Tests for links, parse, phone rule.

**TASK 44 - Surge config (G2.8, G3.1):**
1. `SurgeRule` model: peak hours, night hours, festival date ranges, percent each, cap percent.
2. Stored in `config/pricing` under `surge` (admin).
3. Pure `SurgeCalculator.percentAt(DateTime, config)`.
4. Fare calculator applies surge to the base freight, shown as its own breakdown line.
5. Money stays integer paise (round half up).
6. Admin config UI fields for the three windows and cap.
7. Default OFF (`enabled: false`).
8. Fare breakdown widget shows "Peak/Night/Festival" label (12 languages).
9. Tests: boundaries, midnight wrap, cap, off.

**TASK 45 - Offline toll, fuel, trip cost (G1.3, G2.6, G3.4):**
1. `TollTable`: per-km toll rate per vehicle category + city-pair fixed values for the top corridors (estimate).
2. `FuelEstimate`: km, mileage per category, diesel price in config (default marked as estimate).
3. `TripCostPreview` combining fare + toll + fuel, all paise.
4. Labels "estimate" on every line.
5. Customer post-load preview card.
6. Driver bid sheet shows toll + fuel + net margin.
7. Admin can edit diesel price in `config/pricing`.
8. Toll table clamps for unknown routes (falls back to per-km).
9. 12-language strings.
10. Tests.

**TASK 46 - Driver Simple Mode and voice (G2.1, G2.2, G2.7):**
1. Add `speech_to_text`; Android `RECORD_AUDIO` permission and `queries` for speech.
2. `SimpleMode` setting (shared_preferences), toggle in settings and on first driver start.
3. Simple home: four large buttons (Find loads, My trips, Money, Help) with icons.
4. Simple bid form: big amount stepper, one confirm button.
5. `VoiceParser`: pure parse of Hindi/English spoken numbers and cities ("पाँच हज़ार", "ten thousand", "Delhi se Jaipur").
6. Mic button on load search and on the bid amount.
7. Permission denied / unavailable fallback message.
8. "Money" simple line: balance and what can be requested.
9. Simple Mode keeps 12 languages and max 3 words per button label.
10. Tests for parser and mode persistence.

**TASK 47 - LoadGo Sahayak engine (G1.7, G3.5):**
1. `AssistantEngine` interface (`// LATER(paid): LLM engine`).
2. `RuleEngine`: tokenise, normalise Hinglish/Hindi/English, keyword intents with scores.
3. Intents: my booking, post load (pre-fill from/to/vehicle), nearby loads, OTP FAQ, bid FAQ, payment FAQ, cancel FAQ, support ticket, greeting, unknown.
4. Entity extraction: cities from offline table, weight, vehicle words.
5. `AssistantReply` (text key, action, prefill map).
6. Answer text in 12 languages (+ Hinglish keywords).
7. Confidence threshold and "did not understand" reply.
8. Unknown question collector (pure) for logging.
9. Tests for each intent and each language keyword set.

**TASK 48 - Sahayak UI and admin log (G1.7, G5.6):**
1. Chat-style screen in `core/assistant`, used by both apps.
2. Entry button on customer and driver home.
3. Action chips: open my bookings, open post-load with pre-filled values, open nearby loads, open ticket form.
4. `assistant_unknown/{id}` collection: text (max 300), userId, role, language, createdAt.
5. Rules + rules tests (create own, no read except admin, no update/delete).
6. Rate limit by short timestamp guard (client) and size limit (rules).
7. Admin screen listing unknown questions with a "resolved" flag.
8. Strip numbers/phones from logged text.
9. Widget test for the screen.

**TASK 49 - Earnings, history, spending (G1.6, G2.3, G2.4, G3.6):**
1. `EarningsSummary` pure: daily and weekly buckets from delivered bookings (paise).
2. Driver earnings view: today, this week, last 7 days bars (simple widgets).
3. Trip history filters: status, date range, vehicle.
4. `SpendingSummary` for the customer: month totals, by cargo, by route.
5. Customer spending screen.
6. Filter chips reuse `LoadFilter` style.
7. Empty states.
8. CSV share of history using share_plus.
9. 12-language strings.
10. Tests.

**TASK 50 - Cancel reasons, value, feedback, rating reminder (G1.4, G1.5, G1.9, G1.10):**
1. Cancel reason list (customer and driver), saved as `cancelReason` code.
2. Rules allow `cancelReason` (enum) with cancel.
3. Goods value declaration (`declaredValuePaise`, optional) on load post.
4. Rules validate it (int, 0..10 crore paise).
5. Claim screen shows the declared value.
6. `feedback/{id}` collection: rating 1-5, category, text, app version.
7. Rules + tests for feedback (own create, admin read).
8. Feedback form screen in Help.
9. Rating reminder as a reminder kind (delivered, not rated after 24 h).
10. 12-language strings.
11. Tests.

**TASK 51 - App-wide search (G1.8):**
1. `GlobalSearch` pure index over loads, bookings, tickets, saved places, cities, help topics.
2. Ranking: exact, prefix, contains.
3. Search screen with sections.
4. Entry in both app bars.
5. Recent searches (shared_preferences).
6. Debounce.
7. Tapping opens the right screen via `AppRoutes`.
8. Open-by-id for shared load links.
9. Empty and no-result states.
10. Tests.

**TASK 52 - Admin tools (G4.9, G4.10):**
1. Support reply templates (`config/reply_templates`) editable by super admin.
2. Template picker in the ticket reply box.
3. Bulk actions on user list: hold, unhold, set status with audit.
4. User export CSV (masked sensitive fields).
5. Booking export CSV.
6. System health screen: counts (users, loads, bookings, open tickets, pending deletion), recent errors.
7. Client error log `app_errors/{id}` (message, screen, version, createdAt; no personal data).
8. Rules + tests for `app_errors`.
9. Hook crash service to also write sampled errors there.
10. 12-language strings.
11. Tests.

**TASK 53 - Demo data and test plan (G4.11):**
1. `DemoSeed` generator (pure data builders): users, vehicles, loads, bookings; all tagged `demo: true`.
2. Admin-only screen to create and remove demo data.
3. Rules: `demo: true` docs only creatable by admins.
4. Guard: refuse in release unless `config/app.allowDemo`.
5. Delete-all demo query with batches.
6. `docs/TEST_PLAN.md`: customer, driver, fleet, admin checklists.
7. Tests for builders and guard.

**TASK 54 - Play Store pack and docs (G7.1-G7.6):**
1. Android label `LoadGo`.
2. Permission rationale dialogs (location, notifications, microphone) in 12 languages.
3. `docs/PLAY_STORE_CHECKLIST.md`.
4. `docs/PRIVACY_POLICY.md`.
5. `docs/TERMS.md`.
6. Firebase Hosting steps and a `hosting/` folder with public policy and account-deletion pages.
7. `firebase.json` hosting entry (not deployed).
8. Data safety answers in the checklist.
9. Policy/terms public URL setting shown in the app.
10. `docs/PAID_UPGRADE_PLAN.md`.
11. Tests for the policy URL helper.

**TASK 55 - Errors, empty states, slow network (G4.6-G4.8):**
1. `FriendlyError.of(error)` maps FirebaseException codes and timeouts to translated keys.
2. Use it in the shared error widget.
3. `EmptyState` widget (icon + text + action).
4. Use it in lists without one.
5. `withRetry` helper (timeout + backoff) for one-shot reads.
6. Slow-network banner state when the first snapshot takes > 8 s.
7. 12-language strings.
8. Tests.

**TASK 56 - Abuse guards (G5.3-G5.5):**
1. Chat: reject the same message text twice in a row (client).
2. Rules: chat message size and no empty text (verify and extend).
3. Bids: client check amount within 30%..300% of the estimate with a clear message.
4. Rules: offer amount bounds against the load estimate.
5. Rating burst: admin screen lists users with 5+ one-star ratings given in 24 h.
6. Tests for each.

**TASK 57 - Quality sweep (G8.1-G8.4):**
1. Language QA test extended to all new tables (12 entries, no empty, placeholders match).
2. Layout test of new screens at 360 px and 1.3x text.
3. Dark mode smoke test of new screens.
4. Convert large `ListView(children:)` of unbounded data to builders where found.
5. Structure test still passes.
6. Docs final counts.

## Pilot add-on (Tasks 60-66, from docs/ADDON_PILOT.md)
**TASK 60 - config/features, pilot mode:** `Features` model (pilot defaults), `FeaturesService` (15 min cache), `FeatureGate`, gates on driver network, empty trucks, business tools, rental and movers, driver rewards, trip share, problem report; Admin > Features. **TASK 61 - supply and demand screen** (admin, super and ops). **TASK 62 - unit economics screen** (admin, super; costs in `config/economics`). **TASK 63 - driver payment timeline** on the trip screen. **TASK 64 - trip share link** (`trip_shares`, public page `/trip/{token}`). **TASK 65 - problem report** (becomes a support ticket). **TASK 66 - docs:** ADDON_PILOT, LAUNCH_RISKS, COST_WATCH.
