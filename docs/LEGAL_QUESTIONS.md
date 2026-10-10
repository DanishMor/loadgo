# Vakeel aur CA se poochhne ke sawaal (Hinglish)

Ye **sawaalon ki list** hai, legal salah nahi. Har sawaal ke saath likha hai ki app mein abhi kya hai (file ka naam), taaki vakeel / CA ko seedha dikha sakein. Jawab milne par `docs/DECISIONS.md` mein ek line likhein aur jo badalna ho wo `docs/TERMS.md`, `docs/PRIVACY_POLICY.md`, `docs/REFUND_POLICY.md`, `docs/DRIVER_AGREEMENT.md`, `docs/TRANSPORTER_AGREEMENT.md` mein karwayein (phir `tool/apply_app_info.dart` se hosting pages). Ye sab abhi **DRAFT** hain.

Saath le jaane ke liye: `docs/OWNER_GUIDE.md`, `docs/DATA_RETENTION.md`, `docs/SECURITY_REVIEW.md`, aur ek chhoti demo (app chalakar trip ka flow).

---

## A. CA se (GST, commission, hisaab)

| # | Sawaal | App mein abhi kya hai |
|---|---|---|
| A1 | Platform **commission / platform fee** par GST kaise lagega? Kya LoadGo ko GST registration abhi chahiye (turnover ya intermediary / e-commerce operator ke niyam se)? Kis rate par (18% ya kuch aur)? | Default config: `platformFeePercent = 5`, `gstPercent = 5` (`lib/core/pricing/pricing_config.dart`); fare mein dono alag line dikhte hain (`lib/core/pricing/fare_calculator.dart`, `lib/core/widgets/fare_breakdown.dart`). Ye sirf **estimate** hai; paisa app se nahi guzarta (`docs/TERMS.md`). |
| A2 | Jab customer driver ko seedha cash/UPI deta hai aur platform fee alag se milti hai, to **fee kaun, kab, kaise** charge kare? Kya wallet/commission ledger ki entries invoice ban sakti hain? | Driver ledger: `trip_earning` aur `platform_commission` (negative) lines (`lib/core/models/ledger_entry.dart`, `lib/driver/wallet_screen.dart`); koi asli collection abhi nahi, "no money moves through LoadGo yet". |
| A3 | **Freight par GST** (GTA / RCM): transporter ya customer par kisko kya dikhana hai? Bilty/invoice par GST ka kya format chahiye? | Invoice aur PDF mein GST line (`lib/core/payments/earnings_statement.dart`, invoice screen); LR mein `gstPaise` aur GSTIN fields (`lib/core/bilty/lr_model.dart`). Rate sirf us copy mein jahan owner ne dikhaya. |
| A4 | **TDS** (194C ya anya) kab lagta hai? Kya driver/transporter ko payment par platform ko TDS katna padega? | App kuch nahi katta; koi TDS logic nahi. |
| A5 | Driver/transporter ki **income ka statement** (earnings/party statement) kis form mein dena theek hai? Kitne saal rakhna hai? | `lib/core/payments/earnings_statement.dart`, `lib/core/transporter/party_statement.dart`; 8 saal retention (`docs/DATA_RETENTION.md`). |
| A6 | **Refund / cancellation charge** ki accounting (kaun rakhta hai, GST?) | Cancellation charge sirf **record** hota hai (`CancellationPolicy` in `fare_calculator.dart`, `docs/REFUND_POLICY.md`). |
| A7 | Promo / credits / referral ko GST ya accounting mein kaise treat karein? | `lib/core/offers/promo.dart`, credits ledger (`docs/DATA_RETENTION.md` last rows). |

## B. Vakeel se: bilty, e-way bill, transport niyam

| # | Sawaal | App mein abhi kya hai |
|---|---|---|
| B1 | App mein bani **bilty / LR** ki kanooni haisiyat? Kaun issuer hai aur kiski zimmedari? Kya hastakshar/stamp chahiye? | LR "issuer ka record" hai, issue ke baad edit nahi (naya version), cancel ke liye karan (`docs/TERMS.md`, `lib/core/bilty/lr_service.dart`, `lr_pdf.dart`). Teen copies: full, driver, consignee (`lr_visibility.dart`). |
| B2 | **E-way bill** ki zimmedari: app sirf number/validity ka record rakhta hai. Kya ye kaafi hai? Galat ya expired bill par LoadGo ka kya daayitva hai? | Sirf user ka daala number aur date; GST portal se koi check nahi (`lib/core/documents/eway_status_line.dart`, `ewayStatus()` in `lib/core/payments/payment_logic.dart`; `LATER(paid)`). 12 ghante ka warning window. |
| B3 | **Transport licence / permits** (national permit, goods carriage): kya LoadGo ko kuch chahiye ya sirf transporter/driver ko? Kya hum "broker/aggregator" mane jayenge? | App sirf matching karta hai; driver docs (licence, RC) ka record (`docs/DATA_RETENTION.md`, `lib/core/models/vehicle.dart`). |
| B4 | **Motor Vehicles Aggregator Guidelines** ya anya state niyam goods-transport par lagu hote hain? | Koi alag compliance logic nahi. |
| B5 | **Insurance** (goods in transit) ka kya? App kya claim kar sakta hai kya nahi? | App mein "claims/dispute" flow hai (`lib/core/services/claim_service.dart`), insurance ka koi vaada nahi. `docs/PILOT_KIT.md` mein bhi "insurance hai" bolne se mana hai. |
| B6 | **Ghalat/kam/damaged maal** par dispute ka process aur samay seema kya rakhein? | Disputes aur damage tickets (`docs/OWNER_GUIDE.md` Dispute playbook); `docs/TERMS.md` mein sirf general line. |

## C. Vakeel se: agreements aur disclaimers

| # | Sawaal | App mein abhi kya hai |
|---|---|---|
| C1 | **Driver agreement**: kya independent contractor wording theek hai? Termination, strike/suspension, jurisdiction, stamp duty? | `docs/DRIVER_AGREEMENT.md` (DRAFT), hosting page `hosting/driver-agreement.html`. Strike ladder `lib/core/comm/chat_strikes.dart` (24 ghante, 3 din, 7 din; 14 din ki appeal). |
| C2 | **Transporter agreement**: fleet/team/company account, commission, indemnity, data sharing. | `docs/TRANSPORTER_AGREEMENT.md` (DRAFT), `hosting/transporter-agreement.html`. |
| C3 | **Liability disclaimer** ("LoadGo kisi nuksan ka zimmedar nahi") consumer law mein kitna chalega? Kya "marketplace" wording zyada surakshit hai? | `docs/TERMS.md` "Liability": "To the extent the law allows ..." aur consumer rights ki line. |
| C4 | **Terms acceptance** kaise lein (checkbox, version, timestamp) taaki court mein maanya ho? | Consent screens aur stored consents (`users/{uid}` consents, `lib/core/l10n/consent_strings.dart`); Terms/Privacy ka version number abhi nahi. |
| C5 | **Dispute resolution** (arbitration ya court, jagah)? Kis state ka jurisdiction likhein? | Terms mein "Indian law applies" (placeholder contact bhi `docs/PLACEHOLDERS.md` se bharna). |
| C6 | **Pilot consent text** (`docs/PILOT_KIT.md` section 8) theek hai? | Draft Hindi/Hinglish text. |

## D. Vakeel se: data, chat, call, DPDP

| # | Sawaal | App mein abhi kya hai |
|---|---|---|
| D1 | **DPDP Act 2023**: LoadGo "data fiduciary" hai? Notice, consent, purpose, grievance officer, breach notice ke liye kya chahiye? | `docs/PRIVACY_POLICY.md` (DRAFT), consents `consent_strings.dart`, delete/download in Settings, `docs/DATA_RETENTION.md`. |
| D2 | **Chat aur call data**: chat 8 saal (trip record ke saath), call records (kaun, kab, kaise khatam; **audio nahi**) 1 saal. Ye retention theek hai? Admin ko chat padhne ka adhikar kis shart par? | Chat blocking `lib/core/comm/contact_filter.dart` (phone/UPI roke jate hain); admin views audit log mein (`contact_view`, `chat_view`, 3 saal); calls `lib/core/call/*` peer-to-peer WebRTC, audio LoadGo servers se nahi guzarta (`docs/PRIVACY_POLICY.md`). |
| D3 | **Bachhon ka data**, 18 saal se kam: kya age gate chahiye? | Koi age check nahi; driver/transporter ke liye hi. |
| D4 | **Aadhaar / PAN / licence** jaise ID: sirf last 4 digit aur hash (`identity_index`). Kya ye kaafi hai, ya alag consent/purpose chahiye? | `docs/DATA_RETENTION.md`; Aadhaar poora kabhi nahi. |
| D5 | **Location**: trip ke dauran aur consent ke saath last location. Retention aur purpose wording theek? | `users/{uid}.lastLocation`, consent off par turant delete. |
| D6 | **Account deletion** vs 8 saal ka legal record (GST, e-way): jo hum "personal fields clear karke rakhte hain" wo kanooni taur par theek hai? | `docs/DATA_RETENTION.md` rules; `hosting/delete-account.html`; deletion requests admin handle karta hai. |
| D7 | **Vendors** (Google Firebase, India se bahar server): cross-border transfer ke liye kya likhna hai? | Privacy mein "Google Firebase ... on our behalf"; asli region Firebase project mein check karna hai (`docs/FIREBASE_CONSOLE_CHECKLIST.md`). |
| D8 | **Crash logs aur analytics** ko kya anonymised maane? | Redactor se personal data hata kar bhejte hain (`lib/core/services/breadcrumbs.dart` (Redactor), `docs/SECURITY_REVIEW.md`). |

## E. Trademark aur naam

| # | Sawaal | Note |
|---|---|---|
| E1 | **Naam "LoadGo"** (ya naya naam) ka trademark search: Class **39** (transport, goods delivery, freight booking) aur Class **42** (software / SaaS / app) mein kya pehle se registered ya similar hai? | Naam badalne ka script taiyaar hai (`docs/RENAME.md`); package id Play Store upload ke baad badal nahi sakta, isliye naam aur id upload se **pehle** final karein. |
| E2 | Logo ka alag trademark / copyright? Placeholder icon kisi par depend nahi karta. | `docs/ICON_AND_SPLASH.md`: final icon designer banayega; designer se **assignment of rights** likhwayein. |
| E3 | Domain aur app store listing ke naam ka conflict? | `docs/PLAY_LISTING.md` drafts. |

## F. Refund, cancellation, payment

| # | Sawaal | App mein abhi kya hai |
|---|---|---|
| F1 | Jab paisa seedha customer-driver ke beech hai, to **refund** ki zimmedari kiski? "Platform paisa nahi rakhta" wording kaafi hai? | `docs/REFUND_POLICY.md` (DRAFT), cancellation charge sirf record. |
| F2 | Future mein **payment gateway / escrow** aaye to kaun si licence (RBI payment aggregator niyam) chahiye? | Abhi nahi; adapters taiyaar (`docs/PAID_ADAPTERS.md`, `lib/core/adapters`). |
| F3 | Consumer Protection (E-Commerce) Rules ke tahat grievance officer, return/refund display? | Help screen aur support (`docs/PLACEHOLDERS.md` mein contact bharna baaki). |

---

## Meeting se pehle taiyaari (checklist)
- [ ] Ye file aur upar ki draft docs print / PDF.
- [ ] Demo: ek trip ka flow (post load, offer, OTP, bilty, wallet).
- [ ] `docs/SECURITY_REVIEW.md` aur `docs/DATA_RETENTION.md` saath.
- [ ] Naam aur package id ki shortlist (`docs/RENAME.md`).
- [ ] Har jawab ko `docs/DECISIONS.md` mein ek line, aur jo docs badalne hain unki list.
