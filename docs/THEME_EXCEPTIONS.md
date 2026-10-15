# Theme exceptions (L7)

Outside `lib/core/theme/` nothing should spell a colour (`Color(0x...)`) or build a `TextStyle`; colours come from `DsColors` / `AppPalette` / the theme and text from `DsType` / `Theme.of(context).textTheme` (`docs/BRAND.md`). The screens written before the design system still do, so this list is the **baseline**: `test/theme_guard_test.dart` fails if a file gets more hard-coded colours or styles than listed here, or if a file that is not listed gets any. Moving a screen onto the shared components (Phase 3) lowers its number; then run `dart run tool/theme_guard.dart --write` to lock it in. The goal is an empty table.

Total: **0** colours, **0** text styles in **0** files.

| File | `Color(0x...)` | `TextStyle(` |
|---|---|---|
