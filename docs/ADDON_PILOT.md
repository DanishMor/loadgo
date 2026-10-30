# Pilot plan (add-on to the master plan)

Goal: put LoadGo in front of a small, known group (one or two corridors, tens of drivers, tens of customers) and learn, without opening every feature. Everything below is controlled from **Admin > Features and pilot mode** (`config/features`) and **Admin > Offers** (`config/offers`); no new app build is needed to change it. Phones pick a change up within 15 minutes.

## What is ON and OFF by default (pilot mode on, document missing)
| Part | Pilot default | Where it is switched |
|---|---|---|
| Freight posting, price offers, booking, OTP trip steps, proofs, LR/POD, chat, ratings, support tickets, SOS, reminders, Sahayak, search, earnings, wallet records | ON | always on |
| Trip share link (`trip_shares`) | ON | Features > Trip share link |
| Report a problem | ON | Features > Report a problem |
| Transporter accounts | ON | Features > Transporter accounts |
| Bilty (LR) | ON | Features > Bilty (LR) |
| Block screenshots on private screens | OFF | Features > Block screenshots on private screens |
| Earnings and accounts hub | OFF | Features > Earnings and accounts hub |
| Two admins for payouts | OFF | Features > Two admins for payouts |
| Fresh code before payouts | OFF | Features > Fresh code before payouts |
| Payout limits and waiting time | OFF | Features > Payout limits and waiting time |
| Fingerprint lock for earnings | OFF | Features > Fingerprint lock for earnings |
| Server hourly limits | OFF | Features > Server hourly limits |
| Server chat check | OFF | Features > Server chat check |
| Server credits and referral | OFF | Features > Server credits and referral |
| Server trip counts | OFF | Features > Server trip counts |
| Server timed jobs | OFF | Features > Server timed jobs |
| Server admin actions | OFF | Features > Server admin actions |
| Server account deletion | OFF | Features > Server account deletion |
| Server earnings checks | OFF | Features > Server earnings checks |
| Online payment (test mode) | OFF | Features > Online payment (test mode) |
| Push notifications | OFF | Features > Push notifications |
| Admin announcements by push | OFF | Features > Admin announcements by push |
| Photo uploads | OFF | Features > Photo uploads |
| Nearby-first dispatch and bidding | OFF | Features > Nearby-first dispatch and bidding |
| New look and booking steps | ON | Features > New look and booking steps |
| Signature look | ON | Features > Signature look (OFF shows Classic to everyone) |
| Business card to share | OFF | Features > Business card to share |
| Party khata | OFF | Features > Party khata |
| Safety check-in on a long stop | OFF | Features > Safety check-in on a long stop |
| Hold online payment until delivery | OFF | Features > Hold online payment until delivery |
| Usual price on a route | OFF | Features > Usual price on a route |
| Driver trust on offers and trips | OFF | Features > Driver trust on offers and trips |
| Refuse calls from unknown apps | OFF | Features > Refuse calls from unknown apps |
| ID checks (licence, RC, PAN, GST) | OFF | Features > ID checks (licence, RC, PAN, GST) |
| SMS messages | OFF | Features > SMS messages |
| Live trip location | OFF | Features > Live trip location |
| Maps and road distance | OFF | Features > Maps and road distance |
| Promo codes, credits, referral | OFF | Offers (three switches, default OFF) |
| Surge pricing | OFF | `config/pricing.surge.enabled` |
| Driver network and groups | OFF | Features |
| Empty trucks board (both apps) | OFF | Features |
| Business tools (company team, statements, approvals) | OFF | Features |
| Hourly rental and packers and movers | OFF (freight only) | Features |
| Driver tips, bonuses and plans | OFF | Features |
| Demo data in a release build | OFF | `config/app.allowDemo` |
Fleet owner login stays visible on the role screen (it is shown before sign-in, when `config/*` cannot be read). Do not invite fleet owners during the pilot unless you want them.

Turn pilot mode off to start every feature on its normal default (everything on), or set one feature to On/Off by hand: the explicit choice always wins.

## Before the first real user
1. Deploy rules and indexes (done by the owner), then hosting (`firebase deploy --only hosting`) for the policy pages, `/load/**` and `/trip/**`.
2. Make yourself admin (docs/MANUAL_TODO.md), open Admin > Pricing and Vehicle types and press Save once.
3. Fill the support phone/e-mail placeholders in `hosting/*.html` and `docs/PRIVACY_POLICY.md`.
4. Set budget alerts (docs/COST_WATCH.md) and read docs/LAUNCH_RISKS.md.
5. Create 3 testers (customer, driver, admin) and run docs/TEST_PLAN.md once on real phones. Remove demo data afterwards (Admin > Demo data shows 0).
6. Approve every pilot driver by hand in Admin > Driver verification after you have seen the papers yourself: the app only checks formats.

## Daily routine (10 minutes)
- Admin > Supply and demand: loads waiting with no trucks near them? Call drivers there.
- Admin > Tickets and SOS: answer within the hour; use reply templates.
- Admin > System health: errors this week, open tickets, pending deletions.
- Admin > Flagged users and Rating bursts: anything new?
- Open loads older than a day: call the customer, adjust the price or close.

## Weekly review
- Admin > Unit economics (type your real fixed and per-trip costs once): trips, take rate, cancel rate, break-even trips.
- Admin > Analytics trends: top routes, cancel rate, active drivers.
- Feedback and Sahayak unknown questions: what are people asking that the app does not answer?
- Decide one change for next week and write it down here.

## Success and stop rules (suggested, adjust)
- Good: most loads that get an offer become trips, cancel rate under 15%, payments marked and confirmed within 2 days, support tickets answered the same day.
- Slow down and fix before adding people if: cancel rate over 25%, repeated safety tickets, or any case of money disputes you cannot settle from the records.
- Add one feature at a time (Features screen), watch a week, then the next.

## What the pilot does NOT test
Real payments, real KYC, push notifications when the app is closed, live map tracking. Those are in docs/PAID_UPGRADE_PLAN.md; payments and payouts are records only, so settle money outside the app and mark it.
