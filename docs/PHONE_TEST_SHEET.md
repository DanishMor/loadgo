# Phone test sheet (G45)

Test on **two real Android phones** (one cheap phone with 2 GB RAM if you have it), after the owner steps in `docs/GO_LIVE_RUNBOOK.md`. Test only the rows of switches that are ON. Mark Pass or Fail, write the phone model and a screenshot for every Fail in `docs/BUG_REPORT.md`.

Phone A: ______  Android ____    Phone B: ______  Android ____    Date: ______    Tester: ______

## Always (switches as shipped)

| # | Screen | What to press | What you must see | Pass / Fail |
|---|---|---|---|---|
| 1 | Login | enter phone, then the SMS code | signed in; 5 wrong codes lock for 15 minutes | |
| 2 | Customer > Post a load | Delhi to Jaipur, 20 ft | fare estimate shows; load appears in the list | |
| 3 | Driver > Loads | open the load, make an offer | the customer sees the offer | |
| 4 | Customer > Offers | select the offer, driver confirms | booking with a trip code | |
| 5 | Driver trip | enter the pickup code (try a wrong one 5 times) | wrong codes lock after 5; the right one moves the trip on | |
| 6 | Settings | language Hindi, Urdu, biggest font, dark mode | no cut-off text, Urdu runs right to left | |
| 7 | Low-end mode | switch it on in Settings | animations off, nothing cut off | |

## Per switch

| # | Switch | Screen | What to press | What you must see | Pass / Fail |
|---|---|---|---|---|---|
| 8 | `pushNotifications` | any | close the app, have the other phone make an offer | push arrives; tap opens that load | |
| 9 | `photoUploads` | Driver profile > licence | take a photo on mobile data, then one with the network off | uploads; the offline one waits and sends later | |
| 10 | `maps` | Customer > Post a load | type Delhi and Jaipur, stop typing | after about a second the km changes to the road figure (about 280); switch OFF returns the city table | |
| 11 | `maps` | Customer > trip screen | Show on map | pickup, drop and the driver's marker; blank map = key or SHA wrong | |
| 12 | `liveLocation` | Driver trip (in transit) | accept the location consent; lock the screen; drive 1 hour | notification "Load 20 is sharing your trip location" stays; customer sees "Last seen" within 5 minutes; note battery % | |
| 13 | `liveLocation` | Driver > deliver the trip | finish the trip | notification disappears; customer's last-seen disappears the next day | |
| 14 | `paymentGateway` (test keys) | Customer > payment card | Pay online with the Razorpay test card / UPI | "Payment received"; booking shows paid; admin sees `paid` | |
| 15 | `payHold` | same | pay before delivery | card says "Held safely ... when the trip is delivered"; no money line for the driver; after delivery the driver's earnings show it | |
| 16 | `paymentGateway` | Admin > refund | refund part of it | order shows the refunded amount | |
| 17 | `smsGateway` | notifications off on the customer phone | accept a booking | one SMS arrives (not two); with push on, none | |
| 18 | `smsGateway` | Profile > Emergency contacts, then SOS | press SOS | the saved contact gets one SMS; support sees the alert | |
| 19 | `safetyCheckin` | Driver trip | stand still 30 minutes (or ask for a short test setting) | "Are you OK?" card; tap "I'm OK" thanks; leave one unanswered for 10 minutes, support gets an alert | |
| 20 | `tripTrustCard` | Customer > offers | open an offer from a driver with trips | verified, stars, trips, since | |
| 21 | `rateRange` | Customer > Post a load | a route with 5 or more finished trips | "Usual price on this route: ..." | |
| 22 | `khata` | Profile > Party khata | add a party, "They owe me" 15000, "They paid" 5000, share, delete a line | balance 10,000; text statement opens in WhatsApp; delete corrects the balance | |
| 23 | `bizCard` | Driver / transporter Profile > business card | Share on WhatsApp, with and without the phone switch | picture arrives; phone number only when the switch was on | |
| 24 | `appLock` | Settings > fingerprint lock, then Earnings | open Earnings | the phone's own prompt; wrong finger stays locked | |
| 25 | `kycVerify` (sandbox) | Driver > save papers | the admin opens Verification | chips show the sandbox answers or "No automatic ID check yet" | |

## After

- [ ] Every Fail is written in `docs/BUG_REPORT.md` with phone model, Android version, language and screen.
- [ ] Any switch that failed is turned OFF again (Admin > Features) until fixed.
- [ ] Battery and heat noted for row 12.
