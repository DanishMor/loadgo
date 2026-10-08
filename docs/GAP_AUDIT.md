# Gap audit (MASTER-2, Phase 1)

Method: code in `lib/`, `firestore.rules`, `android/`, `docs/ROADMAP_STATUS.md`, `docs/NEXT_TASKS.md`. Items already built are skipped. Each gap is FREE (Flutter + Auth + Firestore + Hosting/Crashlytics/Analytics/Remote Config + free packages) or PAID (needs a paid or manual-provider service; goes to `docs/PAID_UPGRADE_PLAN.md`, never built). Only FREE gaps get tasks. `Task` = TASK_QUEUE_3 task that closes it.

## 1. Customer journey
| ID | Gap | Type | Task |
|---|---|---|---|
| G1.1 | No way to share a load as a link or to WhatsApp (only plain text copy) | FREE | 43 |
| G1.2 | Driver phone is shown on the booking even before the driver is confirmed | FREE | 43 |
| G1.3 | No total trip cost preview (fare + toll + fuel hint) before posting | FREE | 45 |
| G1.4 | No goods value declaration (claims have no baseline) | FREE | 50 |
| G1.5 | Cancel has a charge but no structured reason list | FREE | 50 |
| G1.6 | No spending summary for the customer (month totals) | FREE | 49 |
| G1.7 | No in-app help assistant; user must read the FAQ or open a ticket | FREE | 47, 48 |
| G1.8 | No app-wide search (loads, bookings, tickets, places in one box) | FREE | 51 |
| G1.9 | No rating reminder after delivery if the user skipped it | FREE | 50 |
| G1.10 | No in-app feedback form (only tickets) | FREE | 50 |

## 2. Driver journey
| ID | Gap | Type | Task |
|---|---|---|---|
| G2.1 | No Simple Mode: big buttons, icons, little text for low-literacy drivers | FREE | 46 |
| G2.2 | No voice input for load search and bid amount (Hindi) | FREE | 46 |
| G2.3 | No daily/weekly earnings summary | FREE | 49 |
| G2.4 | Trip history has no status/date filters | FREE | 49 |
| G2.5 | No navigation hand-off to Google Maps for pickup and drop | FREE | 43 |
| G2.6 | No toll/fuel estimate to judge whether a bid is profitable | FREE | 45 |
| G2.7 | Payout request: screen exists, no clear "how much can I withdraw" line in simple words | FREE | 46 |
| G2.8 | Peak/night/festival demand is not reflected in the suggested fare | FREE | 44 |

## 3. Competitor features (Porter, Uber, Rapido, Vahak, BlackBuck, Lorry apps)
| ID | Gap | Type | Task |
|---|---|---|---|
| G3.1 | Surge pricing (peak/night/festival) | FREE | 44 |
| G3.2 | Share load on WhatsApp / link (Vahak, BlackBuck) | FREE | 43 |
| G3.3 | Navigation button (Rapido, Uber driver) | FREE | 43 |
| G3.4 | Toll + fuel estimate (BlackBuck) | FREE | 45 |
| G3.5 | Voice assistant / help bot (Porter) | FREE (rule based) | 47, 48 |
| G3.6 | Earnings dashboard (Uber, Rapido) | FREE | 49 |
| G3.7 | Live map, turn-by-turn, FASTag, insurance, live GPS tracking on a map | PAID | PAID_UPGRADE_PLAN |
| G3.8 | LLM assistant | PAID | PAID_UPGRADE_PLAN (`LATER(paid)` engine slot in Task 47) |

## 4. Production readiness
| ID | Gap | Type | Task |
|---|---|---|---|
| G4.1 | No crash reporting (only debugPrint) | FREE | 42 |
| G4.2 | No analytics events | FREE | 42 |
| G4.3 | No force update | FREE | 42 |
| G4.4 | No maintenance mode | FREE | 42 |
| G4.5 | No feature flags | FREE | 42 |
| G4.6 | Raw exception text can reach the user; no single friendly error mapper | FREE | 55 |
| G4.7 | Empty states are inconsistent across list screens | FREE | 55 |
| G4.8 | Slow network: no timeout + retry wrapper on one-shot reads | FREE | 55 |
| G4.9 | No admin system health screen | FREE | 52 |
| G4.10 | No admin support reply templates, bulk actions, user/booking export | FREE | 52 |
| G4.11 | No demo/seed data tool and no manual test plan | FREE | 53 |
| G4.12 | Server-side push, scheduled jobs | PAID | PAID_UPGRADE_PLAN |

## 5. Security and abuse
| ID | Gap | Type | Task |
|---|---|---|---|
| G5.1 | Promo, credits and referral are live by default (abuse surface); no admin switch | FREE | 41 |
| G5.2 | Credits `spend` and referral lines only partly guarded by an off switch in rules | FREE | 41 |
| G5.3 | Ratings: no per-booking cap beyond one per party (OK) but no admin review of rating bursts per user | FREE | 56 |
| G5.4 | Chat spam: 120 messages/hour cap exists; no repeated-identical-message guard | FREE | 56 |
| G5.5 | Bids: 60/hour cap exists; no guard against bids far outside the fare band (spam at 1 paise) | FREE | 56 |
| G5.6 | New collections of this plan (assistant log, feedback, app control) need rules + rules tests | FREE | 48, 50, 42 |
| G5.7 | Server-authoritative fare, payouts, notification fan-out | PAID | PAID_UPGRADE_PLAN |

Reviewed and fine: every collection in `firestore.rules` ends in the default-deny rule; rate limits, role lock, identity index, audit events and promo slots exist.

## 6. Cost control (Firestore reads/writes)
| ID | Gap | Type | Task |
|---|---|---|---|
| G6.1 | Reminder service ticks every minute and re-runs on every snapshot | FREE | 41 |
| G6.2 | Nearby loads opens up to 9 live geohash streams | FREE | 41 |
| G6.3 | Several one-shot config reads repeat each sign-in (no cache TTL) | FREE | 41 |
| G6.4 | Un-paged live streams on `watchMine`/`watchOpen` | FREE | 41 |

## 7. Play Store
| ID | Gap | Type | Task |
|---|---|---|---|
| G7.1 | App label is `transport_app`; applicationId is `com.example...` | FREE (label) / manual (id) | 54 |
| G7.2 | No PLAY_STORE_CHECKLIST, PRIVACY_POLICY, TERMS documents or Hosting steps | FREE | 54 |
| G7.3 | Policy text in the app is only 5 short clauses; needs the public URL setting | FREE | 54 |
| G7.4 | Account deletion link (web) for Play Console | FREE | 54 |
| G7.5 | Permission rationale text before location / notification permission | FREE | 54 |
| G7.6 | Data safety form answers not written down | FREE | 54 |
| G7.7 | Custom app icon and splash artwork | PAID/design (default Flutter icon) | PAID_UPGRADE_PLAN |

## 8. Quality
| ID | Gap | Type | Task |
|---|---|---|---|
| G8.1 | 360 px width and 1.3x font have a theme test, but no sweep over the new screens | FREE | 57 |
| G8.2 | Language QA test covers old tables; new tables need the same completeness check | FREE | 57 |
| G8.3 | Performance on old phones: large `ListView(children:)` lists build all rows | FREE | 57 |
| G8.4 | Dark mode contrast of new widgets | FREE | 57 |

## Round 2 (Phase 4 re-audit after Task 57)
| ID | Gap | Type | Task |
|---|---|---|---|
| G9.1 | Sahayak had no entry on the fleet home and the Simple Mode home; the engine offered fleet owners a post-load action | FREE | 58 |
| G9.2 | A tapped shared load link did not open the app (no intent filter), and there was no web page for people without the app | FREE | 59 |
| G9.3 | PAID_UPGRADE_PLAN had no rough cost per row | FREE (doc) | 59 |
| G9.4 | Verified App Links need `assetlinks.json` with the final application id and the signing key hash | manual (owner) | docs/PLAY_STORE_CHECKLIST.md |
| G9.5 | The older "Total earnings / This week" figures on the driver Earnings tab still use the rupee `EarningsSummary`, not `EarningsBreakdown` | FREE (cosmetic, same numbers for delivered trips with a fare) | left as is, noted |

## Round 3 (second re-audit)
Looked again at the eight angles after Tasks 58 and 59: no new FREE gap that is not either built, already listed in docs/NEXT_TASKS.md as paid or manual, or listed above as manual. G9.5 is the only open FREE item and changes no behaviour (both figures read the same delivered bookings), so it is not worth a task.

## Round 4 (MASTER-3, after Tasks 67 and 68, the feature map and the naming work)

Method: the same eight angles, read against the new code (`lib/fleet/`, `lib/core/transporter/`, `lib/core/comm/`, `lib/core/call/`, the new rules) and a real run of its queries against the emulator. `Task` = TASK_QUEUE_4 task that closes it.

| ID | Gap | Type | Task |
|---|---|---|---|
| G10.1 | The incoming-call listener and the "Download my data" queries would have been refused: the `calls` read rule used `uid in [callerId, calleeId]`, which fails for a query on one field (found by running the queries on the emulator) | FREE (bug) | 69 |
| G10.2 | An assigned driver could not move the trip: `advance` allowed only the booking holder; closing the load, notices and the vehicle were holder-only | FREE (bug) | 69 |
| G10.3 | The trip screen showed the assigned driver the payment, papers and cancel parts, which the rules refuse | FREE (bug) | 69 |
| G10.4 | Chat "other person" and its notice were wrong for the assigned driver and for the customer of a company booking | FREE (bug) | 69 |
| G10.5 | Nothing limited how often one person could ring another | FREE | 69 (rate limit `call`, 20 an hour) |
| G10.6 | Several new screens had never been checked at 360 px, 1.6x text, in Tamil, Telugu and Urdu; the check found 5 real overflows (a shared `StatusChip` could be wider than the screen) | FREE | 69 |
| G10.7 | Deleting an account while assigned to a trip, or holding company trips, was not blocked; the transporter's books were not deleted | FREE | 69 |
| G10.8 | The assigned driver was not told about a new trip; the transporter was not told about the driver's steps; a missed call left no trace | FREE | 70 |
| G10.9 | A customer could not see that a bidding transporter is "Verified" (only the transporter saw the badge) | FREE | 70 |
| G10.10 | The transporter's load list ignored the routes and vehicle types in the profile | FREE | 70 |
| G10.11 | Help and Sahayak did not explain why numbers are private, why a message was blocked, or what a Transporter is | FREE | 70 |
| G10.12 | "Download my data", the retention table and the Play data-safety answers did not mention the new records (violations, calls, books, memberships) | FREE | 70 |
| G10.13 | A mistyped translation key would show the raw key on screen and no test noticed (`tr(c, 'ok')` and `'done'` did not exist) | FREE | 70 (`translation_keys_test`) |
| G10.14 | The new analytics events (company bid, trip assigned, contact blocked, call started and connected) were missing | FREE | 70 |
| G10.15 | A real call between two phones, a TURN server, push to ring a closed app, masked numbers | PAID / device test | docs/BLOCKED.md |
| G10.16 | GST / PAN verification of a transporter | PAID (API) | docs/TRANSPORTER.md |
| G10.17 | Strikes and audit lines are written by the client, so a modified app can skip them | needs Cloud Functions | docs/SECURITY_REVIEW.md |
| G10.18 | The transporter had reminders for vehicle papers but not for the licences of their member drivers | FREE | 70 (the driver shares only the expiry date with the fleet; `fleet_members.licenceExpiry`) |

### Round 4, second look
After Tasks 69 and 70 the eight angles were read again, including the new Home entries, the admin screens and the generated hosting pages: no further FREE gap that is not built, listed above as paid / manual, or recorded in docs/SECURITY_REVIEW.md.

## Round 5 (MASTER-5: hardening, quality and small free gaps)

Method: the eight angles again, against the whole app instead of only the newest code, with a test or a measurement behind every claim (a static audit of the rules, a listener ratchet, an index check, a layout test of all 95 screens in four language / theme variants, contrast numbers, a generated rules matrix, a fuzz of every model reader). `Task` = MASTER-5 Phase A task that closes it.

| ID | Gap | Type | Task |
|---|---|---|---|
| G11.1 | Support tickets could be created without limit (the only unlimited create path with a free-text field) | FREE | 2 (`ticket` kind, 10 an hour) |
| G11.2 | An admin reassign could write a phone number into a booking both parties read | FREE | 4 |
| G11.3 | 14 admin writes left no audit event (vehicle, SOS, report, ticket, deletion request, rating flag, payout, promo, credits, referral bonus, pricing, offers, vehicle types, licence override) | FREE | 5 |
| G11.4 | LR share links stayed open after the owner deleted the account | FREE | 6 |
| G11.5 | Error samples, unanswered assistant questions and call records never expired | FREE | 7 (`expireAt` + a console TTL policy) |
| G11.6 | Privacy and Terms did not mention the automatic clean-up, the LR-link switch-off and the hourly limits | FREE | 8 |
| G11.7 | Six admin "all" lists had no limit | FREE | 9 |
| G11.8 | `config/support` was read on every use | FREE | 12 |
| G11.9 | Three Save buttons could write twice on a double tap | FREE | 16 |
| G11.10 | A revoked or expired session left the person on screens that only failed | FREE | 17 |
| G11.11 | A widget that failed to build showed the framework error box in a release build | FREE | 18 |
| G11.12 | A shared-load link meant for one session could open in the next one | FREE | 19 |
| G11.13 | Screens and pre-checks trusted the phone clock for expiry, schedule and grant checks | FREE | 20 (`ServerClock`) |
| G11.14 | Urdu and Kashmiri text was right to left but the layout stayed left to right | FREE (bug) | 24 |
| G11.15 | Real overflows at 360 px / 1.3x text: the first-time location consent and verification-pending screens (buttons could be pushed off screen), the shared empty state, the empty-trucks filter row, reply templates, My Loads and Recent headers, the driver plan row | FREE (bug) | 25, 26, 48 |
| G11.16 | Dark mode: the "online" chip had light text on a light green background | FREE (bug) | 25 |
| G11.17 | The light-mode hint colour was 2.6:1 against white; six icon-only buttons had no spoken label | FREE | 23 |
| G11.18 | No first-time guide per role | FREE | 27 |
| G11.19 | Notifications were one flat list; Mark all read stayed active with nothing unread | FREE | 29 |
| G11.20 | The Post Load form read as one very long page | FREE | 31 (three numbered steps) |
| G11.21 | The cancel dialog of an open load did not say there is no charge | FREE | 32 |
| G11.22 | No way to remove an abusive rating comment | FREE | 33 |
| G11.23 | A dispute showed claims and messages but not what the trip itself recorded | FREE | 34 |
| G11.24 | No earnings statement for drivers; no party statement for transporters | FREE | 35, 37 |
| G11.25 | The invoice PDF used a Latin-only font, Western digit grouping and no amount in words | FREE | 36 |
| G11.26 | Admin lists had no search, saved filters, paging or export; no pilot funnel; no announcement banner | FREE | 38, 39, 40 |
| G11.27 | The offers switches OFF path (promo, credits, referral) had no test | FREE | 41 |
| G11.28 | The Help centre showed the same eleven questions to everyone | FREE | 42 |
| G11.29 | The public token pages had no security headers; the Android app allowed cloud backup (saved LR copies live on the phone) | FREE | 49 |
| G11.30 | Opening Admin > Config > Support with no document started from the vehicle-types text | FREE (bug) | 40 |
| G11.31 | Release build signing still uses the debug key; `flutter build apk` needs the Android SDK | manual (owner) | docs/PLAY_STORE_CHECKLIST.md, docs/BLOCKED.md |
| G11.32 | Counters and audit lines are still written by the client; a modified app could skip them | needs Cloud Functions | docs/SECURITY_REVIEW.md |
| G11.33 | Per-user lists (bookings, offers, tickets, notifications ...) are still read without a limit; paging each needs a composite index | not a gap yet (a real account passes 300 documents), plan in docs/COST_WATCH.md | - |

### Round 5, second look
After the tasks were done the angles were read again (customer, driver, transporter, admin, bilty, chat and calls, cost, security, quality): the generated rules matrix, the fuzz of 80 model readers, the listener and index ratchets and the layout matrix found nothing more that is free and not built. One bug was found in the review of the round's own changes (the referral bonus had been cached for 15 minutes while the rules compare it with the server value; it is read fresh again, docs/BUG_REPORT.md).

## Counts

- Round 1: 60 gaps found, of which 55 FREE (closed by Tasks 41-57) and 5 PAID (G3.7, G3.8, G4.12, G5.7, G7.7; in docs/PAID_UPGRADE_PLAN.md).
- Round 2: 5 more gaps: 3 FREE closed by Tasks 58 and 59 (G9.1-G9.3), 1 manual for the owner (G9.4), 1 cosmetic left (G9.5).
- Round 4 (MASTER-3): 18 more gaps: 15 FREE closed by Tasks 69 and 70 (G10.1-G10.14 and G10.18), 3 paid, device-test or Cloud-Functions items recorded elsewhere (G10.15-G10.17).
- Round 5 (MASTER-5): 33 more: 30 FREE closed (G11.1-G11.30), 1 manual for the owner (G11.31), 1 needing Cloud Functions (G11.32), 1 not yet needed (G11.33).
- Total: 116 gaps, 103 FREE closed, 9 PAID or needing Functions, 2 manual, 1 cosmetic left open, 1 not yet needed.

Free gaps: 0 (every FREE gap is closed; G9.5 is cosmetic and recorded above)
Open bugs: 0 (free)
