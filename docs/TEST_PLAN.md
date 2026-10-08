# LoadGo manual test plan

Run on a debug build with demo data (Admin > Demo data > Create) or two real test phones.
Tick every line on a real Android phone before a release. Test in English and one Indian language, light and dark.

## Customer
- [ ] First launch: 3 intro slides, role screen, OTP login (resend after 60 s, wrong code message).
- [ ] Profile: name, optional company and GST (bad GST refused).
- [ ] Post a load: pickup/drop picker, vehicle type, weight over capacity refused, fare estimate and breakdown, prohibited goods refused.
- [ ] Post with promo code, credits, helpers, exact pickup time, declared value (only when the offers switches are on).
- [ ] Offers: see driver prices, counter once, select one; booking appears after the driver confirms.
- [ ] Trip: OTPs shown, status timeline, ETA card, chat, share trip, call driver only after accept.
- [ ] Cancel with a reason; cancel an advance booking (free window vs charge).
- [ ] After delivery: pay (UPI link / cash mark), rate (3 category rows), tip, invoice PDF, raise a claim.
- [ ] Spending screen, trip history filters, CSV share, global search, Sahayak questions.
- [ ] Settings: language, theme, notification switches, consents, delete account (blocked with an active trip).

## Driver
- [ ] Login as driver; role lock (a customer number is refused), KYC documents, location consent, pending verification screen.
- [ ] After admin approval: add vehicle (duplicate number refused), documents with expiry.
- [ ] Loads tab: nearest first, recommended, filters, saved search, favourite route star, open a shared link.
- [ ] Make an offer (Simple Mode stepper and mic), accept a load, confirm a selected offer.
- [ ] Trip: arriving banner, pickup OTP + proof, in transit, drop OTP + proof, navigate buttons, SOS, breakdown.
- [ ] Wallet, earnings today / 7 days, payout request, tips, incentives, plan request.
- [ ] Empty truck post, driver network (nearby, connections, groups).
- [ ] Simple Mode: four big buttons, money screen.

## Bilty (LR)
- [ ] Transporter: Trips > LR > Create LR, fill the form, number looks like TR-2026-000001; a second LR gets 000002.
- [ ] Customer on own booking: Create LR gives CS-... with the title "Consignor LR / booking slip"; the driver and an admin never see a Create button.
- [ ] Send screen: switch Driver / Consignee / Full; the preview changes; Driver copy has no rate, margin or phone; Consignee copy shows the rate only with the switch on.
- [ ] Send to the driver in app: the assigned driver gets a notice and "LR (driver copy)" on the trip screen with the label "Rate hidden by owner".
- [ ] Share PDF opens the share sheet (WhatsApp); open it: Hindi text has no boxes, the QR code opens /lr/<token> with only LR number, route, status, issuer.
- [ ] Create a link, open it in a browser (shows only that copy), revoke it (page says the link has ended); view count goes up.
- [ ] Edit: a new version, same number; the old one is listed under Versions as view only. Cancel needs a reason; the verify link then says CANCELLED.
- [ ] E-way bill field is a record only (note under the field).

## Bilty inspection mode (RTO / GST)
- [ ] Default mode is Hide: the driver copy shows no goods value, invoice, GSTIN or e-way bill, the labels say "Rate hidden by owner" and "Owner approval needed for inspection". The rate, margin and phones never show to the driver in any mode.
- [ ] Owner changes the mode on the LR card (Hide / Show / Only when an inspection is asked): no new version; the change is in Admin > Audit log (lr_mode).
- [ ] Driver taps "Show inspection": the owner gets a request in the notification bell (and on the LR card); Approve gives the driver the details for 2 hours ("Inspection allowed until HH:MM"); Deny shows "The owner did not allow it".
- [ ] After 2 hours the driver screen goes back to hidden, the saved inspection copy is gone, and `inspection_expire` is in the audit log once.
- [ ] Owner: "Show for this trip" (mode Show) and "Allow inspection for the next N hours" before the trip; the driver saves the inspection copy, switches the phone to flight mode, and "Show saved inspection copy" still opens it (watermark, LR no, QR, date and time, driver name, no rate).
- [ ] Another driver, or a driver after expiry, cannot read the details (rules tests cover this).

## Fleet owner
- [ ] Login through the fleet door, profile (PAN), invite a driver by phone, driver accepts.
- [ ] Add vehicle, assign driver, dashboard figures, expenses, analytics.

## Business account (customer with company)
- [ ] Invite a booker, role change, approval limit (load waits for approval), statements by cost centre.

## Admin
- [ ] Admin tile only for allowlisted uid (live: remove admins/{uid} and the open panel closes); purple "Admin mode" banner on every admin screen; customer, driver, transporter never see the tile, the text or the screens; staff roles hide tiles (support, ops, verifier).
- [ ] Verification queue, users (suspend, ban, restore, bulk hold with reason), CSV exports masked.
- [ ] Tickets with reply templates, SOS, reports, claims, fraud cases, payouts, feedback, assistant questions.
- [ ] Config JSON editors, offers switches, app control (force update, maintenance).
- [ ] System health counts and sampled errors; Demo data create / remove (release build blocked without `config/app.allowDemo`).

## Release checks
- [ ] `flutter analyze` 0 issues, `flutter test` green, `cd firestore_rules_test && npm test` green.
- [ ] Demo data removed from the live project (count 0).
- [ ] Rules and indexes deployed by the owner (see docs/MANUAL_TODO.md).

## Automated coverage (MASTER-5 Phase B round 2)
What the ticks above already have as test code, so a release check only needs the parts that need a real phone (OTP SMS, WhatsApp / UPI hand-over, camera, GPS, calls on two networks, push, the PDF look on paper). `test/test_plan_map_test.dart` fails if a file named here disappears.

| Area | Flows | Test files |
|---|---|---|
| Customer | post load, fare, offers, counter, select, booking, OTPs, ETA, chat, share trip | `test/load_post_test.dart`, `test/load_posting_upgrade_test.dart`, `test/pricing_test.dart`, `test/offers_test.dart`, `test/booking_flow_test.dart`, `test/trip_eta_test.dart`, `test/chat_test.dart`, `test/share_test.dart` |
| Customer | cancel (reason, charge, advance booking), pay, rate, tip, invoice, claim | `test/load_cancel_test.dart`, `test/schedule_test.dart`, `test/payments_test.dart`, `test/rating_test.dart`, `test/rating_categories_test.dart`, `test/driver_extras_test.dart`, `test/invoice_series_test.dart`, `test/claim_test.dart`, `test/trip_evidence_test.dart` |
| Customer | promo, credits, referral (also with the switches OFF), spending, history, search, settings, deletion | `test/rewards_test.dart`, `test/offers_off_test.dart`, `test/customer_history_test.dart`, `test/advanced_search_test.dart`, `test/analytics_settings_test.dart`, `test/help_deletion_test.dart`, `test/e2e/deletion_roles_e2e_test.dart` |
| Driver | role lock, KYC, identity, documents and expiry, vehicles | `test/role_lock_test.dart`, `test/identity_test.dart`, `test/auth_fixes_test.dart`, `test/doc_expiry_test.dart`, `test/vehicle_documents_test.dart`, `test/add_vehicle_screen_test.dart`, `test/vehicle_service_test.dart` |
| Driver | loads, ranking, filters, accept, offers, trip, cancel, wallet, payout, earnings, tips, incentives | `test/matching_test.dart`, `test/load_filter_test.dart`, `test/accept_load_test.dart`, `test/booking_flow_test.dart`, `test/driver_cancel_test.dart`, `test/earnings_test.dart`, `test/earnings_statement_test.dart`, `test/e2e_flow_test.dart` |
| Driver | empty truck board, driver network, Simple Mode | `test/truck_board_test.dart`, `test/task35_test.dart`, `test/task46_test.dart`, `test/task57_test.dart` |
| Whole trip | customer to driver, bid, trip, delivery, rating, tip and payment | `test/e2e_flow_test.dart` |
| Bilty and inspection | numbered LR, copies, versions, share links, verify page, inspection requests, grants, expiry, offline copy | `test/bilty_test.dart`, `test/bilty_layout_test.dart`, `test/inspection_test.dart`, `test/e2e/bilty_e2e_test.dart`, `test/e2e/inspection_e2e_test.dart`, `test/pure_logic_matrix_test.dart` |
| Transporter | company profile, loads, assign, trips, books, party statements | `test/task67_test.dart`, `test/party_statement_test.dart`, `test/fleet_test.dart`, `test/e2e/transporter_private_chat_e2e_test.dart` |
| Chat and call | numbers hidden, contact filter, strike ladder, blocks, calls | `test/contact_filter_test.dart`, `test/task68_test.dart`, `test/pure_logic_matrix_test.dart`, `test/e2e/transporter_private_chat_e2e_test.dart` |
| Business account | invites, roles, approval limit, statements | `test/business_team_test.dart`, `test/enterprise_test.dart`, `test/task38_test.dart` |
| Admin | lock and banner, verification, users, lists, exports, funnel, announcement, moderation, audit of every write | `test/admin_lock_test.dart`, `test/admin_verification_test.dart`, `test/admin_user_test.dart`, `test/admin_console_test.dart`, `test/admin_list_tools_test.dart`, `test/pilot_funnel_test.dart`, `test/announcement_test.dart`, `test/rating_moderation_test.dart`, `test/admin_audit_test.dart` |
| Rules | every collection, every role | `firestore_rules_test/rules.test.mjs`, `firestore_rules_test/matrix.test.mjs`, `test/rules_audit_test.dart` |
| Quality | layout of all screens, 12 languages, right-to-left, accessibility, states, listeners, indexes, old documents | `test/layout_all_screens_test.dart`, `test/language_qa_test.dart`, `test/translations_test.dart`, `test/rtl_test.dart`, `test/accessibility_test.dart`, `test/state_audit_test.dart`, `test/listener_audit_test.dart`, `test/index_audit_test.dart`, `test/model_fuzz_test.dart` |
