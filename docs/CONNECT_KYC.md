# Connect: Document verification (licence, RC, PAN, GSTIN)

- Adapter: `KycVerifier` in (kyc_adapter.dart, partner_adapters.dart).
- Switch: `kycVerify` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.kyc.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Format checks and admin review.
- What it needs: A KYC partner contract; Aadhaar is never sent.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 300 calls a day from one phone and 5 per user (`ConnectKit.guard`). `config/providers.kyc.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `kycVerify` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): KYC checks are billed per lookup. Check the provider's current price page before switching on.

## Owner steps
1. Sign a KYC partner contract.
2. Save the key as a functions secret.
3. Deploy kycVerify.
4. Set config/providers.kyc.configured = true, then switch on kycVerify.
