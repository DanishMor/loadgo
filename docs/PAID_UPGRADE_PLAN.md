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

---

# Playbook: har paid cheez ko kaise lagayein (P12, Hinglish)

Upar ki table "kya aur kitna"; neeche "kaise, kis adapter se, kaise test, kaise wapas". Adapters ki fixed jagah: `lib/core/adapters/` (`docs/PAID_ADAPTERS.md`). Abhi app ka koi screen adapter ko call nahi karta, isliye har step mein **pehle app ko adapter se jodna** bhi ek kaam hai.

## 1. Order aur adapter map
| Order | Cheez | Adapter (`lib/core/adapters`) | Input | Output | Server par kya |
|---|---|---|---|---|---|
| 1 | Blaze + Cloud Functions | (adapter nahi; baaki sab isi par tikte hain) | trigger / call | server-side fare, commission, OTP limit, account deletion, TTL | Functions: `TODO(functions)` markers (27 jagah) |
| 2 | Push | `PushGateway` (`push_adapter.dart`) | `List<String> tokens`, `PushMessage(title, body, data)` | `PushOutcome(delivered, badTokens)` | bhejna Function se; bad tokens users se hatao |
| 3 | Photos | `FileStore` (`storage_adapter.dart`) | `path`, `Uint8List bytes`, `contentType` | `(StoredFile(path,url,bytes)?, StorageFailure?)` | `storage.rules` pehle se likhe hain |
| 4 | Maps | `MapsProvider` (`maps_adapter.dart`) | place text; do `GeoPoint2` | `GeoPoint2?`; `RouteInfo(meters, seconds)?` | API key restrict (Android package+SHA, web referrer) |
| 5 | Payments | `PaymentGateway` (`payment_adapter.dart`) | `createOrder(amountPaise, reference)`, `verify(orderId, paymentId, signature)`, `refund(paymentId, amountPaise)` | `(PaymentOrder?, PaymentFailure?)`; `PaymentResult` | **verify aur refund sirf server par**; app sirf order shuru kare aur result dikhaye |
| 6 | KYC / GST | `KycVerifier` (`kyc_adapter.dart`) | `KycKind`, number | `KycResult(status, holderName?)` | secret key server par; app sirf status dekhe |
| 7 | SMS / OTP | `SmsGateway` (`sms_adapter.dart`) | `send(E164, text)`, `startOtp(E164)`, `verifyOtp(challengeId, code)` | `SmsResult`, `OtpStart`, `bool` | DLT registration; bhejna server se |
| 8 | App Check | (Firebase Console, `docs/FIREBASE_CONSOLE_CHECKLIST.md` step 11) | - | - | pehle monitor, phir enforce |
| 9-10 | Insurance, LLM | insurance: idea; LLM: `AssistantEngine` interface (Sahayak) | - | - | LLM key server par, daily cap |

Rule: paisa **int paise**, phone **E.164**, jawab typed value (exception nahi), har `No...` default safe (network nahi, throw nahi).

## 2. Ek adapter lagane ka standard tareeka (har step par wahi)
1. **Provider chunein**, sandbox / test account lein (live key nahi). Kharcha limit aur contract note karein.
2. `class <Provider>Gateway implements <Interface>` likhein. **Key repo mein nahi**: Functions ke secret config ya Secret Manager se (`docs/SECRETS_AUDIT.md` ke niyam).
3. **Contract test**: `test/adapter_contract_test.dart` ke `makers` map mein provider ka sandbox version jodein. Wo sab tests pass kare jo `Fake` karta hai (paise integer, signature check, refund kabhi paid se zyada nahi, E.164, upload limits).
4. **Factory ek jagah** (jaise `Adapters.payments`): flag off ho to `No...` class do.
5. App ke screen ko adapter se jodein; `notConfigured` aaye to wahi purana "record only" raasta chale (screen kabhi na toote).
6. Privacy policy (naya processor), Play data-safety, `docs/DATA_RETENTION.md` update. Phir vakeel ko dikhayein (`docs/LEGAL_QUESTIONS.md`).

## 3. Sandbox mein kaise test karein
| Cheez | Sandbox tareeka | Pass kab maanein |
|---|---|---|
| Functions | `firebase emulators:start --only functions,firestore` (Java chahiye; `docs/WINDOWS_SETUP.md`) | rules tests + function unit tests pass |
| Push | do test phones par FCM test token; Console > Messaging se test message | message app band hone par aaye; galat token `badTokens` mein aaye |
| Photos | emulator ya alag test bucket | 10 MB se bada ya galat type reject; delete kaam kare |
| Maps | alag test key, daily quota cap | Delhi-Jaipur ka distance Google se milta jule (offline table se +-15%) |
| Payments | provider ka **test mode** (test cards/UPI), webhook ko emulator se | order, verify (galat signature reject), full aur partial refund, double-click par ek hi order |
| KYC | provider ke sample numbers | valid / invalid / provider down teeno ka sahi `KycStatus` |
| SMS | DLT template approve hone ke baad 2 test numbers | E.164 galat par reject; rate limit lage |
Har sandbox run ke baad `flutter test test/adapter_contract_test.dart` aur `docs/TEST_PLAN.md` ka relevant row.

## 4. Feature flag se rollback
* Flag store: `config/features` (`pilotMode`, `flags{key:bool}`; `lib/core/features/features.dart`, admin screen `admin_features_screen.dart`). Unknown key = **OFF**.
* Har paid adapter ke liye ek naya flag key banayein (jaise `paidPayments`, `paidPush`, `paidMaps`, `paidKyc`, `paidSms`) aur `Features.registry` mein `pilotOn: false` ke saath jodein. Ye abhi **bane nahi hain** (is plan ka kaam).
* Rollback: Admin > Features mein flag **Off** karein. Factory turant `No...` adapter deta hai, app purane "record only" raaste par wapas aa jaati hai; naya release nahi chahiye.
* Money wale flag ke liye: Off karne se pehle jo orders `created` par atke hain unka kya karna hai ye pehle likh lein (provider dashboard se manually refund/close), `docs/OWNER_GUIDE.md` dispute playbook ke saath.
* Naye flag par rollout: pehle 1 route / 10 log (`docs/PILOT_KIT.md`), phir badhayein.

## 5. Blaze plan lene ke baad **sabse pehle** (is order mein)
1. **Budget alert** (aaj hi): Google Cloud Billing > Budgets (chhoti limit, 50/90/100% e-mail). Functions ke bug se kharcha ek raat mein badh sakta hai. (`docs/FIREBASE_CONSOLE_CHECKLIST.md` step 10.)
2. **Quotas / max instances**: har Function par `maxInstances` chhota rakhein; Firestore/Storage ke daily usage alert lagayein.
3. **Rules aur indexes dobara deploy** (`tool/deploy_rules.ps1`), Storage rules sahi account se.
4. **Server-side fare/commission** pehle (client estimate par bharosa kam karein): `TODO(functions)` list se shuru.
5. **App Check** monitor mode (Play Integrity), phir enforce jab verified requests 95%+.
6. **API keys restrict** (Maps, Firebase) aur har provider ka secret Secret Manager mein; repo mein koi key nahi (`docs/SECRETS_AUDIT.md` dobara chalayein).
7. **Test numbers hatayein / kam karein**; SMS region policy sirf India (`FIREBASE_CONSOLE_CHECKLIST.md` step 5).
8. **Firestore TTL / clean-up policies** (`docs/DATA_RETENTION.md` ka TTL hissa) chalu karein; account deletion Admin SDK se.
9. **Monitoring**: Crashlytics, Functions logs, error alerts; ek hafte tak roz dekhein.
10. Phir order ke hisaab se adapters: 2 Push, 3 Photos, 4 Maps, phir 5+6 saath.

## 6. Har step ke baad check
- [ ] `flutter analyze` 0 issues, poora `flutter test`, `npm test` (rules).
- [ ] Contract test provider ke sandbox ke saath pass.
- [ ] Flag Off karke dekha: app purane raaste par theek chalti hai.
- [ ] Privacy policy, data-safety, retention, `docs/PAID_ADAPTERS.md` aur `docs/PROGRESS.md` update.
- [ ] Kharcha 1 hafte dekha aur budget ke andar.
