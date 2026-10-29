# Connect: Cargo insurance quote request (legal gate)

- Adapter: `InsuranceQuotes` in (connect_adapters.dart).
- Switch: `legalGateInsurance` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.insurance.configured` is true (`ConnectKit.useReal`).
- Off or not configured: No insurance option is shown.
- What it needs: A licensed insurance partner. The app only passes on a quote request; it never sells or promises cover.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 100 calls a day from one phone and 3 per user (`ConnectKit.guard`). `config/providers.insurance.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `legalGateInsurance` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Partner terms vary. Check the provider's current price page before switching on.

## Owner steps
1. Get legal advice; only a licensed partner may sell cover.
2. Sign a partner agreement.
3. Save the key as a functions secret.
4. Set config/providers.insurance.configured = true, then switch on legalGateInsurance yourself.
