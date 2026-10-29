# Connect: Maps, geocoding and road distance

- Adapter: `MapsProvider` in (maps_adapter.dart).
- Switch: `maps` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.maps.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Offline city table and straight-line distance.
- What it needs: A Google Maps Platform key stored as a Cloud Functions secret (docs/MAPS_SETUP.md).
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 3000 calls a day from one phone and 60 per user (`ConnectKit.guard`). `config/providers.maps.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `maps` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Maps is billed per request after a monthly free credit. Check the provider's current price page before switching on.

## Owner steps
1. Create the key in Google Cloud and restrict it.
2. Save it as a secret with firebase functions:secrets:set (never in the repo).
3. Deploy the maps functions.
4. Set config/providers.maps.configured = true, then switch on maps.
