# Brand guide (Elite, E6)

The rules for how the app looks, sounds and speaks. Name, tagline and logo basics stay in `docs/BRAND.md`; exact values live in code (`lib/core/theme/design_tokens.dart`) and are proven by `test/design_tokens_test.dart`. The app name always comes from `AppInfo` (never typed by hand).

## 1. Positioning
- **Premium, not pricey.** Calm screens, few colours, generous space. Luxury here means care and clarity, not gold everywhere.
- **Trustworthy.** We show proof (Verified badge, OTP, live status, bilty) instead of claiming it. No "100% safe", no promises the app cannot keep.
- **Indian.** Hindi first, 12 languages, rupees in integer paise, Indian date and number habits, trucking words people really use (maal, gaadi, bilty).
- **Respectful to drivers.** Drivers are partners. We address them as "aap", never "bhai" or "uncle", and never shame them in copy (no red "You failed" banners).

## 2. Voice
- "Aap" always. Short sentences: one idea, 10 to 12 words at most.
- Verb on buttons ("Rate bhejein", "Load daalein"), never "Submit".
- No blame in errors: "Network nahi mila. Dobara koshish karein." Raw errors and codes never reach the user (E-PERM reason codes go to Diagnose).
- No legal, tax, insurance or guaranteed-payment claims. Calculators carry "check with your CA".
- Tagline is kept as it is: see `docs/BRAND.md` section 2 and `AppInfo.taglines`.

## 3. Logo usage
- Mark and wordmark are drawn in code (`lib/core/widgets/ds/brand_logo.dart`). The final logo still needs a designer's approval (`docs/LEGAL_QUESTIONS.md`).
- Signature theme: Navy mark on Ivory, Gold dot. Midnight theme: Ivory mark on black, Gold dot. Classic: today's Navy and saffron.
- Clear space: half the mark height on every side. Minimum 24 dp (mark), 96 dp (wordmark).
- Never stretch, rotate, outline, shadow or recolour it, and never place it on a photo without a scrim.

## 4. Palette (Navy and Ink, one Gold accent, on Ivory)
| Token (`DsLuxe`) | Hex | Role |
|---|---|---|
| `ivory` | #FAF7F0 | Signature background |
| `ink` | #0B1220 | Body text, text on Gold |
| `navy` | #14284B | Trust: app bar titles, links, Verified, primary filled buttons |
| `gold` | #C9A24A | The one accent: main action fill, hairlines, the logo dot |
| `goldDeep` | #7E5F17 | Gold when it must be read on Ivory (small accent text, progress) |
| `goldLight` | #E0BE6A | Gold on black (Midnight) |

Contrast verified by test (WCAG 2.x AA): text 4.5:1 or more, UI parts 3:1 or more, for every pair in Classic light, Classic dark, Signature and Midnight. Gold on Ivory is below 4.5:1 and is decoration only (the test checks that too, so nobody uses it for text by mistake).

Rules:
1. One Gold thing per screen: the main action. Everything else is Navy, Ink or neutral.
2. Status keeps its own colours (green, amber, red) in every theme, always with an icon or a word. Colour never carries meaning alone.
3. Midnight is true black (#000000) for OLED battery; Classic dark stays navy-tinted.
4. Role accents (customer, driver, transporter) stay thin details: icons and lines, never fills behind text.

## 5. Token set
| Group | Where | Notes |
|---|---|---|
| Colour | `DsColors` (`context.ds`): `light`, `dark` (Classic), `signature`, `midnight` | 27 roles each; same names in every theme |
| Type | `DsType` (display 32 to caption 12), `DsStyle` consts | Mukta + Noto fallbacks; tabular digits for money (`DsType.number`) |
| Space | `DsSpace` 4/8 grid, gutter 16, tap 48 / 64 | |
| Radius | `DsRadius` 8, 12, 16, 24, pill | |
| Elevation | `DsElevation` 0, 1, 2, 4, 8 | cards flat with a border; only sheets and dialogs lift |
| Motion | `DsMotion` fast 120, normal 200, slow 320 ms | always through `DsMotion.duration` |

## 6. Motion principles
- Motion explains, it never decorates: where a thing came from, where it went, what changed.
- Soft springs and ease-out; nothing bounces more than once. Success moments are short (under 600 ms) and quiet.
- Reduce-motion (system) and LowEndMode turn every duration to zero. Each screen has an animation budget (E9).

## 7. Sound
- Off by default for non-critical events; a short, soft chime for "new load" and "offer accepted" only.
- Quiet hours and LowEndMode silence it (`FeedbackKit`). Never loop a sound, except the SOS alarm.

## 8. Haptics
- Light tick on selection, medium on confirm (slide-to-confirm, bid sent), heavy only for SOS.
- No haptics while scrolling. One haptic per user action at most.

## 9. Imagery
- Original vector art drawn in code (illustrations E11, vehicles E16). No stock photos, no third-party artwork.
- Generic vehicles only: never a manufacturer logo, grille shape or name.
- Real people only in user-provided photos (driver vehicle photos E18), never in marketing art inside the app.

## 10. Do and do not
| Do | Do not |
|---|---|
| Ink text on Ivory, Navy for trust | Gold text on Ivory, gold gradients, glitter |
| One Gold action per screen | Several Gold buttons competing |
| Show proof (badge, OTP, timeline) | Claim safety, insurance or guaranteed payment |
| "Aap", short sentences, verbs on buttons | "Bhai", jargon, "Submit", long paragraphs |
| Rupees from integer paise, tabular digits | Floating-point money, prices without the rupee sign |
| Respect reduce-motion and LowEndMode | Animations that cannot be turned off |
| Generic vector vehicles | Brand logos or real models on vehicles |
| Keep Classic selectable | Force the new look on anyone |
