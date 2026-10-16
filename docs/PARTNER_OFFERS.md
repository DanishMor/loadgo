# Partner offers and later ideas (G25)

Things the competitor research found (docs/COMPETITOR_MATRIX.md) that need a **partner, a legal decision or a bigger design**. Nothing here is built; this note says why and what would be needed, so the decision is the owner's.

| Idea | Seen in | Why it waits | What it would take |
|---|---|---|---|
| **FASTag and fuel card** | BlackBuck (public pages) | A deal with a FASTag issuer or a fuel-card company; they pay a referral fee or sell the product. The app cannot do this alone. | Pick a partner; a "Partner offers" card (name, link, one-line benefit) in the transporter home behind a flag `partnerOffers`; **no personal data sent** unless the person taps and agrees; privacy policy and Play data-safety line for the link-out; a plain "this is an offer from a partner, not Load 20" label. |
| **Trip and cargo insurance quote** | BlackBuck (driver insurance, **UNVERIFIED** for cargo) | IRDAI rules for who may sell or refer insurance; an insurer or broker agreement. | Legal opinion first (docs/LEGAL_QUESTIONS.md); then an adapter like `EwayBillProvider` (quote request with load value and route only, no names); the customer sees a quote and buys on the partner's page. |
| **Caller ID card** (name, rating, badge when someone calls) | BlackBuck (public page) | Showing it on the phone's own call screen needs Android call-screening permissions that Play restricts heavily. | In-app only: the in-app call and chat screens already show the name. Not worth the Play risk; skipped. |
| **Part load** (share of a truck by weight) | Vahak (public page) | Needs matching of weight shares between several customers on one truck, a price split rule, a pickup order and proof for each customer. | Design first: a "part load" post with weight and cargo type, a truck's free capacity from the empty-trucks board, a booking per share, the driver's route with several pickups (the multi-stop code can carry it). Pilot data should show demand before building. |
| **Wait-time charge added to the bill** | Ride apps (**UNVERIFIED** for trucks) | `DetentionCard` records waiting time and the charge; adding it to the invoice needs the customer's consent and a change to the booking amount rules and the GST invoice. | A request from the driver with the time stamps, the customer taps accept or decline, an accepted charge becomes a line on the invoice. Needs a CA view on the tax treatment. |
| **Driver loans** | not researched | Lending rules; the licence issue noted in the plan. | Skipped. |
| **Instant payout to the driver's bank** | many apps | RazorpayX or similar business account, business KYC, fees. Payouts stay manual with two admins today (docs/PAID_UPGRADE_PLAN.md). | After the pilot shows payout volume. |

## Rule for any partner card

1. A switch (OFF), a label that names the partner, a link that opens outside the app.
2. No name, phone, load detail or location is sent before the person taps and agrees on a screen that says what is shared.
3. Added to the privacy policy and the Play data-safety form before it is switched on.
4. A cost note in docs/COST_WATCH.md if the app calls anything.
