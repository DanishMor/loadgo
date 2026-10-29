# Paid adapters (MASTER-6 Task 46)

Everything in `lib/core/adapters/` is the plug for a paid service. Today the app runs on the free stack, so each adapter has: an interface, a **Fake** (tests, demos), and a **No...** default that fails calmly with `notConfigured`. Nothing in the app calls an adapter yet; when you buy a service, you write one class, add it to the contract test and switch the one place that builds it.

| Adapter | File | Paid service | Today (free path) | Marker |
|---|---|---|---|---|
| `SmsGateway` (send + one-time code) | sms_adapter.dart | SMS provider with DLT registration | Firebase Auth phone sign-in; no SMS to emergency contacts | `LATER(paid)` SMS |
| `PushGateway` | push_adapter.dart | FCM send through Cloud Functions (Blaze) | tokens saved, in-app inbox | `LATER(paid)` push |
| `MapsProvider` (geocode, route) | maps_adapter.dart | Google Maps Platform | offline city table and straight-line distance | `LATER(paid)` maps |
| `PaymentGateway` (order, verify, refund) | payment_adapter.dart | payment partner (UPI, card) | payments are recorded, not processed | `LATER(paid)` gateway |
| `KycVerifier` | kyc_adapter.dart | licence / RC / PAN / GSTIN / Aadhaar partner | format checks and admin review | `LATER(paid)` KYC |
| `RazorpayGateway` (F34, G9) | razorpay_gateway.dart, online_pay.dart, razorpay_checkout.dart | Razorpay through Cloud Functions (key stays on the server; the app gets only the public key id with each order) | `NoPaymentGateway` until the switch `paymentGateway` is on; the old "I have paid" record flow stays | `LATER(paid)` gateway |
| `Msg91SmsGateway`, `PartnerKycVerifier` (F35) | partner_adapters.dart | SMS provider, KYC partner (skeletons, server functions not written) | `NoSmsGateway`, manual admin review | `LATER(paid)` SMS / KYC |
| `EwayBillProvider` (G14) | eway_adapter.dart | GST Suvidha Provider (e-way bill) | the person makes the bill on the GST portal and records the number; the app checks 12 digits and the expiry | `LATER(paid)` GSP |
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

## Elite connect kit (E4)
- `lib/core/adapters/connect_adapters.dart`: Toll, Places, WhatsApp, Payout, Liveness, OCR, Translation, Speech, Device telemetry, Insurance quotes, Credit partner links, ERP webhooks (interface, `No...` default, `Fake...`).
- `lib/core/adapters/connect_registry.dart` (`ConnectKit`): one line per service with its switch, owner sheet (`docs/CONNECT_<ID>.md`) and cost caps. The real adapter is used only when the switch is ON and `config/providers.<id>.configured` is true. `config/providers` holds only booleans and caps, never a key.
- `lib/core/adapters/cost_guard.dart`: daily and per-user caps, and the switch as kill switch. Config may lower caps, never raise them.
- Test: `test/connect_kit_test.dart`.
