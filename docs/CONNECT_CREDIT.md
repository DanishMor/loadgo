# Connect: FASTag, fuel card and driver advance links (legal gate)

- Adapter: `CreditPartnerLinks` in (connect_adapters.dart).
- Switch: `legalGateCredit` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.credit.configured` is true (`ConnectKit.useReal`).
- Off or not configured: No partner links are shown.
- What it needs: Partner https links only. The app has no lending logic.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 500 calls a day from one phone and 10 per user (`ConnectKit.guard`). `config/providers.credit.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `legalGateCredit` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): No per-call fee for a link. Check the provider's current price page before switching on.

## Owner steps
1. Get legal advice.
2. Sign partner agreements.
3. Add the https links in config/providers.credit (links only, no keys).
4. Set configured = true, then switch on legalGateCredit yourself.
