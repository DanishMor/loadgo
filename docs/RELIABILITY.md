# Reliability tier (E34)

What customers see on an offer: **Reliable** or **Highly reliable**, or nothing. Never a number.

## Formula (the same in functions/src/trust.js and lib/core/trust/reliability.dart)
- Look at the driver's newest 100 finished trips: delivered, or cancelled by the driver.
- Fewer than 10 finished trips: no tier (new drivers are not marked down).
- completion = delivered / finished.
- on time = trips picked up on time / trips with a known pickup time (within an hour of the scheduled time, else on the pickup day). With fewer than 5 known, completion stands in.
- stars = average rating / 5. With fewer than 5 ratings, 0.9 stands in.
- score = 60 x completion + 25 x on time + 15 x stars, rounded (0 to 100).
- **Highly reliable** at 92 or more, **Reliable** at 82 or more, nothing below.

## Why these weights
Finishing the trip matters most to a customer; being on time next; stars last, because few trips are rated. The weights and cut-offs are first guesses for the pilot (UNVERIFIED) and are listed in OWNER_REVIEW.md to adjust after real trips.

## Where it comes from
The trust function (Server trip counts, flag serverTrust) writes `public_trust/{uid}.reliability` after each delivered trip. Clients cannot write it (firestore.rules). The app only shows it with the flag `reliabilityBadges` ON.
