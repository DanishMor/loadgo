# Paid upgrade plan

Everything built so far runs on the free Firebase stack (Auth + Firestore + Hosting, Crashlytics/Analytics/Remote Config on the free tier). Items below need billing or a partner. The order is by value for a first public launch. Costs are not quoted here: check each provider's current price page.

| Step | Needs | Unlocks | Code marker |
|---|---|---|---|
| 1. Blaze plan + Cloud Functions | billing account | server-side fare and commission, audit events from triggers, OTP attempt limit, account deletion with the Admin SDK, scheduled reminders, promo/credit/referral counting, `app_errors` and presence cleanup | `TODO(functions)` |
| 2. Push notifications | Blaze (functions) + FCM | alerts when the app is closed, wave dispatch to nearby drivers (geohash already stored) | `LATER(paid)` push |
| 3. Firebase Storage | Blaze | photos for RC, vehicle papers, pickup/delivery proof, POD packet, driver photo; `storage.rules` already written | `LATER(paid)` photos |
| 4. Maps and Places | Google Maps Platform key | map picker, live tracking map, real road distance and ETA, geocoding instead of the 64-city table | `LATER(paid)` maps |
| 5. Payment gateway | payment partner, business KYC | in-app UPI/card payment, escrow-like hold, refunds, driver payouts instead of manual | `LATER(paid)` gateway |
| 6. KYC and GST verification | verification API partner | licence, RC, PAN, Aadhaar and GSTIN checks instead of format checks; e-way bill API | `LATER(paid)` KYC |
| 7. SMS and masked calling | SMS / telephony provider | emergency contact SMS, OTP fallback, call without sharing numbers | `LATER(paid)` SMS |
| 8. App Check (Play Integrity) | Play Console + Firebase setup | blocks calls from modified apps | docs/BLOCKED.md |
| 9. Insurance partner | partnership | cargo cover at booking | idea only |
| 10. LLM assistant | LLM API key | smarter Sahayak behind the same `AssistantEngine` interface | `LATER(paid)` LLM |

## Suggested order
1 -> 2 -> 3 first (reliability and photos), then 4, then 5 and 6 together (money and trust). 7 to 10 when the volume asks for them.

## What stays "record only" in version 1
Payments, payouts, credits, promo settlement, tips, incentives, claims awards, invoices (PDF is a record, not a filed GST invoice), e-way bill numbers (typed, not verified), KYC numbers (not verified).
