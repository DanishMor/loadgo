# Brand: Load 20

Ek jagah ki list: naam, tagline, tone, logo, colour, font, do aur dont. Colour aur font ke **asli values** `lib/core/theme/` (design tokens, L4) mein hain; yahan sirf niyam hain. Naam ka code mein ek hi source hai: `lib/core/app_info.dart` (`docs/NAMING.md`, `docs/RENAME.md`).

## 1. Naam
* Display naam: **Load 20** (Latin mein, "L" aur "2" bade/seedhe, beech mein ek space).
* Dusri lipiyon mein: लोड 20 (hi, mr), ಲೋಡ್ 20 (kn), லோட் 20 (ta), లోడ్ 20 (te), લોડ 20 (gu), লোড 20 (bn), ਲੋਡ 20 (pa), لوڈ 20 (ur, ks). Ye transliteration hai; kisi native reader se ek baar padhwa lein.
* Bolte waqt: "लोड ट्वेंटी" / "Load twenty". Sankhya hamesha "20" likhein, "Twenty" ya "XX" nahi.
* Package id (`com.example.transport_app`) user ko nahi dikhta aur abhi nahi badla (`docs/NAME_CHECKLIST.md`).
* Purana naam (LoadGo) kisi user-facing jagah par nahi; `test/rename_check_test.dart` isko check karta hai.

## 2. Tagline
**"Maal bhejo, bharosa ke saath"** (Hinglish, jaisa hai waisa). Hindi: "माल भेजो, भरोसे के साथ". Baaki bhashaon ke anuvaad `AppInfo.taglines` mein. Tagline ko chhota rakhein; naam ke neeche ek line se zyada nahi, aur kabhi vaada nahi ("100% safe", "insurance hai") jo app nahi nibhati.

## 3. Tone of voice
Teen bhashaon mein ek hi swar: **seedha, bharosemand, chhote vaakya.** Dost jaisa, par kaam ki baat pehle. Trucking ke log vyast hote hain: ek vaakya mein ek hi baat.

| | Hindi | Hinglish | English |
|---|---|---|---|
| Kya karein | "लोड डालें" | "Load daalein" | "Post a load" |
| Wait | "ड्राइवर के रेट आ रहे हैं..." | "Driver ke rate aa rahe hain..." | "Rates are coming in..." |
| Galti | "OTP गलत है। फिर से डालें।" | "OTP galat hai. Phir se daalein." | "That OTP is wrong. Try again." |
| Paisa | "₹14,500 (ड्राइवर को सीधे)" | "₹14,500 (driver ko seedha)" | "₹14,500 (pay the driver directly)" |

Niyam:
1. **Pehle kaam, phir shabd.** Button par kriya ("Rate bhejo"), "Submit" nahi.
2. **Chhote vaakya** (10-12 shabd tak). Lambi baat ho to bullet.
3. **Seedhi sankhyaein:** paisa ₹ ke saath, tareekh "14 Oct", doori "280 km". Paisa app mein hamesha integer paise se bana (`docs/` money rules).
4. **Galti par kisi ko doshi nahi:** "Network nahi mila. Dobara try karein" (raw error kabhi nahi).
5. **Bharosa dikhao, bolo nahi:** "Verified" badge, OTP, trip status dikhayein; "hum sabse safe" jaise daave nahi.
6. **Hinglish** Roman mein wahi shabd jo log WhatsApp par likhte hain (maal, gaadi, rate, bilty). Angrezi tabhi jab sabko wahi aata hai (OTP, SOS, UPI).
7. **Respect:** "aap", "ji" jahan sahi; driver ko "bhai"/"uncle" nahi, naam ya "driver" likhein.
8. 12 bhashaon mein naya text ek saath (`docs/NAMING.md` ke tokens `{app}`), Urdu/Kashmiri RTL.

## 4. Logo
Logo mark + wordmark vector (CustomPainter) mein banega (L13), kisi aur brand jaisa ya copyrighted nahi. Placeholder abhi: safed truck, neele background par (`tool/make_placeholder_icon.dart`). **Final logo designer se approve karwana hai** (aur assignment of rights likhwana: `docs/LEGAL_QUESTIONS.md` E2).
* Chhoti jagah (icon, favicon): sirf mark. Bade (splash, hosting header): mark + wordmark.
* Saaf jagah (clear space): mark ki ooonchai ka aadha chaaron taraf. Minimum size 24 dp (mark), 96 dp (wordmark).
* Sirf do rang version: gehra navy par safed, ya safed par gehra navy. Accent (amber) sirf mark ke ek chhote hisse mein.
* Mat: stretch, rotate, shadow, outline, naya rang, photo ke upar bina overlay.

## 5. Colour
Direction: **gehra navy (bharosa) + saffron/amber accent (action)**, saath mein success (hara), warning (peela), error (laal) aur neutral slate. Exact hex `lib/core/theme/` mein; test (L4) sabit karta hai: text 4.5:1 se upar, UI components 3:1 se upar, light aur dark dono mein.
* Navy: app bar, heading, trust cheezein (Verified, OTP).
* Amber/saffron: ek screen par ek primary action.
* Hara/peela/laal: sirf status (success, warning, error). Rang akela arth nahi batata: icon ya text saath mein.
* Dark mode: kala-neela (navy-tinted), pure black nahi.
* Role ka halka accent (customer, driver, transporter) sirf chhota detail; Admin ka alag "Admin mode" banner.

## 6. Font
Ek brand font (OFL license, `assets/` mein license file ke saath) Latin ke liye + Devanagari; baaki scripts system fallback (L6). Heading bold, body regular; sankhya tabular (barabar chaudai) jahan paisa ya kilometer. Chhota text 12 sp se neeche nahi; 2.0x text scale par layout tootna nahi chahiye.

## 7. Do aur Dont
| Do | Dont |
|---|---|
| "Load 20" likhein, ek space ke saath | "Load20", "LOAD 20", "Load-20", "Load Twenty" |
| Tagline jaisi hai waisi | Tagline ko badalna ya anuvaad mein naya vaada jodna |
| Navy + amber, ek primary action per screen | Har button amber, 3+ rang akele status ke liye |
| Chhote vaakya, kriya wala button | "Submit", lambi paragraph, jargon |
| Paisa ₹ aur integer paise se | Floating point se paisa, bina ₹ ke sankhya |
| "Verified" tabhi jab admin ne verify kiya | Bina jaanch ke Verified/Trust badge |
| Raw error ki jagah saaf sentence + Retry | Exception ya code user ko dikhana |
| Placeholder logo ko "final" bolna nahi | Doosre brand ke truck/arrow jaisa logo copy karna |
