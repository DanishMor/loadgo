# Connect: Reefer temperature and GPS devices

- Adapter: `DeviceTelemetry` in (connect_adapters.dart).
- Switch: `deviceIngest` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.telemetry.configured` is true (`ConnectKit.useReal`).
- Off or not configured: No device data; the driver reports by hand.
- What it needs: A device vendor that posts readings to a function.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 5000 calls a day from one phone and 500 per user (`ConnectKit.guard`). `config/providers.telemetry.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `deviceIngest` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Device vendors charge per device per month; function runs are billed. Check the provider's current price page before switching on.

## Owner steps
1. Pick a device vendor.
2. Save the vendor webhook secret as a functions secret.
3. Deploy the ingest function (E79).
4. Set config/providers.telemetry.configured = true, then switch on deviceIngest when it is live.
