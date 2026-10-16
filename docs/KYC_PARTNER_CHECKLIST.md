# ID check partner: what to ask, what it costs, what leaves the app (G13)

No partner is chosen. The app and the server are ready for one (`KycVerifier` on the phone, a provider with two lines on the server in `functions/src/kyc.js`); until then the admin looks at the papers, exactly as before. The sandbox gives fake answers for tests (`config/kyc.provider = "sandbox"`, never in production).

## What the code does today

- Switch `kycVerify` (OFF). After a driver saves papers the phone asks the server about licence, RC, PAN, and (for companies) GSTIN. The server checks the format again, limits each person (6 a day) and everybody (300 a day), asks the provider, and writes the answer to `kyc_checks/{uid}` (admins read, only the server writes).
- **Aadhaar**: only the last four digits are ever collected. The server refuses anything but exactly four digits and looks nothing up. The full number must never be asked for, stored, logged or sent to a partner.
- The number itself is not kept in `kyc_checks` or any log. The name the record carries is kept (up to 60 characters) so the admin can compare it with the profile.
- Result "unavailable" or any failure: nothing is stored, no quota is used, the admin card says "No automatic ID check yet. Please look at the papers yourself."

## Questions to ask each partner

1. Which checks, with what source: driving licence (Parivahan / Sarathi), vehicle RC (Vahan), PAN (name match), GSTIN (GST portal), bank account or UPI name match (for payouts)?
2. Price per check, minimum monthly fee, price when the answer is "not found", price for a repeat check, free sandbox?
3. Response time and uptime; what happens when the government source is down (do you cache? how old can an answer be?).
4. Do you return only match / no match and the holder name, or the full record (address, date of birth, photo)? We want the minimum: status and name.
5. Where is data processed and stored; how long do you keep what we send; can you promise no reuse (training, marketing, resale)?
6. Is there a data processing agreement; are you a registered entity in India; which security audits do you hold (ISO 27001, SOC 2)?
7. Auth method (API key, IP allow-list): the key goes into a Firebase secret, never in the repo.
8. Do you support only the last four digits of Aadhaar (or no Aadhaar at all)? Aadhaar rules limit who may verify and what may be stored; get written confirmation.
9. Webhook or polling; request ids we can log without the number.
10. Exit: can we export or delete our data when we leave?

## Data that would leave the app (for the privacy policy and DPDP)

| Data | Sent to the partner | Why | Kept by us |
|---|---|---|---|
| Driving licence number | yes | check it exists and the name | status and name only |
| Vehicle RC number | yes | check the owner name | status and name only |
| PAN | yes | name match | status and name only |
| GSTIN | yes (companies) | legal name match | status and name only |
| Aadhaar | **no** (only the last four digits are kept, never sent) | not needed | last four digits as today |
| Date of birth, address, photo | no | not needed | not collected from the partner |

DPDP questions for the lawyer (also in docs/LEGAL_QUESTIONS.md): Is the driver's consent enough or must it be a separate notice? Which legal basis applies to a safety/verification check? Is the partner a processor under our control or an independent fiduciary? How is a correction or withdrawal handled (a "not found" must never be final: the admin can accept the papers by eye)? What is the retention of `kyc_checks`?

## Cost estimate (fill in with the real price)

Checks per new driver: 3 (licence, RC, PAN). 1,000 new drivers x 3 x price per check. Repeats happen on edits only (each edit re-asks, limited 6 a day). A busy day of 100 sign-ups uses about 300 checks, which is why the total daily cap is 300 until it is raised on purpose.

## Plugging a partner in (for the developer)

1. Add a provider object `{ name: 'partnername', lookup(kind, number) }` in `functions/src/kyc.js` that calls the partner with the key from a Firebase secret and returns `{status, holderName?}` (statuses: verified, mismatch, not_found, unavailable).
2. Select it with `config/kyc.provider`.
3. Add its sandbox to the contract test (`functions/test/emulator/kyc.test.js`, `test/kyc_g13_test.dart`): it must pass every test the sandbox passes, including "a full Aadhaar number is refused".
4. Update the privacy policy, the Play data-safety answers and docs/PAID_UPGRADE_PLAN.md.
