# OTP security (login code and trip codes)

Two kinds of codes exist in Load 20:

1. **Login code**: Firebase Auth sends an SMS to the phone number.
2. **Trip codes**: the customer's pickup and delivery codes. The driver types them; the Firestore rules compare them with `bookings/{id}/secrets/otp`.

## What the app limits itself (and why that is not enough)

| Where | Limit | Code | Test |
|---|---|---|---|
| Login code, send | "Resend" waits 60 s; at most 5 codes per number per hour | `lib/core/security/otp_limits.dart`, `sendPhoneOtp` | `test/otp_limits_test.dart` |
| Login code, enter | 5 wrong codes lock that number for 15 minutes | same, `OtpVerificationScreen` | same |
| Trip code | every guess is stored and counted first; the 5th wrong guess locks the entry for 15 minutes; audit line `otp_lock`; customer sees a notice | `firestore.rules` (`otp_attempts`, `guessCommitted`), `lib/core/services/trip_otp_attempts.dart` | `firestore_rules_test` (F2 tests), `test/trip_otp_attempts_test.dart` |

**The login limits run on the phone.** A determined person can clear the app data, use another phone or call Firebase directly, and the counters are gone. They stop honest mistakes and casual abuse, nothing more. The real protection is the list below.

The **trip code limit is enforced by the Firestore rules**, so it cannot be skipped from the app. It still needs the server part (Phase C) for a second check and for alerts.

## The real protection (owner steps)

Each line says how to verify it.

1. **Firebase Auth's own limits.** Firebase limits SMS sends per phone number and per project/IP and returns `too-many-requests` or `quota-exceeded` (the app already maps both, see `authErrorKey`).
   *Verify:* read the current numbers in the official Firebase Authentication quota page (they change; do not copy numbers from this file). In the Firebase Console open Authentication, Usage, and look at the SMS count per day.
2. **SMS region: India only.** Authentication, Settings, SMS region policy: allow only India (+91), block the rest. Stops pumping fraud to premium foreign numbers.
   *Verify:* Console shows the policy as "Allow" with only India; try a +1 test number from the sign-in page of a test build and see it refused.
3. **Budget alert.** Google Cloud Console, Billing, Budgets and alerts: a small monthly amount with email alerts at 50, 90 and 100 percent. Phone auth SMS is billed on the Blaze plan.
   *Verify:* the budget is listed; send a test notification from the budget screen.
4. **Test phone numbers.** Fictional numbers added in Authentication, Sign-in method, Phone, "Phone numbers for testing" skip the SMS. **Delete all of them before launch.**
   *Verify:* the list in the Console is empty. Search the repo and docs for the test numbers: `docs/PLACEHOLDERS.md` lists where they are mentioned.
5. **App Check** (later, with Phase C/G). Makes Firebase accept SMS requests only from the real app build (Play Integrity). Needs the Play signing SHA values.
   *Verify:* Console, App Check, Authentication shows "Enforced"; a request from a rebuilt or emulated app is refused.
6. **Cloud Functions** (Phase C, F16 and F17). Server-side hourly counters for OTP-related actions, chat second scan.
   *Verify:* functions emulator tests (`functions/` tests), then the function list in the Console after the owner deploys.
7. **Trip codes.** The codes are six random digits from a secure generator, readable only by the customer. With 5 guesses per 15 minutes the chance to guess a code is at most 5 in 1,000,000 per window. Codes are single-use because the booking moves on after a correct one.
   *Verify:* rules tests "F2" in `firestore_rules_test/rules.test.mjs`.

## Rules for people working on the code

- Never log a code, a phone number or a verification id (`Redactor`, see `docs/SECURITY_REVIEW.md`).
- Never show the real code in an error message. `OtpVerificationScreen` shows only "n tries left".
- A redesign of the login screens must keep calling `sendPhoneOtp` (the limit lives there) and `OtpLimiter` in the code screen. `test/otp_limits_test.dart` fails if they are removed.
- The pickup and delivery step must keep storing the guess first. `test/trip_otp_attempts_test.dart` and the rules tests fail otherwise.

## Using MSG91 for the login code (G12, design only, default OFF)

**Today:** the login code is sent by Firebase Auth. To my knowledge the SMS provider of Firebase phone sign-in cannot be replaced (UNVERIFIED: re-check the Firebase documentation before relying on this). The app's MSG91 work (`smsSend`, `smsOnNotification`) never touches the login code.

**If the owner ever wants MSG91 to deliver the login code**, the only way is a *custom* sign-in: the server creates and checks the code and, when it is right, mints a Firebase **custom token** for the phone number. This is NOT built. If it is built later it must sit behind its own switch (`smsLoginOtp`, OFF) and must keep every control Firebase gives us for free:

| Risk | Why it matters | What the build must do |
|---|---|---|
| **SMS pumping** (fraud: bots request codes to premium numbers) | Firebase has its own abuse detection; a custom flow has none | India-only numbers (+91 and 10 digits), per number 5 per hour, per IP and per device limits, a total daily cap, a kill switch, App Check enforced first |
| **Code guessing** | A 6-digit code has 1,000,000 values | Store only a hash (HMAC with a secret), 5 tries per code then lock 15 minutes, code valid 5 minutes, single use |
| **Replay and enumeration** | Answers that differ for known and unknown numbers leak who is registered | The same answer for every number; constant-time compare; never say whether an account exists |
| **Token minting is account takeover** | A bug in the check lets anyone sign in as anyone | Mint the token only after a successful, unexpired, unused check; log every mint (audit); short-lived token; admin accounts never use this path |
| **DLT template** | Login SMS needs an approved DLT template and a registered header | Owner registers it with the provider first |
| **Cost** | Every request costs a few paise | quota.js daily caps and the budget alert |
| **Loss of Firebase's protections** | reCAPTCHA / Play Integrity checks inside Firebase Auth do not run | App Check on the callable; decide before building whether the saving is worth the added risk |

**Recommendation:** keep Firebase for the login code. Use MSG91 only for trip messages and the SOS message, where a mistake costs a message, not an account.
