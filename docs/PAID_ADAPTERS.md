# Paid adapters (MASTER-6 Task 46)

Everything in `lib/core/adapters/` is the plug for a paid service. Today the app runs on the free stack, so each adapter has: an interface, a **Fake** (tests, demos), and a **No...** default that fails calmly with `notConfigured`. Nothing in the app calls an adapter yet; when you buy a service, you write one class, add it to the contract test and switch the one place that builds it.

| Adapter | File | Paid service | Today (free path) | Marker |
|---|---|---|---|---|
| `SmsGateway` (send + one-time code) | sms_adapter.dart | SMS provider with DLT registration | Firebase Auth phone sign-in; no SMS to emergency contacts | `LATER(paid)` SMS |
| `PushGateway` | push_adapter.dart | FCM send through Cloud Functions (Blaze) | tokens saved, in-app inbox | `LATER(paid)` push |
| `MapsProvider` (geocode, route) | maps_adapter.dart | Google Maps Platform | offline city table and straight-line distance | `LATER(paid)` maps |
| `PaymentGateway` (order, verify, refund) | payment_adapter.dart | payment partner (UPI, card) | payments are recorded, not processed | `LATER(paid)` gateway |
| `KycVerifier` | kyc_adapter.dart | licence / RC / PAN / GSTIN / Aadhaar partner | format checks and admin review | `LATER(paid)` KYC |
| `FileStore` | storage_adapter.dart | Firebase Storage (Blaze) | no photo upload | `LATER(paid)` photos |

## How to plug a real provider in
1. Write a class that implements the interface (for example `RazorpayGateway implements PaymentGateway`). Keep keys out of the code: read them from a server-side function or secure config, never from the repo or the app.
2. Add it to the `makers` map in `test/adapter_contract_test.dart` for that group (use the provider's sandbox). It must pass every test the fake passes: amounts as whole paise, signature checks, refunds never above what was paid, E.164 numbers, upload limits equal to `storage.rules`.
3. Build it in ONE place (a small factory, for example `Adapters.payments`), default to the `No...` class, and switch by a Remote Config / `config/features` flag so you can turn it off.
4. Anything that moves money or checks a signature must run on the server (Cloud Functions). The client may only start an order and show the result: `TODO(functions)`.
5. Update `docs/PAID_UPGRADE_PLAN.md`, the privacy policy (new processor) and the Play data-safety answers.

## Rules the interfaces follow
- Money is always `int` paise. Phone numbers are E.164. Results are typed values (`ok` / `failure`), not exceptions, so a provider outage never crashes a screen.
- Each default (`No...`) must be safe to ship: no network call, no throw.
