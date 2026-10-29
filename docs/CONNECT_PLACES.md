# Connect: Nearby services (fuel, dhaba, mechanic, tyre, weighbridge)

- Adapter: `PlacesFinder` in (connect_adapters.dart).
- Switch: `nearbyServices` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.places.configured` is true (`ConnectKit.useReal`).
- Off or not configured: The admin-curated list only.
- What it needs: A places API key as a functions secret. Without it the admin-curated list is used.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 1000 calls a day from one phone and 30 per user (`ConnectKit.guard`). `config/providers.places.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `nearbyServices` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Places search is billed per request. Check the provider's current price page before switching on.

## Owner steps
1. Get a places API key and restrict it.
2. Save it as a functions secret.
3. Set config/providers.places.configured = true.
4. Switch on nearbyServices when it is live.
