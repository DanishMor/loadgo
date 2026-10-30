# Owner review: chosen new features (G3)

One page. Work does **not** wait for you; if you want something removed, write it in "Your changes" and it will be dropped or moved to later. Details: docs/NEW_FEATURES_PLAN.md. Evidence and UNVERIFIED marks: docs/COMPETITOR_MATRIX.md.

Every feature is OFF until you switch it on in Admin > Features. Nothing here needs a paid service unless marked.

**Safety and trust**
1. Trusted contacts get the trip link automatically.
2. Safety check-in when the truck stops long or leaves the route.
3. Driver, photo and truck plate card on the customer's trip screen.
4. ID-checked badge (works with admin review now; automatic KYC needs a partner, paid).

**Money (records now, online pay needs Blaze and gateway)**
5. Wait-time charge with a cap, both sides see it.
6. Advance and balance split on a booking.
7. Party khata (who owes whom), shareable PDF.
8. Payment hold until delivery proof (paid, after the payments work).
9. Freight rate range before you post or bid.

**Driver ease**
10. Preferred routes: matching loads first.
11. Load match score with reasons.
12. Document vault with expiry reminders; service reminders.

**Fleet**
13. Expense log and mileage.
14. Shareable business card for WhatsApp.
15. Multi-stop and part load (later in the order).

**Only documents or skeletons (partner needed)**: FASTag and fuel card, trip insurance quote, caller ID.

**Skipped**: driver loans (licence issue), lost item (the Report a problem button already covers it).

Your changes: _(write here)_

## E28b part loads (defaults to review before `partLoad` is switched on)
- Smallest share sold: 10% of the truck's load space (`minShare` 0.1).
- Largest part load: 70% (`maxShare` 0.7); above it the customer is told to book the whole truck.
- Handling margin: 15% over the plain share of a full-truck price (`handling` 0.15), capped at the full-truck price.
These are guesses for a first pilot, not market rates (UNVERIFIED). They live in code defaults and can be overridden by a config document once the flag is live.

## E34 reliability tier (check after the first weeks of trips)
- Weights 60 / 25 / 15 (completion, on time, stars), tiers at 92 and 82, at least 10 finished trips (docs/RELIABILITY.md). First guesses, UNVERIFIED.
