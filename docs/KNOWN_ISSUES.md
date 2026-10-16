# Known issues and limits (F43)

Things that cannot be proved on the laptop, or that need a paid service or a contract. None of them breaks the app today: each has a fallback. `docs/BLOCKED.md` has the same items as "what is needed"; this file says **what a tester may notice**.

## Needs a real phone to prove

| Area | What may happen | Fallback / note |
|---|---|---|
| Screenshot block (`secureScreens`) | On some phones the block may not apply to the recent-apps thumbnail. | Test on 2 phones before relying on it. |
| Live location (`liveLocation`) | G11: the foreground service and consent check are written and tested with fakes. Not yet tried on a real phone for a long drive (battery saver on some makers may stop it); the customer then sees "Last seen N min ago". | Leave OFF until a real 1 hour test. |
| Fingerprint lock (`appLock`) | G7: the real prompt is plugged in through `local_auth` (`USE_BIOMETRIC`, MainActivity is a FlutterFragmentActivity). Not yet tried on a real phone: check that the prompt opens, that a wrong finger keeps the screen locked and that the Settings switch refuses when no lock is set. | Leave `appLock` OFF until tested on 2 phones. |
| Fresh SMS code (`walletStepUp`) | The code path is tested with fakes and rules; a real SMS needs billing and a real number. | Leave OFF until tested. |
| Push | Delivery depends on the phone maker (battery saver can delay or drop it). Tap routing is tested only with fakes. | The in-app notification list always has the message. |
| Camera and gallery | The system picker differs by phone; very large photos on weak phones may be slow to shrink. | Photos are cut to 1600 px and under 5 MB before sending. |
| Offline photo queue | Works with a saved file path only. On the web a photo that fails offline is not kept. | The card asks to try again. |
| Right-to-left and big fonts | Checked in widget tests (Urdu, 2.0x text, 360x640). Real phones with unusual fonts may differ. | Report with a screenshot. |
| Voice call | Needs two real phones; strict networks may need a TURN server. | Unchanged from before. |

## Needs a paid service or contract

| Area | State |
|---|---|
| Cloud Functions (41 functions) | Written and tested on the emulator; **not deployed**. Until then every server switch stays OFF and the app does the older thing on the phone. |
| Storage (photos) | Rules written and tested; the bucket needs the Blaze plan. |
| Online payment | G9: Razorpay server code (order, verify, webhook, refund, ledger lines) and the "Pay online" button are ready for **test keys** (the `razorpay_flutter` window is not yet tried on a real phone; the release build may need the plugin's keep rules if a build shows a missing class). No live money. Payouts stay manual with two admins. |
| KYC and GST check | Skeleton only; admin looks at the papers. |
| SMS to emergency contacts (MSG91) | Skeleton only. |
| Maps and road ETA | G10: the `mapsRoute` function (cached, limited per person and per day) and the trip map are written; need a Maps server key (secret) and an Android key (docs/MAPS_SETUP.md). The map picture itself is not tried on a real phone. Switch `maps` OFF: city table. |
| App Check | Not enabled; needs Play Integrity setup. |

## Limits of the design (by choice)

- **Server limits and trip code lock**: the trip code lock is enforced by the rules and works without functions. Hourly limits on bids, chat and codes are on the phone until `serverLimits` is deployed and ON.
- **Wallet history**: the hub shows the newest ledger lines; true paging needs a composite index (`firestore.indexes.json`) that the owner deploys.
- **Fake database in tests** does not serialise transactions the way real Firestore does; concurrency tests are written for the real behaviour but proved only on the emulator.
- **Admin web build**: a customer who signs in on the admin address sees "This account is not an admin" and can sign out; the customer sign-up pages are still reachable before sign-in.
- **Translations**: the new texts wait for the native reader (`docs/TRANSLATION_REVIEW.csv`). Kashmiri and some Indic joined letters in PDFs are drawn side by side by the PDF library.
- **Logo**: the mark is a placeholder until the designer delivers (`docs/LOGO_BRIEF.md`).

## If you find a new issue

Write the phone model, Android version, language, screen and what you did. Add it to `docs/BUG_REPORT.md`.
