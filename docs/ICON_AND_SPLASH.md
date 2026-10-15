# Icon aur splash (L14, Load 20)

**Ye abhi placeholder hai.** Final logo, icon aur splash designer se banwana aur approve karwana hai (1024x1024 PNG, adaptive icon ke liye foreground alag, safe zone beech ka 66%). Designer se **assignment of rights** bhi likhwayein (`docs/LEGAL_QUESTIONS.md` E2).

## Kya hai
* **Mark:** navy tile ya navy background par safed "L" jiska paer tir (arrow) mein badalta hai (maal ka safar) aur ek saffron dot (manzil). Code mein `lib/core/widgets/ds/brand_logo.dart` (`LogoMark`, `Wordmark`, `BrandLockup`), CustomPainter se, har size par saaf, light/dark dono mein.
* **Icon files:** `assets/branding/icon.png` (navy square + mark), `icon_foreground.png` (sirf mark, adaptive icon, safe zone ke andar), `splash_logo.png`, `store_icon_512.png` (Play Store). Sab usi mark se bane hain.
* **Config:** `pubspec.yaml` mein `flutter_launcher_icons` (Android, iOS, web; adaptive background navy `#123A6B`) aur `flutter_native_splash` (navy, dark mode `#0D1526`, Android 12).

## Dobara banana (koi app build nahi hota)
```powershell
flutter test tool/make_brand_assets_test.dart        # assets/branding ke 4 PNG likhta hai
dart run flutter_launcher_icons                      # android + ios + web icons
dart run flutter_native_splash:create                # native splash
```
Alag folder mein try karna ho: `flutter test tool/make_brand_assets_test.dart --dart-define=OUT=C:\temp\icons`.

## Final artwork aane par
1. Designer ki files `assets/branding/` mein wahi naam se rakho (icon.png opaque, icon_foreground.png transparent, splash_logo.png transparent, store_icon_512.png) aur `brand_logo.dart` ka mark bhi usi se milao.
2. Upar ki do generator commands chalao.
3. Phone par light aur dark launcher mein icon dekho. Play Store ke liye `store_icon_512.png` aur 1024x500 feature graphic (`docs/PLAY_LISTING.md`).
