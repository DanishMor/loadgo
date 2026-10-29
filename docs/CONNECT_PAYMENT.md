# Connect: Online payment (UPI, card)

- Adapter: `PaymentGateway` in (payment_adapter.dart, razorpay_gateway.dart).
- Switch: `paymentGateway` (docs/FLAGS.md). The real adapter is used only when the switch is ON and `config/providers.payment.configured` is true (`ConnectKit.useReal`).
- Off or not configured: Payments are recorded only ("I have paid").
- What it needs: A payment partner account, KYC done, keys as functions secrets.
- Keys: never in the app, the repo or a doc. Keys live only as Cloud Functions secrets.

## Cost guard
- App side: at most 1000 calls a day from one phone and 20 per user (`ConnectKit.guard`). `config/providers.payment.daily` / `.perUser` can lower these, never raise them.
- Kill switch: turning `paymentGateway` off stops calls at once. Every paid switch is in the "costs" kill group once it is live (`lib/core/features/kill_switches.dart`).
- Server side: the function must repeat the caps before any paid call (E79).
- Cost note (UNVERIFIED): Payment partners charge a fee per payment. Check the provider's current price page before switching on.

## Owner steps
1. Finish the partner KYC.
2. Save the key secret as a functions secret; only the public key id reaches the app with each order.
3. Deploy the payment functions with signature checks.
4. Set config/providers.payment.configured = true, then switch on paymentGateway.
