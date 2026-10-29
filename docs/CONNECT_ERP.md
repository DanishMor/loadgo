# Connect: ERP, Tally and webhook API for business accounts

- Adapter: `ErpWebhooks` in (connect_adapters.dart).
- Switch: `erpApi` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.erp.configured` is true (`ConnectKit.useReal`).
- Off or not configured: CSV and Excel export only.
- What it needs: Functions with hashed API keys and signed webhooks (E54).
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 5000 calls a day from one phone and 1000 per user (`ConnectKit.guard`). `config/providers.erp.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `erpApi` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Function runs and outbound traffic are billed. Check the provider's current price page before switching on.

## Owner steps
1. Take the Blaze plan.
2. Deploy the API functions (E54, E79).
3. Set config/providers.erp.configured = true.
4. Switch on erpApi when it is live.
