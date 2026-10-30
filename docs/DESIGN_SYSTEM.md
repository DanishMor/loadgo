# Design system (Part 4)

Everything lives in `lib/core/theme/design_tokens.dart` (tokens) and `lib/core/widgets/ds/` (components). Screens never hard-code a colour, a size or a style: they take them from `context.ds`, `DsType`, `DsSpace`, `DsRadius`. `test/theme_guard_test.dart` fails on a new hard-coded colour or style.

## Themes (E7)
Three colour sets with the same 27 roles: Classic light and dark (`DsColors.light`, `DsColors.dark`), Signature (`DsColors.signature`, Ivory) and Midnight (`DsColors.midnight`, true black with Gold). `ThemeStyle` (signature, classic) picks the pair; Settings > Look and Settings > Appearance (system, light, dark) choose, both kept on the device (`ThemeStore`). The `designV3` switch (default ON) shows Classic to everyone when OFF. `AppTheme.build` puts the set on ThemeData as `DsTheme`, so `context.ds` and every component follow the theme. Palette rules: `docs/BRAND_GUIDE.md`.

## Tokens
| Token | Use |
|---|---|
| `DsColors` (`context.ds`) | bg, primary, onPrimary, text, textStrong, textMuted, success/warning/error with their soft backgrounds; light and dark |
| `DsType` | display, headline, title, subtitle, body, bodySmall, label, caption |
| `DsSpace` | 4/8 grid: s1 to s8, gutter 16, tapMin 48 |
| `DsRadius` | sm 8, md 12, lg 16, xl 24, pill |
| `DsHero` | the blue gradient of the hero cards |

## Components (core/widgets/ds)
AppCard, AppButton (primary, secondary, tertiary, danger; `big` for drivers), StatusBadge (tone and icon, never colour alone), RouteRibbon, FareMeter, CountdownRing, SlideToConfirm, BidCard, DriverMiniCard, StatusTimelineV2, QuickChipRow, showAppSheet, showConfirmDialog, AppTopBar, SkeletonList, FeedbackKit (sound and vibration, quiet hours, Low-end mode).

## Rules
1. One main action per screen; targets 48 dp or more.
2. Every list screen has loading, empty, error and offline states (LiveStream, PagedLiveStream, EmptyState, ErrorRetry).
3. A new screen is tested at 360x640, 2.0x text, light, dark, Hindi and Urdu (right to left).
4. New work sits behind `uiV2`; the old screen stays as it was when the switch is OFF.
5. All text comes from `lib/core/l10n` with 12 languages; a native reader checks them (`docs/TRANSLATION_REVIEW_PART4.csv`).
6. Long lists are lazy (ListView.builder); the performance guard fails on a new eager list.
