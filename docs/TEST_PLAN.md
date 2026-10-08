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
