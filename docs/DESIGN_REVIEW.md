# Design review (E13)

How: `powershell -File tool/render_gallery.ps1` draws the key screens with the real bundled fonts into `build/gallery`
(not committed). The review set is 7 screens (customer home, tracking, driver feed, driver trip, earnings, settings,
admin home) x {Signature, Midnight, Classic in English; Signature in Hindi, Tamil, Urdu; small phone 320x568 at 1.3x
in Hindi Midnight and English Classic} = 56 images. `-Full` draws every screen x look x size x 12 languages.
Layout errors found while drawing go to `build/gallery/problems.txt`, and the run fails if there are any.

Each image was checked for spacing rhythm (4/8 grid), alignment, cut or overlapping text, RTL mirroring and contrast.

## Round 1 (2026-10-30)

| # | Screen / look | Before | After | State |
|---|---|---|---|---|
| R1 | Customer home hero, Midnight | Title, subtitle and mode lines drawn in `onPrimary` (near black in Midnight) on the navy gradient: about 1.6:1, unreadable | `DsHero.on` (white) on the gradient in every look; test: 4.5:1 or more on both gradient stops (design_tokens_test) | fixed |
| R2 | Driver home v2 hero (online), Midnight and Classic dark | Same: dark text and radar line on navy | White while online; `onPrimary` on the grey offline card | fixed |
| R3 | Earnings v2 "Today" card, Midnight | Same: dark amount on navy | White | fixed |
| R4 | Driver feed card, tracking, many older screens; Signature and Midnight | Accept button, distance line, price and some icons use `AppColors.primary`, the fixed Classic blue (102 uses), so the Signature navy / Midnight gold looks are mixed with Classic blue | Theme-following primary for the new looks; Classic unchanged (E13b) | E13b |
| R5 | Driver trip title, feed card ("Pune -> Mumbai"), home greeting | U+2192 arrow and the wave emoji draw as a box in the render | None of the bundled fonts carries them; on Android the system font (Roboto, Noto Color Emoji) draws them. A render-only artefact, accepted (DECISIONS.md) | accepted |
| R6 | Driver feed filter chips | Last chip is cut at the right edge | It is a horizontal scroll row; the cut is the scroll cue | no change |
| R7 | Urdu tracking | Mirrored correctly: route, OTP card, timeline dots on the right | - | clean |
| R8 | Hindi settings, small phone 1.3x | Two-line subtitles wrap cleanly, switches stay aligned on the right | - | clean |

Layout errors in the 56 images: none (problems.txt).

## Round 2 (2026-10-30, after E13b)

| # | Before | After | State |
|---|---|---|---|
| R4 | `AppColors.primary` was the fixed Classic blue on 102 spots | A getter: Classic light/dark keep the old blue (identical look), Signature uses Navy, Midnight uses Gold; text and icons on a primary fill use `AppColors.onPrimary` (Ink on Gold). Test: themes_test, 4.5:1 in every look | fixed |
| R9 | Accept button, distance line and price on the driver feed mixed blue into Midnight | Gold with Ink text in Midnight; Classic unchanged (images driver_feed_midnight / driver_feed_classic) | fixed |

Layout errors in the 56 images: none. Full regression after E13b: 337 files, all green after fixing four stale checks
from E7 (designV3 missing from SCREEN_INVENTORY, ADDON_PILOT, WHERE_IS_WHAT; the online-chip contrast test switched only
half of the palette).
