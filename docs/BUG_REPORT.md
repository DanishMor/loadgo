# Bug report (MASTER-3, Phase 6)

Method: read the new code of Phases 1-5 against the rules (permission-denied), the indexes (queries), the crash paths (null, old documents, offline), abuse (chat, strike, transporter, role) and the money logic; then ran what could be run: the whole rules suite, the whole Flutter suite, `flutter build web`, and a one-story end-to-end test. Each row says what was wrong, how it was found and the test that keeps it fixed.

| # | Found in | Problem | How found | Fix | Test |
|---|---|---|---|---|---|
| 1 | rules `calls` | The read rule used `uid in [callerId, calleeId]`. A query on one field (`where calleeId == me and status == ringing`, and the "Download my data" queries) hit an undefined element and was refused, so **no call would ever have rung** | writing the real list queries as rules tests | `callerId == uid \|\| calleeId == uid` | rules "the queries of Download my data are allowed for the owner" |
| 2 | `BookingService.advance` | Only the booking holder could advance; the **assigned driver** got "Only the assigned driver can update this booking"; closing the load, the vehicle and the notices were holder-only in the rules too | review of the assign flow | holder or assigned driver; `loads` close and notices allowed for the assigned driver; the vehicle is freed by the transporter's app (`releaseFinished`) | task69 "the assigned driver runs the trip", rules "the assigned driver runs the whole trip including delivery" |
| 3 | `DriverTripScreen` | An assigned driver saw payment, e-way bill, evidence, claim and cancel controls that the rules refuse | review | those parts only for the booking holder | task69 "the trip screen of an assigned driver has no payment card" |
| 4 | `ChatService.otherParty` | For the assigned driver it returned the transporter, and for the customer of a company booking the transporter instead of the driver; the notice went to the wrong person | review | customer -> running driver; everyone else -> customer | task69 "chat with a company booking" |
| 5 | rules `calls` | No limit: one person could ring another without end | abuse review | `rate_limits` kind `call`, 20 an hour (`rateBumped`) | rules "at most 20 calls an hour" |
| 6 | `AccountDeletionService.activeTripCount` | Ignored trips where the person is the assigned driver or holds a company booking | review | counts `assignedDriverId` and `fleetOwnerId` too; the transporter's books are deleted | task69 + export test |
| 7 | `StatusChip` and 6 new screens | A chip wider than the screen, a title Row without `Expanded`, a non-scrolling call screen: overflow at 360 px / 1.6x text (Tamil, Telugu, Urdu) | new `test/layout_new_screens_test.dart` (7 screens x 4 languages x light and dark) | chips wrap, rows use `Expanded`, call screen scrolls, the shortcuts scroll inside the dashboard | layout_new_screens_test |
| 8 | WebRTC provider | Candidates found right after the offer were lost (broadcast stream with no listener yet); `close()` could wait forever on a stream nobody listens to | writing the call-controller test with a fake provider | single-subscription streams that buffer; `unawaited` close | task68 "ring, answer, connect, hang up" |
| 9 | `CallController` | Hang up and "no answer" were reported as "the other side hung up" because our own status change came back through the listener; two overlapping finishes crashed with a list modified during iteration | tests | `_endingHere` and `_finishing` guards | task68 "declined, cancelled and unanswered" |
| 10 | `T.data` / codemod | Making the name a `{app}` token also rewrote the translation key `gsLoadGone` (it contains "LoadGo") | full test run | key renamed `gsLoadUnavailable`; naming test refuses a table that holds the name | naming_test |
| 11 | 3 string keys | `tr(c, 'ok')` and `'done'` had no translation (raw key on screen) | new `translation_keys_test.dart` | `pcOk`, `pcDone` | translation_keys_test |
| 12 | `TransporterShortcuts` | The attached-vehicle stream could block forever offline | review of crash paths | 8 second timeout, own vehicles still shown | covered by dashboard layout test |
| 13 | `CallController.myDisplayName` | Threw when offline, so the Call button did nothing | review | returns '' | covered |
| 14 | rules load create | The rule was at the 1000-expression limit; adding the `postedByRole` check broke a promo test | full rules run | removed the duplicated `validPromoShape` call | rules suite slice 1 |

## Checks that found nothing

* **Indexes**: every new query is a single field or equality-only (`calls` with two equalities merges single-field indexes; `violations` orders one field). `firestore.indexes.json` did not change.
* **Role lock and identity**: `role`, `selectedRole`, `fleetOwnerId`, `riskTier`, `plan`, `verified`, chat fields and wallet lines are frozen for the owner (22 rules tests).
* **Money**: books, rupee parsing and margins are integer paise with a 10 lakh limit in code and rules; negative margin allowed; party dues never negative.
* **Old documents**: a booking, vehicle, offer, user and call document without the new fields read with safe defaults.

## Could not be checked here

* `flutter build apk --debug`: no Android SDK in this environment (docs/BLOCKED.md). `flutter build web` passes with flutter_webrtc.
* A real call between two phones on different networks.

## Final numbers of this phase

See docs/PROGRESS.md for the last full run (analyze, Flutter tests, rules tests).


---

# Bug report (MASTER-5, Phase B)

Method, three rounds. **Round 1**: not a line-by-line read of every file; each class of defect (null and crash paths, wrong state, permission-denied against the rules, indexes, money, leaks, overflow) was searched across all of `lib/` with scans and tests, the code changed in this round was read against the rules, and the classes were turned into tests so they cannot return: `model_fuzz_test` (every model reader gets an empty document and one with all keys null), `listener_audit_test`, `index_audit_test`, `state_audit_test`, `layout_all_screens_test` (95 screens x 4 variants), `rules_audit_test`, the generated rules matrix, `phone_privacy_test`. **Round 2**: every flow of docs/TEST_PLAN.md mapped to test code (`test_plan_map_test`). **Round 3**: docs/GAP_AUDIT.md read again (Round 5 there).

| # | Found in | Problem | How found | Severity | Fix | Test |
|---|---|---|---|---|---|---|
| M5-1 | `DriverConsentScreen`, `DriverPendingScreen` | At 360 px and 1.3x text the content pushed the buttons off the screen (a first-time driver could not tap Allow / Skip / Refresh) | layout matrix | high (blocks onboarding) | content scrolls above fixed buttons | `layout_all_screens_test` |
| M5-2 | `EmptyState` (shared) | Overflowed when the space left was small (a filter row above it, big text) | layout matrix | medium | it scrolls | same |
| M5-3 | Empty-trucks board, reply templates, My Loads, Recent, driver plan row | Rows with a text and a button side by side overflowed in Tamil / Urdu at 1.3x | layout matrix (Tamil, Urdu) | medium | Wrap / Expanded | same |
| M5-4 | `DriverHomeScreen` online chip | Light text on a light green background in dark mode | review of hard-coded colours | medium | `AppColors.successBg` | `accessibility_test` |
| M5-5 | whole app | Urdu and Kashmiri were never laid out right to left | review | medium | `Directionality` from the language | `rtl_test`, layout matrix with `lang.textDirection` |
| M5-6 | `RewardsService.referralBonus` (my own Task 12 change) | Cached for 15 minutes, but the rules compare the credit with the server value: a credit within 15 minutes of an admin change would be refused | review of code against rules | medium | read fresh, with a comment | `offers_off_test` |
| M5-7 | `NotificationsScreen` (my own Task 29 change) | Mark all read stayed disabled / stale because it read a list that changes inside the stream | full test run | low | a notifier updated after the frame | `notification_test` |
| M5-8 | rules `bookings` admin reassign | Could write `driverPhone` into a booking both parties read | privacy review | medium | must be empty | rules test, `phone_privacy_test` |
| M5-9 | `ConfigEditorScreen` | Opening Support with no document started from the vehicle-types text; saving would have written `types` into `config/support` | adding the announcement editor | low | a default per document | `announcement_test` |
| M5-10 | `AccountDeletionService` | LR share links stayed live after the owner deleted the account | task 6 review | medium | revoked before the profile goes | `e2e/deletion_roles_e2e_test` |
| M5-11 | 14 admin write paths | No audit event | audit of admin writes | medium | `_audited` / batch with `user_action` or `config_change` | `admin_audit_test` |
| M5-12 | tests | Lazy lists (`ListView`) hid rows beyond the first screen, so three old tests failed once the Help list grew to 18 questions | full test run | test only | scroll until the row exists | `help_roles_test`, `task50_test`, `task69_test` |
| M5-14 | `RateLimit.prepare` (since Task 2 of an earlier master) | The hourly counter decides "window over or not" with the phone clock but the rules decide with the server clock. A phone a few minutes or hours wrong sends a count the rules refuse: posting, bidding, messaging or opening a ticket failed with a generic error until the real hour passed | review of every `DateTime.now()` that is compared with a server timestamp (102 uses) | high for those phones | `ServerClock` (learned from the device record at sign-in and start, and from chat acknowledgements) is used here and in the cancel charge, waiting minutes, chat blocks and the Ladder | `server_clock_test` (rate limit with a phone 3 hours ahead) |
| M5-15 | `ContactFilter` | The UPI pattern grew with the square of the text: a 20,000-character paste of letters and digits took 11 seconds (the chat limit of 500 characters hides it, but the filter is a shared function) | random and adversarial input test | low (a frozen phone on a pasted wall of text) | only the first and last 3,000 characters are scanned | `input_fuzz_test` (9 adversarial strings under 3 seconds in all) |
| M5-13 | phone clock | Expiry, schedule and grant pre-checks used the phone clock | review | low (rules always use server time) | `ServerClock` | `server_clock_test` |

## Checks that found nothing
* **Old documents**: 80 model readers (about 45 types, with and without all keys null) do not crash on a document from before a field existed.
* **Rules**: nothing is open to everyone; every create rule names who may create; signed-out access is closed everywhere except the two share-link tokens; a junk create or a foreign update / delete fails for customer, driver and transporter in every collection (129 generated tests). The only collection a signed-in person can list without a filter beyond the frozen list was `truck_posts`: by design.
* **Indexes**: every ordered query has its composite index; no index is declared twice.
* **Hosting pages**: every dynamic value is written as text (no attribute context); the two token pages now carry a content policy, no-store and the usual headers.
* **Money**: statements, books, invoices and the fare use integer paise; rupees are formatted from integers only.

## Could not be checked here
* `flutter build apk --debug` (no Android SDK, docs/BLOCKED.md); a real phone: OTP SMS, camera, GPS, calls on two networks, push, the PDF look on paper and in Tamil / Urdu (the PDF library does not shape every joined form).

## MASTER-6 (2026-10-09)

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| M6-B1 | lib/admin/admin_pilot_funnel_screen.dart, lib/fleet/transporter_shortcuts.dart | `setState(() => _x = someFuture)` returns the Future from the closure: Flutter asserts in debug builds and the refresh did not rebuild in tests | block body `setState(() { _x = ...; })` | Low (release builds ignore the assertion) |
| M6-B2 | lib/admin/admin_lists.dart, lib/auth/driver_onboarding_card.dart | same `setState(() => _x = future)` pattern as M6-B1 | block body; test/setstate_future_guard_test.dart guards it | Low |

## Windows laptop and Master-7 prep (2026-10-11)

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| W-B1 | android/app/build.gradle.kts | `java.util.Properties()` did not resolve (Gradle's `java` extension shadows the package): the Android build failed at script compile | `import java.util.Properties` | High on Windows/Gradle 9 (no APK) |
| W-B2 | android/gradle.properties | `-Xmx1024m` gave "Java heap space" on the first build | `-Xmx4g` (16 GB laptop) | High (no APK) |
| W-B3 | android/app/proguard-rules.pro | R8 release build failed: missing `com.google.android.play.core.*` (Flutter deferred components, not used) | `-dontwarn com.google.android.play.core.**` | High (no release APK) |
| W-B4 | 5 source-scan tests, tool/apply_app_info.dart | Windows `\` paths and CRLF made 6 tests fail | paths normalised to `/`; CRLF ignored in the app_info check | Low (tests only) |
| W-B5 | firestore_rules_test/run-tests.sh | `VAR=x cmd` inside `emulators:exec` fails on Windows cmd.exe; script was CRLF | env set outside `emulators:exec`; `*.sh` kept LF | Low (tests only) |
| W-B6 | tool/rename_app.ps1 (first draft) | a `[string]` param turned the boolean into a truthy string so the apply step never wrote | separate `$isDry` | Low (caught in P1 testing) |
| P9-B1 | lib/core/pricing/fare_calculator.dart `MoversDetails.parseItems` | an item name ending in x or X lost its last letter when a quantity followed: "box 10" became "bo" x 10 ("Max 4" became "Ma") | the quantity separator needs a space or `*` (`^(.*?)(?:(?:\s+[xX]?|\s*\*)\s*(\d+))?$`); test/pure_logic_gaps_test.dart | Medium (wrong item names in a movers quote) |

| L18-B1 | lib/core/settings/onboarding_screen.dart | the Next button called PageController.nextPage with Duration.zero when animations are off (system setting or Low-end mode): an assertion in debug, undefined movement in release | jumpToPage when the duration is zero | Medium (Low-end phones, first run) |

## Part 2 bug hunt (F1 to F46), 2026-10-16

The new code was read like a reviewer: null and crash paths, `permission-denied` against the rules, missing indexes, wrong paise, leaks, overflow, dark-mode contrast, right-to-left, abuse, races.

### Round 1

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P2-B1 | storage.rules | trip evidence (pickup, delivery, pod, damage) could be overwritten by `create` on an existing file in the emulator: the test "evidence is not overwritten" failed | `create` now needs `resource == null` | High (evidence could be replaced) |
| P2-B2 | lib/admin/admin_uploads.dart, lib/core/documents/pod_screen.dart | the Firestore stream was built inside `build`, so every rebuild subscribed again (extra reads, flicker) | stream created once in `State` | Medium (cost) |
| P2-B3 | lib/core/photos/photo_widgets.dart, lib/main.dart | the offline photo queue was never sent: nothing called the flush | `PhotoSync` starts at app start, runs when the phone is online again and after sign-in, one run at a time (no duplicates); `test/photo_sync_test.dart` | High (photos lost silently) |
| P2-B4 | lib/core/bilty/lr_send_screen.dart | the LR PDF could print a proof photo but no caller passed one | `PhotoService.proofImage` (signed proof first, then the delivery photo; null on any problem) passed for non-driver copies of a delivered trip | Medium (F31 not really done) |
| P2-B5 | lib/admin/admin_web_shell.dart | the page and the guard under it each listened to "is admin?" and could disagree for one frame; the guard then asked a navigator that does not exist in this build to close | one listener in `_AdminGate`, the guard gets the same answer | Low |
| P2-B6 | firestore.indexes.json | the chat scan reads one chat by `senderId` and `createdAt`: only a collection-group index existed. The emulator does not ask for indexes, real Firestore would fail the function and retry | collection-scope index on `messages` added; `test/function_indexes_test.dart` lists every index the functions need | High on deploy (scan never works) |
| P2-B7 | functions/integration/functions.test.js | the limits test assumed the 6th load is the one removed; which one goes depends on trigger order | the test checks the count (5 left) and the single audit line | Low (test only) |

### Round 2

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P2-B8 | lib/main.dart, lib/core/notifications/push_router.dart | `PushRouter.start` ran before `Firebase.initializeApp`: `FirebaseMessaging.instance` threw, the error was swallowed and tapping a push never opened the right screen | started after Firebase; a failed start can be tried again; `test/main_order_test.dart` | High (push taps dead) |
| P2-B9 | lib/core/photos/photo_service.dart | the queue flush saved the list it read at the start: a photo added while others were being sent was lost | only the handled photos are removed from the list as it is then; reads and writes run one after the other; tests in `test/photo_sync_test.dart` | Medium |
| P2-B10 | lib/core/photos/photo_service.dart | a queued photo had no owner: after a second person signed in on the same phone it would have been uploaded into the second person's papers | every queued photo stores its uid; only that account sends it | High (papers in the wrong account) |
| P2-B11 | lib/core/photos/photo_widgets.dart | pictures of papers stayed in the picker cache after sending, and in memory after sign-out | the cache copy is deleted after the upload (only inside the temporary folder, never a person's own photo); the in-memory pictures are cleared on sign-out | Medium (privacy) |
| P2-B12 | functions/src/razorpay.js | pressing Pay again made a new Razorpay order every time | an unpaid order of the same amount from the last 30 minutes is given back | Low (clutter) |
| P2-B13 | functions/src/razorpay.js | an unused `catch (_)` variable failed the lint | `catch {` | Low |

### Round 3

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P2-B14 | lib/driver/vehicle_documents_screen.dart | the screen offered photos for insurance, PUC, fitness and permit but not for the RC | RC photo added at the top; `photo_service_test` checks every paper kind is a photo kind (the screen looks it up by name) | Low |
| P2-B15 | lib/core/bilty/lr_pdf.dart, lib/core/services/trip_evidence_service.dart | the receiver's signature (strokes) was never printed on the LR/POD PDF although F31 asks for it | strokes drawn on the PDF next to the proof photo; out-of-range points are clamped; an empty signature prints nothing; `test/pod_photos_test.dart` | Medium |
| P2-B16 | lib/main.dart | pictures of papers kept in memory after sign-out | cleared when the sign-in ends | Low (privacy) |

After round 3 the angles (null and crash paths, `permission-denied` against rules, indexes, paise, leaks, overflow, dark mode, right-to-left, abuse, races) were read once more over `functions/`, `storage.rules`, `lib/core/photos`, `lib/admin`, `lib/core/adapters`: nothing new. Free bugs open: 0.

## Part 3 (G38, 2026-10-17)

### Round 1 (new code of G7 to G25)

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P3-B1 | lib/main.dart, lib/core/location/live_location_sharer.dart | the live trip location was documented to stop at sign-out but nothing stopped it: a second person signing in on the same phone could have the first person's trip position written under the old booking | `LiveLocationSharer.stop()` in the signed-out branch; `test/g38_guards_test.dart` keeps it | Medium (privacy) |
| P3-B2 | android/app/src/main/AndroidManifest.xml | Analytics' automatic events (first open, screen views) were collected before the person agreed, although the analytics switch defaults to off: the consent only gated our own events | `firebase_analytics_collection_enabled=false` in the manifest; `setConsent(true)` turns it on | Medium (privacy, DPDP) |
| P3-B3 | functions/src/sms.js | a made-up notification addressed to someone else could cost them an SMS (a notification is a document any signed-in person can create for another); the daily cap limited the damage but not the annoyance | the SMS goes out only when the notification names a booking of which the person is the customer; emulator test with three variants | Medium (abuse, cost) |
| P3-B4 | functions/src/razorpay.js | the commission share of a refund was `commission x refund x 2` in a plain number: above 2^53 for a big order (about 1 crore rupees) it rounds wrongly; many small refunds also drifted by a paisa each | BigInt arithmetic, and the share is taken from the running total so pieces add up exactly | Medium (money maths) |
| P3-B5 | functions/src/razorpay.js | a refund call that died half way left a reservation that blocked later refunds for ever | a reservation older than 5 minutes stops blocking (stale test) | Low |
| P3-B6 | docs/COST_WATCH.md | the Maps cost note of G10 had been lost by a bad edit (the test for schedules did not catch it, it is a callable) | restored; `test/cost_guards_test.dart` now fails when a paid call has no note | Low |

### Round 2 (screens: overflow, dark mode, right-to-left, accessibility)

`test/part3_layout_test.dart` draws every new screen (trust card, usual-price line, check-in, held payment, khata list and party, business card) at 360 x 640 with 2.0x text in English, Hindi, Tamil, Telugu, Kannada, Urdu and Kashmiri, light and dark, then with the low-end switch on, then checks 48 dp targets, spoken labels and contrast. 108 cases pass.

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P3-B7 | lib/driver/safety_checkin_card.dart | the card's text took the theme colour while its card took the palette colour: in dark mode the contrast could drop (found as 1.12:1 in the test, which had not set the palette the way the app builder does) | text colours come from the same palette as the card (`AppColors.title`); the test sets `AppPalette.current` like `main.dart` | Low |

### Round 3 (abuse, money, missing indexes, races)

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P3-B8 | functions/index.js, functions/src/razorpay.js | a booking cancelled while an online payment was held left the money with no trace for finance | the cancel is noted in the audit trail (`hold_cancelled_<booking>`, once) so finance finds it and refunds with `paymentRefund`; emulator test | Medium (money) |

Checked and found fine (no change): indexes (new queries are one range on one field, or equality on one or two fields: `locationUpdatedAt <`, `paymentId ==`, `bookingId == and status ==`); a replayed webhook (event id claimed once); two refunds at once (reservation); verify then webhook (one settle step); an amount that differs from the order (flagged `mismatch`, never paid); Aadhaar (only four digits accepted, nothing looked up); KYC answer forgery (separate collection, no client write); a pay-order flood (daily quota); kill switches (every paid call has a switch, a quota, the App Check guard and a cost note, `test/cost_guards_test.dart`).

Known and accepted: a person can still find out, with the partner switched on, whether a licence number exists in the government record (6 checks a day per person, 300 in total).

### Round 4 (G41, caught by the existing performance guard)

| ID | File | What was wrong | Fix | Severity |
|---|---|---|---|---|
| P3-B9 | lib/core/khata/khata_screens.dart | the party list (up to 100) and the line list (hundreds) were `ListView(children: [for ...])`, which builds every row at once | `ListView.builder` with the totals as row 0 and the note as the last row; `test/performance_guard_test.dart` found it | Low (speed on cheap phones) |
