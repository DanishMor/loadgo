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
