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

## Counts

- Round 1 (this file's first version): FREE gaps = see "Free gaps" line below; PAID gaps = G3.7, G3.8, G4.12, G5.7, G7.7.

Free gaps: pending (tasks 41-57 close them)
