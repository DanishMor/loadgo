# Decisions (MASTER-5)

One line per assumption taken without asking.

- 2026-10-08 `.claude/` is git-ignored, so the project permissions in `.claude/settings.json` stay local to the Codespace and are not committed.
- 2026-10-08 Rules audit (Task 1) is a static Dart test plus the existing emulator tests; the full field-level review stays in docs/SECURITY_REVIEW.md.
- Privacy / Terms (Task 8): docs and public pages mention the automatic clean-up, the LR-link switch-off on deletion and the hourly limits; the in-app policy stays the five short clauses (generic, no new 12-language text).
- Tasks 45 and 46 (e2e): test/e2e/bilty_e2e_test.dart, inspection_e2e_test.dart and transporter_private_chat_e2e_test.dart (Tasks 66-71) already walk transporter + bilty + inspection and chat block + strike ladder + call block from the booking to the admin; I kept them as the e2e for these tasks and added test/e2e/deletion_roles_e2e_test.dart (Task 47) instead of writing duplicates.
- Task 31: the Post Load wizard is three numbered steps on one scrolling page, not three separate screens, so every field stays in the tree and existing flows and tests keep working.
- Task 20: the phone clock is corrected with a server time learned from a chat message the phone sent; the rules themselves always use the server time. A person who never chats keeps the phone clock for screens (documented in Task 20 progress).
- Task 38: admin lists page the 100 documents read, 50 at a time, on the client; real server paging would need a cursor per list and a composite index.
- Task 20 (update): the learning source for `ServerClock` is the device record (`users/{uid}/devices/{id}.lastSeenAt` is stamped by the server and read back) at sign-in and at most every six hours, plus chat acknowledgements. It is not saved between runs: an old offset would be wrong after the person fixes the phone clock.
- M6-36: trust badges are shown to the driver only; customer-facing needs server summary (TODO(functions)).
- M6-43: R8 minify/shrink turned on for release; unverified because the Android SDK is missing here (see BLOCKED.md).
- 2026-10-11 P1: rename_app.ps1 takes -DryRun as a string (default true; apply with -DryRun false) because powershell -File cannot pass a real boolean; it reuses tool/apply_app_info.dart instead of a second generator.
- 2026-10-14 MASTER_PLAN_FINAL.md was pasted cut off after "key actions par haptics," (L15-L18). Assumption: L15-L18 = splash, role select, login/OTP and first-time tutorial polish with micro-animations and haptics; phases after Phase 4 (server features / functions) are not in the pasted text and are not started until the owner pastes them.
- 2026-10-14 L1: the English tagline slot holds the Hinglish line "Maal bhejo, bharosa ke saath" (as the owner gave it); the other 10 scripts carry translations I wrote, to be checked by a native reader. Name in other scripts is a transliteration plus "20".
- 2026-10-14 WALLET_PLAN.md saved. Order: finish MASTER Phase 5 (security) first; WL7 server parts go with L27/L28. The pasted MASTER text stops inside L15-L18, so Phase 5 and L27/L28 are not in the repo yet; the wallet phase starts only after the owner pastes those or says to go ahead. Existing wallet pieces to upgrade, not duplicate: lib/driver/wallet_screen.dart, lib/core/models/ledger_entry.dart, lib/core/payments/*, payout/tips/incentives/credits code, staff roles (BE7), admin banner, FLAG_SECURE, Redactor, lib/core/adapters.

- 2026-10-15 F2: the trip code limit changes firestore.rules for pickup/delivery, so rules and app must be deployed together; an older app build cannot pick up or deliver after the new rules are deployed (it does not store a guess first). ASSUMPTION: acceptable before launch; no feature flag because rules cannot read a flag cheaply and the old behaviour was the weaker one.

- 2026-10-15 F4: new flags that guard server or security work (secureScreens now; wallet, push, photos later) are declared FeatureSpec(pilotOn: false, normalOn: false) so they stay OFF also when pilot mode is switched off. test/task60_test.dart "pilot mode off: every feature starts on" now expects each flag to equal its own normalOn (all older flags are normalOn: true, so nothing is weakened for them).
- 2026-10-15 F7: WalletEntry (not LedgerEntry) for the pure money line, adapter fromLedger; existing collection payouts is extended (approved, reversed) instead of adding payout_requests. Label stays "Kamai aur hisaab"; the word "wallet" is a decision for the lawyer (WALLET_LEGAL.md in F13).
- 2026-10-15 F10: ledger stays one query by driverId with a client sort (no new index); the hub limits what it draws. A paged ledger needs a composite index (driverId, createdAt desc): recorded for the owner, not deployed.

- 2026-10-16 Server switches (F15): they live in config/features.flags like every other switch (the plan says so) and are registered in the app (Features.registry) so a save from Admin > Features never drops them. Functions read the same document, only an explicit true counts, cached 30 seconds.
- 2026-10-16 F22: the admin sets a deletion request to "approved" (new status in the rules) and the server then does the deletion and sets "done"; "done" by hand stays for the old manual way. An open payout or an admin account blocks the deletion and puts the request back to pending with blockedReason.
- 2026-10-16 F19: public_trust/{uid} allows get only (not list) so nobody can read all drivers at once; the matrix test pins the list of collections that can be listed.
- 2026-10-16 F21/F23/F27 client: cloud_functions added. ServerActions calls the function only when its switch is ON; if the function is missing or the network is down the app does the old direct write; a real refusal (permission-denied) is shown and never hidden by a fallback.
- 2026-10-16 Push texts (F25): a push shows a short fixed title in the person's language and never the content of a message; chat pushes say "New message". Android channel names are in res/values-*/push_channels.xml for the 11 Android locales (Hinglish uses the English names).
- 2026-10-16 Photos: no download links (getData with sign-in only) so a leaked URL never opens a paper; truck views have fixed file names (front/side/rear/load); queue keeps max 10 photos and only on phones (web has no file path).
- 2026-10-16 Admin web: firebase.json is not changed for the second hosting site (an unmapped target would stop today's deploy); the owner adds it with the steps in docs/ADMIN_WEB.md. serverStatus has no switch on purpose: it is how to test a fresh deploy.
- 2026-10-16 Payment: the app sends only the booking id; the server takes the amount from the booking so a changed phone cannot pay less. Refund needs finance or super staff and never exceeds what was paid. KYC/SMS partner skeletons come before any contract; they never block the manual path.
- G4: owner bug list in the master plan is empty, so nothing to fix (2026-10-16).
- G6: the deploy state is a second table in ROADMAP_STATUS.md, not a new column on 1,000 rows, so roadmap_counts.py keeps working (2026-10-16).
- G8: no analytics without the person's analytics consent (it was ignored before); funnel steps are not used up while consent is off (2026-10-16).
- G12: login OTP via MSG91 custom token is documented only (risks in OTP_SECURITY.md), not built; recommended to keep Firebase (2026-10-16).
- G14: invoice shows reverse charge 'No' and IGST when seller and place of supply differ; both need CA confirmation (docs/GST_EWAY.md) (2026-10-16).
- G18: audit showed most planned features already exist; Phase 4 builds only the real gaps (trust card, route rates, payment hold, safety check-in, khata, business card) (2026-10-17).
- U5-U9: the system alert sound is used for the incoming-load sound (no audio plugin or asset added, keeps the app small); quiet hours default 22:00-06:00 and Low-end mode mutes it.
- U15: no new no-show cancel code (the cancel-reason lists are pinned by tests): a no-show is the existing reasons `customer_unreachable` (driver cancels) and `driver_delay` (customer cancels); the admin dispatch monitor (U17) counts them. A per-load cap on the number of bids is not in the rules (they cannot count documents); the hourly bid limit (rate_limits) and one bid per driver per load already bound it.
- U12/U14: bid-mode accept is two steps as before (customer selects, driver confirms) so the driver stays in control of their truck; the auto-accept rule does the selecting, the driver app shows "customer chose you, confirm".
- U10/U11: the wave layer in the app is a visibility filter only (docs/FLOW_SPEC.md); the server wave and push come after the functions deploy.
- U28: skip reasons are shown but not stored (no server field for them); back on the card counts as Skip.
- Z2: LR register queries (lrs by issuerId, lr_shares by ownerId) match rules and need no composite index; kept the customer/fleet-owner list clauses in rules but the app lists only by issuer. Share-link query is now non-blocking. Likely live cause: rules/indexes not published.
- Z1: Diagnose probes use the same service streams as the screens (first event, 6 s timeout); limit 1 is not forced because the services own their limits. Server time difference is not measured (no free read gives it, the screen never writes). Device model shows the platform name only (no new plugin).
- Z9: skipped, rules would have to let an admin write documents under another user's id; written in docs/BLOCKED.md.
- Z22: web release builds not run: free memory was 4.4 GB, rule says 5 GB.
- E3 (2026-10-29): legal gate flags are camelCase keys (legalGateEscrow, not legalGate.escrow), because a dot would split the Firestore field path in config/features.flags.
- E3: Elite flags are added to Features.registry only when their feature is finished; until then they are 'planned' in docs/FLAGS.md and a test blocks registering them, so no half-built screen is reachable. Kill-switch groups get Elite keys as each flag goes live.
- E2: firestore.rules comments were moved to docs/firestore.rules.annotated.txt (not deployed) to get 43 KB of room; no rule text changed.
