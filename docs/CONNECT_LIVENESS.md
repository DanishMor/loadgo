# Connect: Selfie liveness

- Adapter: `LivenessChecker` in (connect_adapters.dart).
- Switch: `kycLiveness` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.liveness.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Admin looks at the selfie.
- What it needs: A liveness partner; selfies are processed on the server and not kept longer than needed.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 300 calls a day from one phone and 3 per user (`ConnectKit.guard`). `config/providers.liveness.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `kycLiveness` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Liveness checks are billed per check. Check the provider's current price page before switching on.

## Owner steps
1. Sign a liveness partner contract.
2. Update the privacy policy (new processor).
3. Save the key as a functions secret.
4. Set config/providers.liveness.configured = true, then switch on kycLiveness when it is live.
