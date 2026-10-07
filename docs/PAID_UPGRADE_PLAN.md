# Paid upgrade plan

Everything built so far runs on the free Firebase stack (Auth + Firestore + Hosting, Crashlytics/Analytics/Remote Config on the free tier). Items below need billing or a partner. The order is by value for a first public launch. The cost column is a rough planning guess from general knowledge, NOT checked against today's price pages: always confirm on the provider's page before committing. Amounts are per month in rupees unless written otherwise.

| Step | Needs | Unlocks | Rough cost | Code marker |
|---|---|---|---|---|
| 1. Blaze plan + Cloud Functions | billing account | server-side fare and commission, audit events from triggers, OTP attempt limit, account deletion with the Admin SDK, scheduled reminders, promo/credit/referral counting, `app_errors` and presence cleanup | ~0 to 2,000 at small volume (free quota first, then pay as you use); set a budget alert | `TODO(functions)` |
| 2. Push notifications | Blaze (functions) + FCM | alerts when the app is closed, wave dispatch to nearby drivers (geohash already stored) | FCM itself is free; cost is the functions that send it (inside step 1) | `LATER(paid)` push |
| 3. Firebase Storage | Blaze | photos for RC, vehicle papers, pickup/delivery proof, POD packet, driver photo; `storage.rules` already written | ~0 to 1,000 for the first few thousand photos; grows with photos and downloads | `LATER(paid)` photos |
| 4. Maps and Places | Google Maps Platform key | map picker, live tracking map, real road distance and ETA, geocoding instead of the 64-city table | free monthly allowance per API, then per 1,000 requests; plan 2,000 to 15,000 depending on use | `LATER(paid)` maps |
| 5. Payment gateway | payment partner, business KYC | in-app UPI/card payment, escrow-like hold, refunds, driver payouts instead of manual | no fixed fee usually; about 2% on cards, UPI often near 0%; business KYC needed | `LATER(paid)` gateway |
| 6. KYC and GST verification | verification API partner | licence, RC, PAN, Aadhaar and GSTIN checks instead of format checks; e-way bill API | per check, roughly 3 to 25 each; ask for volume pricing | `LATER(paid)` KYC |
| 7. SMS and masked calling | SMS / telephony provider | emergency contact SMS, OTP fallback, call without sharing numbers | SMS roughly 0.15 to 0.30 each plus one-time DLT registration; masked calling per minute | `LATER(paid)` SMS |
| 8. App Check (Play Integrity) | Play Console + Firebase setup | blocks calls from modified apps | free within quota | docs/BLOCKED.md |
| 9. Insurance partner | partnership | cargo cover at booking | premium is paid per booking by the customer; revenue share to negotiate | idea only |
| 10. LLM assistant | LLM API key | smarter Sahayak behind the same `AssistantEngine` interface | per token; a few thousand at small volume, set a daily cap | `LATER(paid)` LLM |

## One-time and yearly
- Google Play developer account: one-time fee of about USD 25 (check today's rate).
- Own domain for links and policy pages: optional, roughly 800 to 1,500 a year; then change the host in `ShareLinks`, `PolicyLinks`, the manifest and `config/app.policyBaseUrl`.
- Lawyer review of privacy policy and terms: quote needed.
- Icon and screenshots design: quote needed (G7.7).

## Suggested order
1 -> 2 -> 3 first (reliability and photos), then 4, then 5 and 6 together (money and trust). 7 to 10 when the volume asks for them.

## What stays "record only" in version 1
Payments, payouts, credits, promo settlement, tips, incentives, claims awards, invoices (PDF is a record, not a filed GST invoice), e-way bill numbers (typed, not verified), KYC numbers (not verified).
