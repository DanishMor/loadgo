# Design upgrade spec (U3)

The last design round changed colours and fonts only. This round changes layout, booking flow and how a driver receives a load.

## Principles
1. One primary action per screen, at the bottom, in the thumb zone.
2. Targets at least 48 dp; main buttons 56 dp.
3. Little text. One short sentence per idea; Hindi first.
4. Progressive disclosure: advanced options (counter, rules, notes) behind a sheet.
5. Trust cues next to every price and every person: verified, rating, trips, hidden number.
6. Motion budget: one animation per screen, none with "remove animations" or Low-end mode.
7. Icon first for low-literacy drivers: every driver button has an icon and a verb; numbers are big.
8. Every screen has loading, empty, error and offline states.

## Signature elements (all original, in `core/widgets/ds`)
| Element | What it is |
|---|---|
| RouteRibbon | pickup dot, dashed line with a truck, drop pin, distance label; drawn with CustomPainter, works offline |
| FareMeter | horizontal bar for the usual price range, a marker for the estimate, a handle for the chosen price, hint text |
| CountdownRing | ring that empties over the accept window, number in the middle, colour changes in the last 10 s |
| SlideToConfirm | slide thumb to the end; haptic at the end; a plain button for screen readers and switch access |
| BidCard | driver mini card, price, ETA, tags (best price, nearest, top rated), accept and counter |
| StatusTimeline v2 | vertical steps with time stamps |

## Screen inventory
| Area | Before | After (uiV2 ON) |
|---|---|---|
| Customer home | list of buttons and tabs | big book action, mode line, recent routes, active trip, bottom nav Home, Trips, Help, Profile |
| Post load | one long form | 5-step wizard |
| Offers | list of offers | Bid Room with live cards |
| Tracking | status text | timeline, OTP cards, ribbon or map |
| Driver home | tabs and list | online switch, Radar, today, upcoming |
| Driver load | list tile | full-screen Incoming Load Card |
| Driver offers | list | Bid sheet and My bids with statuses |
| Admin | tables | same data in the kit's cards, plus dispatch monitor |

Old screens stay in the code and show when `uiV2` is OFF.
