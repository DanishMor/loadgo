# SMS setup (G12)

What the SMS code does (switch `smsGateway`, OFF): a short trip-step SMS to a customer who has no push token, and the SOS text to the person's own saved emergency contacts. Never the login code (docs/OTP_SECURITY.md).

## Owner steps (India)

1. Open an account with the SMS partner (the code is written for MSG91's Flow API; the request shape is UNVERIFIED against their live documentation, check it first).
2. **DLT registration**: register the business (principal entity) and a sender header, then get two **templates approved**. Suggested wording (adapt to what the portal accepts; variables are written `{#var#}`):
   - `tripStatus`: "Load 20: {#var#} (ref {#var#}). Open the app for details."
   - `sos`: "Load 20 SOS: {#var#}"
3. Put the two template ids in Firestore `config/sms`:
   `{ "templates": { "tripStatus": "<id>", "sos": "<id>" }, "perUserPerDay": 10, "totalPerDay": 500 }`
   (Console > Firestore > config > sms. Template ids are not secret.)
4. Set the key as a secret yourself: `firebase functions:secrets:set MSG91_AUTH_KEY` and type it when asked. Never in chat, never in the repo.
5. Deploy functions, then Admin > Features > **SMS messages**.

## Cost and safety

- A transactional SMS costs a few paise each (check the partner price list). `perUserPerDay` and `totalPerDay` stop a runaway day; both are counted in `quota_usage` (set a TTL policy on `expireAt`).
- A trip SMS goes only to people who have a phone number saved and **no push token**, and who did not switch booking updates off. People with push never get an SMS.
- The SOS text can only be sent to a number the caller saved as an emergency contact (the server checks), so the function cannot be used to spam strangers.
- Test: with the switch on and a test template, accept a booking as a customer on a phone without notifications; one SMS arrives. Switch off = no SMS at once.
