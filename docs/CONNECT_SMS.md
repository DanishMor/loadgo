# Connect: SMS to emergency contacts

- Adapter: `SmsGateway` in (sms_adapter.dart, partner_adapters.dart).
- Switch: `smsGateway` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.sms.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Nothing is sent; login codes stay with Firebase Auth.
- What it needs: A DLT-registered SMS provider; templates approved on DLT.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 200 calls a day from one phone and 5 per user (`ConnectKit.guard`). `config/providers.sms.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `smsGateway` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): SMS is billed per message; watch for SMS pumping. Check the provider's current price page before switching on.

## Owner steps
1. Register the sender and templates on DLT.
2. Save the provider key as a functions secret.
3. Deploy smsSend.
4. Set config/providers.sms.configured = true, then switch on smsGateway.
