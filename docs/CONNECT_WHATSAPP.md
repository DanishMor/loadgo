# Connect: WhatsApp template messages

- Adapter: `WhatsAppGateway` in (connect_adapters.dart).
- Switch: `whatsappGateway` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.whatsapp.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Nothing is sent; share sheets still work.
- What it needs: A WhatsApp Business provider with approved templates.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 500 calls a day from one phone and 10 per user (`ConnectKit.guard`). `config/providers.whatsapp.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `whatsappGateway` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Template messages are billed per conversation. Check the provider's current price page before switching on.

## Owner steps
1. Get a WhatsApp Business account through a provider.
2. Get the templates approved.
3. Save the provider key as a functions secret.
4. Set config/providers.whatsapp.configured = true, then switch on whatsappGateway when it is live.
