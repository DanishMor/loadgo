# Earnings and accounts: questions for the lawyer and the CA (F13)

These are questions, not answers. Claude is not a lawyer. Nothing here is advice. The app today keeps **records only** of what a driver earned, the commission and what was paid by hand.

## 1. What is it in law?

1. Is a screen showing "what you earned and what is still to come" only a **record of earnings** (an accounts statement), or does it become **held money / a prepaid instrument / a wallet** if Load 20 keeps the customer's money until the trip ends?
2. At what point does the model need an RBI authorisation (for example prepaid payment instruments or payment aggregator rules)? Which designs avoid it (for example the customer pays the driver directly and Load 20 only invoices its own commission)?
3. May the product use the word **"wallet"** in the app, in the Play Store text and in advertising, or must it say "earnings and accounts" (the current default label)?
4. If a payment gateway holds and settles the money, which party is the merchant, and what must our terms say?

## 2. Tax

1. **TDS**: is any TDS to be deducted when Load 20 pays a driver or a transporter (which section, which rate, which threshold)? Who issues the certificate?
2. **GST on commission**: Load 20's commission or platform fee, is it taxable, at what rate, and what must the invoice to the driver show? Does the driver need a GSTIN?
3. Does the **transporter** (who bills a party and pays a driver) need to issue a different document from our statement? (Our statements say "a record, not a tax invoice".)
4. Records to keep, and for how many years.

## 3. KYC for payouts

1. What identity proof is needed before the first payout (PAN, bank account name match, Aadhaar-based)? Limits without KYC?
2. How should payout details (UPI id, bank account) be stored and shown? (Today: UPI id only, masked to admins.)
3. Rules for paying a third-party account, and for changing details (we use a fresh code and a waiting time).

## 4. Refunds and disputes

1. Time limit to refund a customer after a cancelled or disputed trip.
2. Who bears the cancellation charge and how it is shown.
3. What must the terms say about reversals of a paid payout (failed transfer) and about freezing a person's payouts during a review?

## 5. Data protection

1. How long may payout and ledger records be kept, and when must they be erased on an account deletion request (the ledger may have to stay for tax)?
2. Are payout details "sensitive personal data" under the DPDP Act, and what notices and consents are needed?

## What the product will do once these are answered

The answers change flags and texts, not the code: `walletMakerChecker`, `walletStepUp`, `walletLimits`, `config/wallet`, the label "Kamai aur hisaab", the Play Store data-safety form and the Terms and Privacy pages (`docs/LEGAL_QUESTIONS.md` is the general list).
