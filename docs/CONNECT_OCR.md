# Connect: Reading text from DL, RC and plate photos

- Adapter: `OcrReader` in (connect_adapters.dart).
- Switch: `ocrAutofill` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.ocr.configured` is true (`ConnectKit.useReal`).
- Off or not configured: The person types the numbers.
- What it needs: An OCR API through a function, or an on-device reader added later.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 500 calls a day from one phone and 10 per user (`ConnectKit.guard`). `config/providers.ocr.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `ocrAutofill` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Cloud OCR is billed per image. Check the provider's current price page before switching on.

## Owner steps
1. Pick an OCR service.
2. Save the key as a functions secret.
3. Set config/providers.ocr.configured = true.
4. Switch on ocrAutofill when it is live. The person always confirms what was read.
