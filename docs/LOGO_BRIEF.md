# Logo brief for the designer (F39)

Is file ko designer ko seedha bhej sakte hain. Poori brand rules: `docs/BRAND.md`. Abhi ka mark ek **placeholder** hai (code mein bana vector, `lib/core/widgets/ds/brand_logo.dart`); isko final logo se badalna hai.

## 1. Kaun hum hain
- **Naam:** Load 20 (Latin mein "Load 20", ek space; "Load20", "LOAD 20" nahi).
- **Kya hai:** India mein maal bhejne wale (customer), truck driver aur transporter ko jodne wala app. Rate, bilty (LR), trip code (OTP), tracking.
- **Tagline:** "Maal bhejo, bharosa ke saath" (jaisi hai waisi; logo ke saath ya alag).
- **Kaun use karega:** driver aur chhote transporter (kai log kam padhe-likhe, sasti phones, dhoop mein screen), customer (dukaan, factory, kisaan).

## 2. Mood
Bharosemand, seedha, mazboot, garam. Kisi badi company ka thanda look nahi, kisi tamasha-app ka shor nahi. Truck ki ladi-hui mazbooti, par dost jaisa.

Teen shabd: **bharosa, raftaar, apna.**

## 3. Rang
- Gehra **navy** (bharosa) + **saffron/amber** accent (action). Exact hex ka source `lib/core/theme/` hai; designer apni ankh se thoda alag shade suggest kar sakta hai, par contrast ka test (text 4.5:1, UI 3:1) pass hona chahiye.
- Do-rang version zaroori: navy par safed, safed par navy. Accent sirf ek chhote hisse mein.
- Dark background par bhi saaf dikhe.

## 4. Kya chahiye (deliverables)
| # | Cheez | Format |
|---|---|---|
| 1 | Mark (sirf nishan), wordmark ("Load 20" akshar), aur dono saath | SVG (outlined text), PNG 1024 px |
| 2 | Do-rang aur ek-rang (sirf safed, sirf kala) version | SVG |
| 3 | Android adaptive icon: foreground aur background alag, safe zone ke andar | PNG 432x432 (108 dp x4), SVG |
| 4 | Play Store icon | PNG 512x512, 32-bit, bina rounded corners |
| 5 | Play feature graphic | PNG 1024x500 |
| 6 | Splash ke liye mark (transparent) | SVG, PNG |
| 7 | Chhota favicon / notification icon (sirf safed silhouette) | SVG, PNG 96x96 |
| 8 | Wordmark ke 12 lipiyon ka mock (लोड 20, ಲೋಡ್ 20, லோட் 20 ...) agar naam wahan bhi likhna ho | PNG preview |
| 9 | Chhota use-guide: clear space, minimum size, kya na karein | 1 page PDF |

## 5. Size aur jagah
- Mark 24 dp par bhi pehchaana jaye (notification, favicon). Wordmark 96 dp se chhota nahi.
- Clear space: mark ki oonchai ka aadha.
- Dhoop mein, kam roshni mein, 48 dp ke button ke paas bhi saaf.

## 6. Kya na karein
- Kisi aur company ke logo jaisa (khaaskar badi logistics, cab ya delivery apps) ya copyrighted clip-art, stock icon, AI se bana bina haq ke.
- Sirf truck ka pehchaana-hua common clip-art; kuch apna chahiye jo yaad rahe.
- Bahut baarik line, gradient par nirbhar, shadow/outline/3D, 3 se zyada rang.
- Dharmik ya rajneetik pratik, jhanda, ya kisi shehar/rajya ka sanket.
- "Safe", "No. 1", "insured" jaise daave logo mein.
- Naam ko stretch, rotate ya naya rang dena.

## 7. Adhikar (rights) aur dastavez
- Final files ke saath **likhit assignment**: designer saare haq owner ko deta hai, aur ye original kaam hai. Template lawyer se: `docs/LEGAL_QUESTIONS.md` (E2).
- Trademark search naam aur logo dono ke liye owner karwayega (`docs/NAME_CHECKLIST.md`).
- Source file (AI/Figma) bhi chahiye.

## 8. Kaam ka tareeka
1. Designer 2-3 direction bheje (sketch).
2. Owner ek chunta hai; teen raound tak badlav.
3. Final files + assignment.
4. Claude naye files `lib/core/widgets/ds/brand_logo.dart` aur icon generators (`docs/ICON_AND_SPLASH.md`) mein lagata hai; kisi hard-coded rang ke bina.
