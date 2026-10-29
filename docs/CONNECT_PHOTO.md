# Connect: Photo and file storage

- Adapter: `FileStore` in (storage_adapter.dart).
- Switch: `photoUploads` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.photo.configured` is true (`ConnectKit.useReal`).
- Off or not configured: No upload; the screen says photos are not on yet.
- What it needs: Firebase Storage on the Blaze plan; storage.rules published.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 2000 calls a day from one phone and 40 per user (`ConnectKit.guard`). `config/providers.photo.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `photoUploads` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Storage is billed per GB stored and downloaded. Check the provider's current price page before switching on.

## Owner steps
1. Take the Blaze plan (docs/BLAZE_GO_LIVE.md).
2. Publish storage.rules (docs/RULES_PUBLISH.md).
3. Set config/providers.photo.configured = true.
4. Switch on photoUploads on Admin > Features.
