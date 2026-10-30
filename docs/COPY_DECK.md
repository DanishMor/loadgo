# Copy deck (E12)

How the app speaks. Voice and brand rules are in `docs/BRAND_GUIDE.md` section 2 and `docs/BRAND.md` section 3; all text lives in `lib/core/l10n` (12 languages, order en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur). Hindi is written first; English and Hinglish follow it in meaning, not word for word. `test/copy_voice_test.dart` enforces the rules below on English, Hindi and Hinglish.

## Rules (tested)
1. **"Aap", never "tum" or "tu".** Hinglish uses the respectful verb form ("likhein", "daalein", "dekhein"), not "likho", "bolo".
2. **No "bhai", "bhaiya", "uncle".** Use the person's name or "driver".
3. **Verb on the button.** "Rate bhejein", "Load daalein", "Pakka karein". Never "Submit".
4. **No promises.** No "100%", "guaranteed", "risk-free", "fully insured", "sabse safe". Show proof instead (Verified badge, OTP, timeline).
5. **Say what happened, not how well.** "Phone number verified." not "Phone verified successfully!".
6. **Calm punctuation.** A full stop (Hindi, Marathi, Bengali, Punjabi: danda; Urdu, Kashmiri: Urdu full stop). An exclamation mark only in a greeting (Sahayak's "Namaste!"), never two in a row.
7. **No raw technical words** ("exception", "stack trace", error codes). Codes go to Diagnose (E-PERM reason codes).
8. **No "oops".** Errors are calm and say the next step.

## Patterns
| Moment | Hindi | Hinglish | English |
|---|---|---|---|
| Done | डिलीवर हो गया। | Deliver ho gaya. | Delivered. |
| Thanks | रेटिंग के लिए धन्यवाद। | Rating ke liye shukriya. | Thanks for your rating. |
| Empty | अभी कोई संदेश नहीं। नमस्ते कहें। | Abhi koi message nahi. Hello likhein. | No messages yet. Say hello. |
| Offline | नेटवर्क नहीं मिला। दोबारा कोशिश करें। | Network nahi mila. Dobara koshish karein. | No network. Try again. |
| Wrong input | OTP गलत है। फिर से डालें। | OTP galat hai. Phir se daalein. | That OTP is wrong. Try again. |
| Money | ₹14,500 (ड्राइवर को सीधे) | ₹14,500 (driver ko seedha) | ₹14,500 (pay the driver directly) |
| Calculator | अपने CA से पूछ लें। | Apne CA se pooch lein. | Check with your CA. |

## Error messages
- One sentence for what happened, one for what to do: "Network nahi mila. Dobara koshish karein."
- Never blame the person. Never show the raw error (`errorText()` in `lib/core/errors/error_text.dart` maps every error to a sentence).
- Permission denied by the rules: "Abhi yeh kaam nahi ho saka. Diagnose kholein." with the reason code kept for Diagnose only.

## Copy pass log (E12)
- Scanned 3,121 keys in English, Hindi and Hinglish. Earlier plans had already cleaned blame, claims and informal address; nothing was found under rules 1 to 4, 7 and 8.
- Changed: `phoneVerified` (no "successfully", calm), `thanksForRating`, `tipSent`, `deliveredTitle`, `noMessages` (full stops in all 12 languages; Hinglish "Hello bolo" became "Hello likhein").
- Kept: `asGreeting` keeps "Namaste!" (a greeting).
- Native-reader review of the other nine languages stays in the translation review sheets (`docs/TRANSLATION_REVIEW_*.csv`; Elite sheet in E77).
