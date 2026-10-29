# Connect: Push notifications

- Adapter: `PushGateway` in (push_adapter.dart).
- Switch: `pushNotifications` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.push.configured` is true (`ConnectKit.useReal`).
- Off or not configured: The in-app inbox only.
- What it needs: Firebase Cloud Messaging and the push functions (Blaze).
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 20000 calls a day from one phone and 50 per user (`ConnectKit.guard`). `config/providers.push.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `pushNotifications` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): FCM itself has no per-message fee; function runs are billed. Check the provider's current price page before switching on.

## Owner steps
1. Take the Blaze plan.
2. Deploy the push functions.
3. Set config/providers.push.configured = true.
4. Switch on pushNotifications.
