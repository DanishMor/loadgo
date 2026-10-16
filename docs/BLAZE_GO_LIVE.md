# Blaze go-live: the ordered checklist (F36)

Today the app runs on the free Firebase plan. Cloud Functions, Storage and push need the **Blaze** plan (pay as you use, with a free allowance first). This file is the order to follow. **The owner does every step with their own login; Claude never runs a deploy.** Do one step, check it, then the next. If a check fails, stop and use the Rollback line of that step.

## 0. Before anything

- [ ] Read `docs/FUNCTIONS.md` (what each function does) and `docs/COST_WATCH.md` (what it can cost).
- [ ] The latest app version is on the pilot phones. Older app versions do not know the trip-code rules or the photo paths.
- [ ] `git status` is clean and the tests pass on this laptop (`flutter analyze`, the rules tests, `functions` tests).

## 1. Take the Blaze plan and set a budget alert (same day)

1. Firebase Console > Usage and billing > change plan to Blaze.
2. Google Cloud Console > Billing > Budgets and alerts: create a small budget (for example Rs 500 a month) with e-mail alerts at 50%, 90% and 100%.
3. Add a second alert for a daily spike if your console offers it.

Check: the budget shows in Billing and you got the test e-mail. Rollback: Blaze can be switched back to Spark; functions stop.

## 2. Rules and indexes (no functions yet)

1. `firebase deploy --only firestore:rules,storage` with the project id of the pilot project.
2. `firebase deploy --only firestore:indexes` and wait until every index in the console says **Enabled** (can take minutes).
3. Open the app: sign in, open a load, a chat, the wallet. Nothing should show "permission denied".

Check: the app works as before with all switches OFF. Rollback: redeploy the previous `firestore.rules` and `storage.rules` from git.

## 3. Turn Storage on

1. Firebase Console > Storage > Get started (location **asia-south1** if offered; the choice cannot be changed later).
2. Deploy `storage.rules` again if the console asked you to create the bucket first.
3. Do **not** switch `photoUploads` on yet.

## 4. Functions: secrets, then deploy

1. Only if you will use online payment: set the two secrets yourself. Each command asks you to type the value, so it never appears in a file or in this chat:
   - `firebase functions:secrets:set RAZORPAY_KEY_ID`
   - `firebase functions:secrets:set RAZORPAY_KEY_SECRET`
   - `firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET` (a long random text you invent; type the same text in the Razorpay dashboard webhook form)
   - `firebase functions:secrets:set MSG91_AUTH_KEY` (only for SMS, see docs/SMS_SETUP.md)
   - `firebase functions:secrets:set MAPS_SERVER_KEY` (only for maps, see docs/MAPS_SETUP.md)
   After the deploy (step 3) Razorpay dashboard > Webhooks > add the URL of `paymentWebhook` (Console > Functions > paymentWebhook > URL), events `payment.captured`, `payment.failed`, `refund.processed`.
   Use the **test** keys from the Razorpay dashboard first. Keep the live keys for step 9.
2. `cd functions; npm ci; npm test` then `npm run test:emulator`.
3. `firebase deploy --only functions` (see `docs/FUNCTIONS.md`).
4. Console > Functions: every function is listed in `asia-south1`. Set a small `maxInstances` if the console shows a large default.
5. Admin > System health > **Check server**: it must say "The server answers."

Check: the app is unchanged because every switch is still OFF. Rollback: `firebase functions:delete <name> --region asia-south1`.

## 5. Switch on, one at a time (24 hours apart)

Admin > Features. After each switch watch Console > Functions > Logs and Billing for one day. Use the pilot switch first (one route, about 10 people), then everyone.

| Order | Switch | What to watch |
|---|---|---|
| 1 | `serverLimits` | people complaining they cannot bid or chat |
| 2 | `serverChatScan` | removed messages in the admin log |
| 3 | `serverTrust` | trip counts on a few profiles |
| 4 | `serverCredits` | referral and credit balances |
| 5 | `serverJobs` | loads expiring at 03:00 India time |
| 6 | `serverAdminActions` | risk tier and driver approval still work; audit lines appear |
| 7 | `serverDeletion` | one test deletion request end to end |
| 8 | `photoUploads` | papers and trip photos upload; Storage size in the console |
| 9 | `pushNotifications` | a real phone gets a push; tapping opens the right screen |
| 10 | `adminBroadcast` | one announcement to yourself only first |
| 11 | `serverWallet` | the daily check says "every person balances" |
| 12 | `paymentGateway` | test mode only (step 8) |

## 6. Real phone tests (cannot be done on the laptop)

- [ ] Push arrives with the app closed, in the right channel, in the right language.
- [ ] A photo from the camera uploads on mobile data and on a weak network (and waits when offline).
- [ ] The screenshot block (`secureScreens`) shows a black picture on wallet and papers screens.
- [ ] The login code arrives by SMS; test phone numbers are removed in Authentication (`docs/OTP_SECURITY.md`).

## 7. App Check (optional but recommended)

Register the Android app with Play Integrity, run in **monitor** mode, and enforce only when almost all requests are verified.

## 8. Online payment, test mode

1. Make sure step 4.1 used the **test** keys.
2. Switch `paymentGateway` on for the pilot only.
3. Pay a small booking with Razorpay's test card or UPI id, then check `payment_orders` in the console shows `paid`.
4. Try a refund from Admin (finance or super role only). The order shows the refunded amount.
5. Real money only after `docs/WALLET_GO_LIVE.md` is satisfied and the lawyer and CA have answered.

## 9. Live keys (last)

Set the live keys with the same two commands, redeploy the functions, and make a tiny first payment of your own.

## Rollback at any time

- Any switch OFF in Admin > Features (takes effect within 30 seconds). The app returns to its older behaviour.
- A function misbehaving: turn its switch OFF first, then delete or redeploy the function.
- Costs rising: check Console > Billing > Reports by service. Turn off the last switch you added.
- Never edit money by hand. Use Reverse, Reject and correction lines (`docs/WALLET_SECURITY.md`).
