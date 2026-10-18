# UX research (U1)

Source: public product pages, store listings and help pages as remembered when this was written. No live fetch was done in this session, so every row below is marked **seen** (widely documented public behaviour) or **UNVERIFIED** (could not be confirmed here). Nothing is copied: only the pattern is used and Load 20 builds its own version.

## How a request reaches the driver, accept timeout, bidding

| Pattern | Seen in | What we take (original version) |
|---|---|---|
| One big "book" action on home, destination first | Uber, Rapido, Ola (seen) | One large "Truck book karo" button; three modes explained in one line each |
| Request goes to the nearest drivers first, then widens | Uber, Rapido, Ola (seen, exact radii UNVERIFIED) | Rings 3 / 7 / 15 km with delays 0 / 30 / 60 s, set in `config/dispatch` |
| Full-screen request card with a countdown, driver accepts or skips | Uber, Rapido (seen) | Incoming Load Card: route ribbon, fare, countdown ring (30 s), slide to accept |
| First valid accept wins | Uber, Rapido (seen) | Firestore transaction: open to matched, others see "someone else took it" |
| Rider proposes the price, drivers counter | inDrive (seen) | Bid mode: customer sees every bid, counters once, accepts one |
| Price shown as a fair range | Porter, WheelsEye (UNVERIFIED), inDrive (seen) | FareMeter bar with the usual range from `route_rates` (rateRange flag) |
| Pick a vehicle by capacity and typical price | Porter, WheelsEye, Vahak (seen) | Vehicle cards with capacity and a typical range |
| Load board browse with filters and saved routes | Vahak, BlackBuck (seen) | Loads feed with filters, saved routes, "why this matches" |
| Driver sees offer price, pickup distance, trip distance before accepting | Uber, Rapido, Porter (seen) | Same three numbers on the card |
| Auto-accept by rule | Uber driver "auto-accept" (UNVERIFIED), inDrive auto-accept (UNVERIFIED) | Customer rule: max price, min rating, verified only |
| OTP at pickup and delivery | Porter, Rapido (seen) | Big OTP cards (already built, restyled) |
| Share trip, SOS, check-in | Uber, Ola (seen) | Reuse trip share, SOS and safety check-in |
| Verified badge, rating, trip count on driver card | all (seen) | DriverMiniCard, plus trust card when `tripTrustCard` is ON |
| Slide to confirm for risky or final actions | Rapido, Uber Eats style (UNVERIFIED) | SlideToConfirm with a plain button fallback |
| Tip, rating, reorder after delivery | Uber, Porter (seen) | One-tap reorder and tip card on the delivery screen |

## Trust cues worth keeping
Verified mark, rating with count, finished trips, month joined (already in `public_trust`), vehicle number last 4 digits, "number hidden, call through the app".

## Not taken
Surge pricing, hidden fees, dark patterns on countdowns (the timer is real and shown plainly), any copied wording, logos or illustrations.
