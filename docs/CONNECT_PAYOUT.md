# Connect: Instant payout to drivers (legal gate)

- Adapter: `PayoutGateway` in (connect_adapters.dart).
- Switch: `legalGatePayout` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.payout.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Payout requests are recorded and paid by hand.
- What it needs: A payout partner contract and an owner legal check. Regulated: the owner decides.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 200 calls a day from one phone and 3 per user (`ConnectKit.guard`). `config/providers.payout.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `legalGatePayout` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Payout partners charge per transfer. Check the provider's current price page before switching on.

## Owner steps
1. Get legal advice on payouts.
2. Sign a payout partner contract.
3. Save the key as a functions secret; payouts run only on the server with an idempotency key.
4. Set config/providers.payout.configured = true, then switch on legalGatePayout yourself.
