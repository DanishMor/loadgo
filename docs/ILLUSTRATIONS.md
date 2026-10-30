# Illustrations (E11)

All art is original and drawn in code: `lib/core/widgets/ds/illustrations.dart` (`IllustrationView`, `IllustrationPainter`). No image files, no third-party artwork, no stock. Test: `test/illustrations_test.dart`.

## Style (one family)
- 160 x 120 canvas, scaled; the view is always 4:3.
- Every picture stands on the same soft oval (`tint`) and ground shadow (`chip`).
- Outlines are 3 px Navy (`primary`), round caps and joins; fills are `surface` or `chip`.
- One warm accent per picture (`accentStrong`, or `accent` for a button-like dot). Status colours only where they mean status (error triangle, success tick, offline slash).
- Colours come only from the theme's `DsColors`, so each picture follows Classic, Signature and Midnight (the test fails on a raw colour).
- Decorative: `ExcludeSemantics`; the meaning is always in the text next to it.

## Set
| Kind | Where |
|---|---|
| `emptyBox` | empty lists |
| `noResults` | search with no match |
| `noNetwork` | offline |
| `error` | something went wrong |
| `success` | done |
| `noTrips` | no trips yet |
| `shield` | privacy, safety |
| `onboardPost` | onboarding slide 1 (post a load) |
| `onboardOffers` | onboarding slide 2 (offers arrive) |
| `onboardTrack` | onboarding slide 3 (follow the trip) |
| `noNotifications` | empty notification centre |

Vehicles are a separate painter (E16) in the same line style. Store icons and the splash logo are the only bitmaps (`assets/branding/`, see `docs/ICON_AND_SPLASH.md`).
