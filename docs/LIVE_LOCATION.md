# Live trip location (G11)

Switch: `liveLocation` (Admin > Features > Live trip location), OFF by default. With it OFF the older behaviour stays: the position is shared only while the driver's trip screen is open.

## What happens when it is ON

1. The driver opens the trip (on the way to pickup or in transit). The app checks **two things**: the driver's own location consent (Settings, asked once on first start) and the phone permission. If either is missing it says which one and shares nothing.
2. Sharing runs as an Android **foreground service**: a visible notification "Load 20 is sharing your trip location" stays while it runs, so the driver always knows and it is not killed when the screen goes off.
3. Writes are limited (`config/liveLocation`, bounded values): at least 30 seconds apart, only after the truck moved 100 m, and a heartbeat every 5 minutes even when parked. A normal day trip is therefore a few hundred writes, not thousands.
4. It stops by itself when the trip is delivered or cancelled, when the driver signs out, or when the driver turns the consent off.
5. The customer sees the position on the trip map when `maps` is ON, otherwise "Last seen 5 min ago" (no coordinates). Only the customer of that trip (and admins in a dispute) can read the booking.
6. **Retention**: the server job `jobClearLocations` (daily 04:30 India time, behind `serverJobs`) removes `lastKnownLocation` and `locationUpdatedAt` from a delivered or cancelled booking 24 hours after the last position. Until the functions are deployed the position stays on the booking (see DATA_RETENTION.md).

## Privacy notes (for the privacy policy and the Play data-safety form)

- Collected: approximate and precise location of the driver, only during a trip, only with consent.
- Used for: showing the customer where the truck is; the arrival alert; safety (SOS shares the last position).
- Shared with: the customer of that trip. Not sold, not used for advertising.
- Deleted: 24 hours after the trip ends (server job), at once when the account is deleted.
- No background location permission is requested (the service starts while the app is on the screen).

## Battery notes

- GPS with a 50 m distance filter plus the 30 s gap: the phone is not woken for every metre.
- The foreground notification is required by Android; it is the cost of keeping the service alive.
- A phone with aggressive battery saving (some makers) may still stop it; the customer then sees "Last seen N min ago" instead of a wrong position.
- Test on 2 phones during a real 1 hour drive before relying on it (docs/KNOWN_ISSUES.md).

## Cost

Firestore writes: about 12 to 120 per hour of driving (gap and move rules). Reads: the customer's open trip screen follows the booking document. See docs/COST_WATCH.md.
