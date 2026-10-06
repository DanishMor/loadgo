# Task queue 2 (built on 2026-10-06 from docs/MASTER_PLAN.md, Phase 2)

Sources swept: every Partial / Todo-free / Unsure row of `docs/ROADMAP_STATUS.md` (113 rows), `docs/NEXT_TASKS.md`, `docs/BLOCKED.md`, and `grep -rn TODO lib test` (only the lawyer-review note in help_strings.dart; `TODO(functions)` and `LATER(paid)` are excluded on purpose).
Same RULES as `docs/MASTER_PLAN.md`. After each task: analyze 0, tests pass, rules tests if rules changed, PROGRESS.md, commit; push every 3 tasks.
Each row ends as **Done** (built, or free part built) or **Paid-or-Later** with the reason in its row. `python3 tool/roadmap_counts.py` recounts the summary.

**TASK 31 - Reconcile rows already built (check the code, flip the row, no new feature):** P0-02, P0-04, L4 (geohash range query exists), SM5 (planned route exists), D1/D3/D4 (online saved, nearby, route loads), B12 (driver KYC has DL), B13 (bulk, templates, book again), M16 (offline persistence, Task 27), CH10 (tickets with replies), SAFE11 (claims, Task 17), PAY4, IE11 (branches), DOC10 (rules by party, plus business roles in Task 38), BE18 (consent, deletion; data export in Task 32).

**TASK 32 - Identity, KYC, auth:** A5 (customer `businessType`: shipper, importer, exporter, trader, transporter), A9 (Profile > linked accounts: company team, fleet memberships), K6 (current and permanent address, masked), K8 (driver address + payout profile UPI id record; photo is paid), K9 (GSTIN checksum, offline), K13 (mismatch workflow: admin marks name/RC-owner/vehicle mismatch, state `needs_review`), R7 (expired licence or paper sends the profile to `needs_review` when edited), R12 (auto-check that fails -> review queue), R3 (phone change: re-auth, `phone_change` risk signal, admin review), BE18 (Download my data as JSON).
Files: lib/auth/*, lib/core/identity/*, lib/core/services/user_service.dart, admin verification screens, rules.

**TASK 33 - Customer app and booking:** C1 (search box wired to loads/bookings), C2 (Book Bike one-tap flow), C8 (nearby vehicle summary with distance estimate), B7 (instant "pickup now" flag + nearest-driver estimate), L13 (load visibility: public / favourites only / invite), P3 (recurring loads: weekly/monthly schedule, created when the app opens), P12 (booking lifecycle view created -> matched -> accepted ... -> settled, derived), M1 ("Use my location" -> nearest city), M2 (city typeahead over the 64-city table + saved places), C10/T2 (ETA to pickup card).
Files: lib/customer/*, lib/core/models/load*.dart, post_load_screen.dart, rules.

**TASK 34 - Fleet and vehicles:** V10 (fuel and toll expense entries per vehicle, monthly total), V11 (replacement vehicle: swap the booking's vehicle with audit), SM12 (breakdown -> suggest idle vehicles of the same owner), SM9 (fleet auto-allocation suggestion for open loads), SM11 (multi-stop matching by stops along the planned route), N13 (fleet analytics: utilisation, idle days, revenue, maintenance due), BIZ12 (transporter dashboard: customers served, vehicles, drivers), V12/D9 free part (document freshness badge).
Files: lib/fleet/*, lib/core/matching/*, lib/driver/*, rules.

**TASK 35 - Driver network and chat:** D11 (nearby drivers list with privacy mode), D12 (connection requests), D13 (groups), D14 (share a load card to a group), CH2 (driver-to-driver chat), CH3 (group chat), CH7 (load card inside a message), CH13 (location privacy modes: nearby only / connections / trip members / hidden), CH14 (location share expires).
Files: lib/core/network/*, lib/driver/network_*, rules (`driver_links`, `chats`, `groups`).

**TASK 36 - Trip lifecycle, alerts, evidence:** T3 (pickup geofence banner), T7 (per-stop progress and stop alerts), N2 (driver arriving ETA alert), N10 (chat notification), SAFE2 (share trip summary text with emergency contacts), S15 (audit events for every evidence write), DOC14 (document view log), F10/F11 (delivery GPS vs drop city mismatch signal), T2 (arriving ETA, with C10).
Files: lib/core/trip/*, lib/core/reminders/*, lib/core/notifications/*, rules.

**TASK 37 - Payments and documents (records only):** P0-06 + PAY1 (UPI payment link `upi://pay` from the driver's payout UPI id), PAY3 (advance payment record, balance on delivery), DOC4 (e-way bill validity date check and warning), IE10 (leg 1 -> leg 2 controlled handover, both drivers confirm), TEST6 (duplicate-transaction and double-confirm tests), PAY6 free part (cancellation charge shown before cancel).
Files: lib/core/payments/*, lib/core/documents/*, rules.

**TASK 38 - Business account roles:** A4, BIZ4, BIZ5 (roles manager, dispatch, accounts, viewer with a permission table), BIZ6 (approval workflow for bookings over a limit), BIZ8 (contract vehicles record), BIZ9 (approved driver pool), BIZ10 (expense dashboard: spend by month, fuel, toll entries), BIZ15 (business support queue), DOC10 (enterprise roles in rules).
Files: lib/customer/business_*, lib/core/enterprise/*, rules.

**TASK 39 - Anti-fraud, roles, quality:** F1 (possible duplicate accounts: name + shared devices), F3 (RC owner vs vehicle owner anomaly), F5 (many devices in 24 h signal), F7 (behavioural score: profile changes, booking bursts), F14 free part (admin bulk hold of high-score users), BE7 (admin staff roles: support, verifier, ops, with rules), BE13 (risk rule thresholds in config), TEST5 (GPS loss and low-network tests), TEST9 (automated language QA: placeholders, scripts, empty strings), TEST6 leftovers.
Files: lib/core/risk/*, lib/admin/*, firestore.rules, test/*.

**TASK 40 - Paid/Later classification:** every row whose remaining part needs Functions, Storage, Maps, a gateway, a KYC/GSTN provider, telephony or a partner becomes **Paid-or-Later** with the reason and the free part that was built; A2 and BE5 (manual Console setup) likewise. Rewrite `docs/NEXT_TASKS.md` with only paid items and their cost reason, update `docs/BLOCKED.md`.
Rows: P0-03, P0-05, K3, V12, L8, P11, M2 (pin/geocoding), M7, M8, M10, C10 (map), C12, C14, B11, D9, DOC4, DOC5, DOC8, DOC12, S14, T14, PAY6, PAY14, IE7, F14, F16, BE11, BE12, BE14, CH12, TEST6, A2, BE5.
