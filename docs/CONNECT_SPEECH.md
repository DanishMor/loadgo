# Connect: Voice announcements and voice input

- Adapter: `SpeechAdapter` in (connect_adapters.dart).
- Switch: `voiceAnnounce` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.speech.configured` is true (`ConnectKit.useReal`).
- Off or not configured: A short chime.
- What it needs: The phone's own text-to-speech; no account needed.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 5000 calls a day from one phone and 300 per user (`ConnectKit.guard`). `config/providers.speech.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `voiceAnnounce` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Platform TTS has no per-call fee. Check the provider's current price page before switching on.

## Owner steps
1. Nothing to buy.
2. Set config/providers.speech.configured = true after a phone test.
3. Switch on voiceAnnounce when it is live.
