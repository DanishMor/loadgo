# Icon aur splash (P5)

**Ye abhi placeholder hai.** Final icon aur splash artwork designer se banwana hai (1024x1024 PNG, adaptive icon ke liye foreground alag, safe zone beech ka 66%).

## Kya pehle se set hai
* `pubspec.yaml` mein `flutter_launcher_icons` aur `flutter_native_splash` ki config (blue `#1565C0`, adaptive icon, Android 12 splash).
* Source images: `assets/branding/icon.png`, `icon_foreground.png`, `splash_logo.png` (white truck on blue).
* Generated files `android/app/src/main/res/mipmap-*` aur splash drawables pehle se bane hue hain.

## Placeholder dobara banana (pure Dart, koi package nahi)
```powershell
dart run tool/make_placeholder_icon.dart            # assets/branding ko overwrite karta hai
dart run flutter_launcher_icons                     # android + ios icons
dart run flutter_native_splash:create               # native splash
```
Pehle alag folder mein try karna ho: `dart run tool/make_placeholder_icon.dart C:\temp\icons`.

## Final artwork aane par
1. Designer ki 3 files `assets/branding/` mein wahi naam se rakho (icon.png opaque, icon_foreground.png transparent, splash_logo.png transparent).
2. Upar ki do generator commands chalao.
3. Phone par light aur dark launcher dono mein icon dekho; Play Store ke liye alag 512x512 icon aur 1024x500 feature graphic chahiye (`docs/PLAY_LISTING.md`).
