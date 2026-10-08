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
