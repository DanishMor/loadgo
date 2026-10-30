# Store assets (E14)

Every image here is drawn in code from the same mark as the app (`lib/core/widgets/ds/brand_logo.dart`), so it can be
re-drawn at any time and carries no third-party artwork. They are PLACEHOLDERS until a designer delivers the final
logo (docs/ICON_AND_SPLASH.md, docs/LOGO_BRIEF.md). Sizes are from the Play Console help pages as read on 2026-10-30
and are marked UNVERIFIED: check them in the console before the upload.

## Draw them (no app build, no device)

```powershell
flutter test tool/make_brand_assets_test.dart        # assets/branding: icon, adaptive foreground, monochrome, splash, 512 store icon
                                                     # build/store: 1024x500 feature graphic (not bundled into the app)
dart run flutter_launcher_icons                      # Android (adaptive + monochrome), iOS, web icons
dart run flutter_native_splash:create                # native splash (Signature: Navy by day, true black at night)
```

## What the stores ask for

| Asset | Size / format (UNVERIFIED) | File | Notes |
|---|---|---|---|
| Play app icon | 512 x 512, 32-bit PNG, up to 1 MB | `assets/branding/store_icon_512.png` | Full square; Play rounds the corners. |
| Play feature graphic | 1024 x 500, JPEG or 24-bit PNG (no alpha) | `build/store/feature_graphic_1024x500.png` | Navy-to-Ink, centred mark, no words inside the safe middle so it reads at any crop. Opaque. |
| Phone screenshots | 2 to 8, 16:9 or 9:16, each side 320 to 3840 px | from the owner's phone (docs/PHONE_SMOKE_SHEET.md) | `tool/render_gallery.ps1` images are for review only: they use test data and must not be uploaded as real screenshots. |
| Launcher icon (Android 8+) | adaptive: foreground 108 dp with the mark inside the 66 dp safe zone, navy background | `assets/branding/icon_foreground.png` | The mark stays inside the middle 66 %. |
| Themed icon (Android 13+) | monochrome layer, one colour on transparent | `assets/branding/icon_monochrome.png` | The launcher tints it; drawn with `LogoVariant.mono`. |
| iOS icon | 1024 x 1024, no alpha | `assets/branding/icon.png` | `remove_alpha_ios: true` in pubspec. |
| Splash | centred mark on Navy (light) and true black (dark, Midnight) | `assets/branding/splash_logo.png` | Android 12+ uses the same colours. |

## Rules for anything in the listing

- The app name always comes from AppInfo (`dart run tool/apply_app_info.dart` fills the hosting pages).
- No other brand, logo or vehicle maker name in any image; generic vehicles only.
- No claims about insurance, guaranteed payment, arrival times or lending (rule 4); copy drafts are in docs/PLAY_LISTING.md.
- Screenshots show test accounts only, never a real phone number or name.
