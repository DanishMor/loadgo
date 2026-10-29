# Connect: Chat auto-translate

- Adapter: `Translator` in (connect_adapters.dart).
- Switch: `autoTranslate` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.translation.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Messages are shown as written.
- What it needs: A translation API through a function.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 5000 calls a day from one phone and 200 per user (`ConnectKit.guard`). `config/providers.translation.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `autoTranslate` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Translation is billed per character. Check the provider's current price page before switching on.

## Owner steps
1. Pick a translation API.
2. Save the key as a functions secret.
3. Set config/providers.translation.configured = true.
4. Switch on autoTranslate when it is live.
