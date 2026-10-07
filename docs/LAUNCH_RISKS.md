# Launch risks

Honest list of what can go wrong at launch, how likely it feels, and what to do. Likelihood and impact are the author's judgement (L = low, M = medium, H = high), not measured. Owner = who acts.

| # | Risk | L | I | What reduces it | Owner |
|---|---|---|---|---|---|
| 1 | Drivers or customers move the deal outside the app (phone numbers shared after accept) | H | M | Phone shown only after accept; off-platform words in chat are warned and flagged; commission only recorded when the driver confirms payment, so watch trips with no confirmation | Admin |
| 2 | Money disputes: payment is a record, no escrow | M | H | Payment mode shown before booking; claims screen; keep ledger records; start with known drivers and small loads | Owner |
| 3 | Fake or stolen documents: KYC is format-only, never verified | M | H | Approve drivers by hand after seeing papers; duplicate-identity block; expired-papers stop; paid KYC later (docs/PAID_UPGRADE_PLAN.md) | Admin |
| 4 | Safety incident on a trip | L | H | SOS, share-trip link, emergency contacts, OTP at pickup and drop, support phone in config/support; decide who answers SOS and when | Owner |
| 5 | Firestore rules or indexes not deployed or changed by mistake | M | H | Rules tests (npm test) before every deploy; deploy only from a clean commit; keep SECURITY_REVIEW.md up to date | Owner |
| 6 | Firestore free quota or a bill surprise | M | M | docs/COST_WATCH.md: budget alert, listener limits, caches; features that read a lot are admin-only and refresh by button | Owner |
| 7 | Abuse: spam bids, fake ratings, chat spam, promo farming | M | M | Hourly rate limits in rules, bid range 30-300% of estimate, repeat-message guard, rating burst screen, promos OFF in the pilot | Admin |
| 8 | Phone sign-in SMS limits or delivery problems (Firebase Auth) | M | H | Check the current Auth SMS quota and cost in the Firebase console before launch; use test numbers for testers; plan a billing account | Owner |
| 9 | Wrong prices: offline city table and flat rates, no live traffic | H | M | Fare is an estimate; offers are the real price; admin edits `config/pricing`; watch average fare vs offers weekly | Admin |
| 10 | Legal: privacy policy, terms, GST invoice wording, DPDP duties are drafts | M | H | Lawyer review before Play Store; account deletion exists; invoice PDF is a record, not a filed GST invoice | Owner |
| 11 | Play Store rejection (policy URL, data safety, permission texts, package id) | M | M | docs/PLAY_STORE_CHECKLIST.md; fix the placeholder contact details; final application id before the first upload | Owner |
| 12 | Old phones, slow networks, big fonts, 12 languages with machine-written texts | H | M | Layout tests at 360 px and large text; offline cache; retry and slow-network states; have native speakers read the top 50 screens | Owner |
| 13 | One person is the whole support team and the admin | H | M | Reply templates, Sahayak, FAQ; set support hours in the Play listing and the Help text; do not promise 24x7 | Owner |
| 14 | Bad actor gets admin access | L | H | Admin list is a hand-made document; roles (super, support, verifier, ops) limit damage; every admin action writes an audit row; use a strong Google account | Owner |
| 15 | Data loss or a bad migration | L | H | Firestore export before bigger changes (Blaze needed for scheduled backups); docs/MIGRATIONS.md; no destructive scripts on live data | Owner |
| 16 | A feature switched on too early (network, rental, business) breaks support | M | M | Pilot mode keeps them off; turn on one at a time with a week of watching | Owner |

## Known gaps accepted for the pilot
No server: fares, commission and counters are written by the apps (rules constrain them but cannot sum). No push when the app is closed. Trip share link shows status, not live position. Payment and payout are records. KYC is not verified. See docs/PAID_UPGRADE_PLAN.md for the order to close them.

## Stop button
If something goes wrong: Admin > Features > turn the feature Off (15 minutes to reach phones), Admin > Config > `app` (set `maintenance` to true, with a message) for a full pause, and Admin > Users > Hold/Ban for one account.
