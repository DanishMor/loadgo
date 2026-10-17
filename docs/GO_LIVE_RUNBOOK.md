# Go-live runbook (G43)

Hinglish, ek ek step. **Ye saare commands aap khud apne laptop par chalate hain, apne login se.** Claude kabhi deploy nahi chalata, aur koi key chat ya repo mein nahi likhi jaati. `<project-id>` ki jagah apna Firebase project id likhein. Har step ke neeche "Kaise verify karein" aur "Wapas kaise lein" hai. Zyada detail ke liye: `docs/BLAZE_GO_LIVE.md`, `docs/FUNCTIONS.md`, `docs/COST_WATCH.md`.

Pehle laptop par ye chalayein (sirf padhta hai, kuch badalta nahi):

```powershell
cd C:\projects\loadgo
powershell -File tool\golive_check.ps1
```

Ye batata hai: kaun sa Firebase login hai, kaun sa project, git saaf hai ya nahi, aur ye checklist.

---

## 1. Phone par smoke test (pehle, bina kisi deploy ke)

Do real Android phones par naya build (aap khud banate hain: `flutter build apk --release`, ya Play ka internal testing track).

| Kya dabana | Kya dikhna chahiye | Pass? |
|---|---|---|
| Role chuno, phone number, OTP | Login ho jaye | |
| Customer: load post karo (Delhi se Jaipur) | Fare estimate dikhe, load list mein aaye | |
| Driver: us load par offer do | Customer ko offer dikhe | |
| Customer offer chune, driver confirm | Booking bane, trip code dikhe | |
| Driver trip aage badhaye (code daalkar) | Status badle | |
| Profile > Settings > Language Hindi | Sab text Hindi mein | |
| Dark mode | Koi text padhne se na chhute | |

Poori sheet: `docs/PHONE_TEST_SHEET.md`.

**Kaise verify karein:** sab "Pass" ho. **Wapas:** kuch nahi badla, koi deploy nahi hua.

---

## 2. Blaze plan aur budget alert

1. Firebase Console > Usage and billing > **Blaze**.
2. Google Cloud Console > Billing > Budgets and alerts > naya budget (jaise Rs 500 mahina), alert 50%, 90%, 100% par e-mail.

**Kaise verify karein:** budget list mein dikhe; "Send test notification" se e-mail aaye. **Wapas:** Blaze se Spark par laut sakte hain (functions band ho jayenge).

---

## 3. Firestore rules, indexes, Storage rules

```powershell
cd C:\projects\loadgo
firebase login:list
firebase use <project-id>
powershell -File tool\deploy_rules.ps1 -Account "<aapka-google-email>" -Project "<project-id>" -WithStorage
```

Ye script pehle login check karti hai, "YES" poochti hai, phir `firestore.rules`, `firestore.indexes.json` aur `storage.rules` deploy karti hai.

**Agar 409 error aaye** (Console mein rules/indexes beech mein badle, ya index pehle se hai):

1. Firebase Console > Firestore Database > **Rules** tab > `firestore.rules` file ka poora text paste karo > **Publish**.
2. Firebase Console > Storage > **Rules** > `storage.rules` ka text paste > **Publish**.
3. Firestore > **Indexes** > jo index `firestore.indexes.json` mein hain wo ek ek karke banao (ya `firebase deploy --only firestore:indexes` dobara chalao). Sab "Enabled" hone tak ruko.

**Kaise verify karein:** app kholo, load, chat, wallet kholo: kahin "permission denied" na aaye. Console > Firestore > Rules mein "Last published" abhi ka time. **Wapas:** git se purani `firestore.rules` / `storage.rules` lekar dobara publish.

---

## 4. Functions ke secrets (aap khud type karein, chat ya repo mein kabhi nahi)

Har command value poochta hai; aap type karte hain, wo kahin likhi nahi jaati.

```powershell
firebase functions:secrets:set RAZORPAY_KEY_ID          # Razorpay TEST key id
firebase functions:secrets:set RAZORPAY_KEY_SECRET      # Razorpay TEST key secret
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET  # ek lamba random text jo aap banate hain
firebase functions:secrets:set MAPS_SERVER_KEY          # Google Routes key (docs/MAPS_SETUP.md)
firebase functions:secrets:set MSG91_AUTH_KEY           # SMS partner key (docs/SMS_SETUP.md)
```

Maps ki Android key repo mein nahi jati: `android\local.properties` mein ek line `MAPS_API_KEY=...` (file git mein ignored hai).

**Kaise verify karein:** `firebase functions:secrets:access RAZORPAY_KEY_ID` mat chalayein (wo value dikha deta hai). Sirf list dekhein: Google Cloud Console > Secret Manager mein paanchon naam dikhein. **Wapas:** `firebase functions:secrets:destroy <NAAM>`.

---

## 5. Functions deploy aur "Check server"

```powershell
cd C:\projects\loadgo\functions
npm ci
npm test
npm run test:emulator        # Java chahiye: Android Studio ka jbr, sirf is command ke liye
cd ..
firebase deploy --only functions
```

Deploy ke baad:

1. Console > Functions mein sab functions `asia-south1` mein dikhein.
2. Console > Functions > `paymentWebhook` ka URL copy karo. Razorpay dashboard > Webhooks > naya webhook: wahi URL, wahi `RAZORPAY_WEBHOOK_SECRET`, events `payment.captured`, `payment.failed`, `refund.processed`.
3. Admin panel > System health > **Check server**.

**Kaise verify karein:** "The server answers." likha aaye. App pehle jaisa chale (har switch abhi band hai). **Wapas:** `firebase functions:delete <naam> --region asia-south1`.

---

## 6. Switch ek ek karke, 24 ghante ke gap par

Admin > Features. Har switch ke baad ek din Console > Functions > Logs aur Billing dekhein. **Pehle pilot mode** (ek route, 10 log), phir sab.

| Number | Switch | Kya dekhna hai | Rollback |
|---|---|---|---|
| 1 | `pushNotifications` | asli phone par push aaye, tap karne par sahi screen khule | switch OFF |
| 2 | `photoUploads` | papers aur trip photo upload hon; Storage size | switch OFF |
| 3 | `maps` (pehle Maps key `docs/MAPS_SETUP.md` ke hisaab se restrict karein) | post load par km sahi (Delhi-Jaipur lagbhag 280); trip map khule | switch OFF: city table wapas |
| 4 | `liveLocation` | driver ke phone par notification "Load 20 is sharing...", customer ko "Last seen"/map; 1 ghante ki drive ke baad battery | switch OFF |
| 5 | `paymentGateway` (**sirf test keys**) | chhoti booking test card/UPI se bhar do, `payment_orders` mein `paid`; admin se refund | switch OFF |
| 6 | `smsGateway` (DLT templates approved hon, `docs/SMS_SETUP.md`) | notification band wale test number par 1 SMS | switch OFF |

Uske baad (zarurat ho to, ek ek karke): `serverLimits`, `serverChatScan`, `serverTrust` (phir `tripTrustCard`, `rateRange`), `serverCredits`, `serverJobs`, `serverAdminActions`, `serverDeletion`, `serverWallet`, `adminBroadcast`, `payHold`, `kycVerify` (partner chunne ke baad), `safetyCheckin`, `khata`, `bizCard`, `appCheckEnforce` (sabse aakhir, `docs/APP_CHECK.md` ke hisaab se).

**Kaise verify karein (har switch):** upar ki table ka "Kya dekhna hai". **Wapas:** Admin > Features mein switch OFF; 30 second mein asar. Function kharab ho to pehle switch OFF, phir function delete/redeploy.

---

## 7. Har switch ka rollback (ek jagah)

| Samasya | Karna |
|---|---|
| Koi feature galat | Admin > Features mein uska switch OFF |
| Billing badh rahi | Console > Billing > Reports by service; aakhri chalu kiya switch OFF; `config/mapsLimits`, `config/sms`, `config/paymentLimits`, `config/kyc` mein `totalPerDay` kam karo |
| Payment galat | `paymentGateway` OFF, phir Razorpay dashboard mein dekho; refund Admin se (finance/super) |
| Rules ne kuch rok diya | purani `firestore.rules` git se, Console > Rules > Publish |
| Poora functions hata do | `firebase functions:delete` ya Blaze se Spark |
| Paisa galat dikhe | haath se kabhi edit nahi; Reverse/Reject/correction line (`docs/WALLET_SECURITY.md`) |

---

## 8. Test numbers hatao aur asli admin

1. Console > Authentication > Sign-in method > Phone > **Phone numbers for testing**: sab hata do (khaali list).
2. Console > Authentication > Settings > SMS region policy: sirf India (+91).
3. Asli admin: Firestore > `admins` collection mein apne asli user id ka document (`createdBy: console`); test admin documents hata do.
4. Demo data band: Admin > Demo data; `config/app.allowDemo` OFF.
5. Authentication mein test accounts delete karo.

**Kaise verify karein:** test number se login try karo: refuse ho. Naye phone se sign-up par asli SMS aaye. **Wapas:** test number wapas jodna ho to Console se (launch ke baad nahi).

---

## Aakhir mein

`docs/RELEASE_CANDIDATE.md` ki checklist, Play listing (`docs/PLAY_LISTING.md`), privacy policy mein naye processors (Razorpay, SMS partner, Google Maps, ID partner agar chuna). Lawyer/CA ke sawal: `docs/LEGAL_QUESTIONS.md`.
