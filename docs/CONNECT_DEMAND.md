# Connect: Demand near the driver

- Adapter: `DemandFeed` in (connect_adapters.dart).
- Switch: `demandFeed` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.demand.configured` is true (`ConnectKit.useReal`).
- Off or not configured: the driver home shows no demand strip (the `NoDemandFeed` default answers with nothing).
- What it needs: a Cloud Function that counts open loads by pickup area (geohash cells) every few minutes and answers with counts only, never load details or customer names.
- Keys: none (our own server); the count is read with the driver's sign-in.

## Cost guard
- App side: at most 2000 calls a day from one phone and 48 per user (one every 30 minutes while online) (`ConnectKit.guard`). `config/providers.demand.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `demandFeed` off stops calls at once.
- Server side: the function should read a precomputed summary document, not scan loads per request.
- Cost note (UNVERIFIED): no outside provider; the cost is Cloud Functions time and one Firestore read per call on the Blaze plan.

## Owner steps
1. Deploy the counting function and its schedule (Blaze plan, docs/NOT_FREE.md).
2. Check one summary document in the console.
3. Set config/providers.demand.configured = true, then switch on demandFeed.
