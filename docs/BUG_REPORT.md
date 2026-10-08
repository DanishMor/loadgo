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

Method, three rounds. **Round 1**: every folder read as a reviewer (null and crash paths, wrong state, permission-denied against the rules, indexes, money, leaks, overflow), each class of defect also turned into a test so it cannot return: `model_fuzz_test` (every model reader gets an empty document and one with all keys null), `listener_audit_test`, `index_audit_test`, `state_audit_test`, `layout_all_screens_test` (95 screens x 4 variants), `rules_audit_test`, the generated rules matrix, `phone_privacy_test`. **Round 2**: every flow of docs/TEST_PLAN.md mapped to test code (`test_plan_map_test`). **Round 3**: docs/GAP_AUDIT.md read again (Round 5 there).

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
| M5-13 | phone clock | Expiry, schedule and grant pre-checks used the phone clock | review | low (rules always use server time) | `ServerClock` | `server_clock_test` |

## Checks that found nothing
* **Old documents**: 80 model readers (about 45 types, with and without all keys null) do not crash on a document from before a field existed.
* **Rules**: nothing is open to everyone; every create rule names who may create; signed-out access is closed everywhere except the two share-link tokens; a junk create or a foreign update / delete fails for customer, driver and transporter in every collection (129 generated tests). The only collection a signed-in person can list without a filter beyond the frozen list was `truck_posts`: by design.
* **Indexes**: every ordered query has its composite index; no index is declared twice.
* **Hosting pages**: every dynamic value is written as text (no attribute context); the two token pages now carry a content policy, no-store and the usual headers.
* **Money**: statements, books, invoices and the fare use integer paise; rupees are formatted from integers only.

## Could not be checked here
* `flutter build apk --debug` (no Android SDK, docs/BLOCKED.md); a real phone: OTP SMS, camera, GPS, calls on two networks, push, the PDF look on paper and in Tamil / Urdu (the PDF library does not shape every joined form).
