# Connect: Toll estimate

- Adapter: `TollEstimator` in (connect_adapters.dart).
- Switch: `tollEstimate` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.toll.configured` is true (`ConnectKit.useReal`).
- Off or not configured: No toll line in the estimate.
- What it needs: A toll data partner reached through a Cloud Function.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 1000 calls a day from one phone and 30 per user (`ConnectKit.guard`). `config/providers.toll.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `tollEstimate` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Toll APIs are usually billed per lookup. Check the provider's current price page before switching on.

## Owner steps
1. Pick a toll data partner and sign up.
2. Save the partner key as a functions secret.
3. Deploy the toll function (E79 skeleton).
4. Set config/providers.toll.configured = true, then switch on tollEstimate when it is live.
