# Translation review (F38)

`docs/TRANSLATION_REVIEW.csv` lists every text added or changed in Part 2 (otp limits, earnings hub, wallet security, finance, photos, push announcements, admin web, feature switches): **12 rows per text**, one per language. Open it in Excel or Google Sheets (UTF-8).

## For the native reader

For each row, check the `text` column. If it is fine, write `ok` in `reviewer_ok`. If not, write the better text in `reviewer_fix` (keep any `{name}` style placeholders and numbers exactly as they are) and your name in `reviewer_name`.

Languages: en English, hi Hindi, hinglish Hindi in Latin letters, kn Kannada, ta Tamil, te Telugu, mr Marathi, gu Gujarati, bn Bengali, pa Punjabi, ks Kashmiri, ur Urdu. Urdu and Kashmiri read right to left.

## Not in the CSV (review these files by eye)

- Push channel names (Android settings): `android/app/src/main/res/values-*/push_channels.xml`
- Text of the push messages sent by the server: `functions/src/pushText.js`
- Short legal wording: `docs/WALLET_LEGAL.md` questions go to the lawyer, not the reader.

## After the review

Give the filled CSV back. The fixes go into the `lib/core/l10n/*_strings.dart` file named in the `file` column. `flutter test test/translations_test.dart` checks every key still has all 12 languages.

## Make the CSV again

`node` script used: it compares the string tables with the commit before Part 2 (`e329d3c`) and writes only new or changed keys. Ask Claude to run it again before sending a new copy to the reader.

## Part 3 (G38 to G45)

`docs/TRANSLATION_REVIEW_PART3.csv` lists the 94 texts added in Part 3 (maps, live location, online payment, held payment, ID-check answers, driver trust card, usual price, safety check-in, khata, business card, and the names and help of the new switches), 12 languages each, same columns as the Part 2 sheet. Make it again with `node tool/translation_review_part3.js`. Two things to check closely: the SOS and check-in sentences (a driver may read them in a bad moment: short and calm) and the payment sentences (a customer must understand "held until delivery").
