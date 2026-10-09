# Owner guide (Hinglish)

Yeh guide aapke liye hai: pilot kaise chalana hai, roz kya dekhna hai, har admin screen kis kaam ki hai, aur SOS, accident, fraud, dispute aaye to kya karna hai. Technical kuch nahi chahiye. Sab kuch app ke Admin panel mein hai.

> Yeh guide LoadGo ke abhi ke code ke hisaab se hai. Paise ka lena-dena app mein nahi hota: customer aur driver seedha hisaab karte hain, app sirf record rakhta hai. Legal texts abhi DRAFT hain, vakeel se review zaroori hai.

## 1. Pilot kaise chalayein (pehle 4 hafte)
1. **Chhota area chunein.** 1 ya 2 routes (jaise Delhi - Jaipur). Admin > **Invite codes** mein "sirf invite se" switch on karein aur open cities ki list daalein.
2. **Pehle 10 driver, phir 10 customer.** Admin > **Invite codes** se code banayein (role, kitni baar chalega, kab tak). Code WhatsApp par bhejein. Driver ko pehle verify karein (Driver verification).
3. **Route ke bahar wale log** "service nahi hai" screen se **Waitlist** mein aa jaate hain. Admin > **Waitlist** mein dekhein kis route ki maang zyada hai; wahi agla route banta hai.
4. **Har load ko dekhein.** Admin > **Pilot control room** par open aur unfilled loads dikhte hain. Unfilled load ke liye **Manual dispatch** se driver suggest karein aur phone par baat karke note likhein.
5. **Hafte mein ek baar** **Pilot report** kholein, text copy karein aur WhatsApp group mein daalein. **Pilot cohorts** se dekhein pehli bid kitni jaldi aati hai aur kitne log dobara aate hain.
6. **Trip ke baad** "dobara use karoge?" ka jawab **Use-again survey** mein aata hai. 70% se zyada haan achha sanket hai.
7. Jab numbers theek hon (load bhar jaate hain, SOS nahi, cancel kam) tab naya route kholein aur invite ka switch dheere dheere band karein.

## 2. Roz ki checklist (10 minute)
- [ ] **Pilot control room**: open SOS 0 hai? Unfilled loads kitne hain?
- [ ] **Alerts**: koi nayi SOS, fraud flag, strike ya documents expire hone wale?
- [ ] **Tickets** aur **Disputes**: koi 24 ghante se purana?
- [ ] **Driver verification**: nayi requests ka jawab (24 ghante ke andar).
- [ ] **Payment aging**: jin trips ka paisa atka hai unko nudge bhejein.
- [ ] **Strike appeals**: koi appeal aayi ho to padhein aur faisla likhein.
- [ ] **Health**: errors achanak badh to nahi gaye?

## 3. Har admin screen ka kaam
Kaun dekh sakta hai (role): super = owner, ops, support, verifier, finance. Jo role ko screen nahi milti wo menu mein dikhti hi nahi.
- **Analytics**: kitne users, loads, bookings. Sab roles.
- **Users**: kisi ko dhundhna, profile dekhna, hold ya suspend karna. Ek saath kai users par action karein to 30 second ka Undo milta hai. Sab roles.
- **Driver verification**: documents dekhkar approve ya reject. Reject karte waqt wajah chunein; driver ko wajah dikhti hai aur wo dobara bhej sakta hai. super, verifier.
- **Vehicles**: gaadi ke papers dekhna, suspend karna. super, verifier.
- **Loads**, **Bookings**: sab dekhna; booking ko trip shuru hone se pehle doosre driver ko dena. Sab roles.
- **Tickets**: help requests ka jawab. super, support.
- **SOS**: emergency alerts (section 4 dekhein). super, support, ops.
- **Reports**: kisi ne kisi ki shikayat ki. super, support, ops.
- **Chat violations**: number ya UPI bhejne ki koshish, strikes, suspension badhana ya hatana. super, support, ops.
- **Strike appeals**: user kehta hai strike galat thi. "Strike hatayein" ya "strike rakhein" aur note likhein. super, support, ops.
- **Signals**: risk ke sanket (bahut cancel, duplicate device). super, ops, verifier.
- **Fraud cases**: shak wale cases ka record aur faisla. super, ops.
- **Disputes**: damage, kami ya delay ka claim. super, support.
- **Rating flags**, **Rating bursts**: nakli ya badla lene wali ratings. super, support, ops.
- **Sahayak**: assistant ne jin sawalon ka jawab nahi diya. super, support.
- **Feedback**: users ki rai. super, support.
- **Flagged users**: review mein rakhe gaye log. super, ops.
- **Health**: app ke errors ka namuna. super, ops.
- **Templates**: chat ke taiyaar jawab. super.
- **Demo data**: test data banana aur hatana (live project mein 0 rakhein). super.
- **Features**: kisi feature ko on/off karna. super.
- **Config**: fare, commission, limits ke settings. Badalne se pehle diff dikhta hai; galti ho to History se purani value wapas laayein. super.
- **Offers**: offers ka global switch. super.
- **Unit economics**: har trip par kamai ka andaza. super, finance.
- **Supply and demand**: kis shehar mein driver kam hain. super, ops.
- **Pilot funnel**: signup se pehli trip tak kitne log pahunche. super, ops.
- **Pilot control room**: aaj ka poora haal ek screen par. super, ops, support.
- **Invite codes**: pilot ke code, whitelist, open cities. super, ops.
- **Waitlist**: jin routes par service nahi hai wahan ki maang. super, ops.
- **Manual dispatch**: unfilled load par driver suggest karna aur call-back note. super, ops.
- **Pilot report**: roz aur hafte ka text report. super, ops.
- **Pilot cohorts**: pehli bid kitni jaldi, load kitni jaldi bhara, dobara use. CSV bhi. super, ops.
- **Use-again survey**: trip ke baad ka 1-tap jawab. super, ops.
- **Payment aging**: kis trip ka paisa kitne din se atka hai; nudge bhejna. super, ops, support, finance.
- **Search everything**: naam, vehicle number, booking id ya LR number se turant dhundhna. Sab roles (jo role jo dekh sakta hai wahi dikhta hai).
- **Alerts**: SOS, fraud flag, strikes, documents jo ek saath expire ho rahe hain. Sab roles.
- **Deletion requests**: account hatane ki request (active trip ho to nahi hota). super, support.
- **Audit log**: kisne kya kiya ka record. super, ops.
- **Driver rewards**, **Payouts**: incentive aur payout ka record. super, finance.

## 4. Playbooks
### SOS aaya
1. Alerts ya SOS screen par alert kholein; booking, last location aur emergency contact dikhega.
2. **Turant driver/customer ko call karein** (Users > phone dekhne par audit log banta hai). Jawab na mile to emergency contact ko.
3. Khatra asli hai to bolein 112 par call karein. App police ya ambulance nahi bulata.
4. SOS ko "resolved" karein aur apne paas note rakhein: kisne, kab, kya hua.
5. 24 ghante baad dobara baat karke band karein. Dubara hone par us user ki risk Signals mein dekhein.

### Accident ya breakdown
1. Driver ya customer Help se ticket ya SOS banata hai. Dono ko call karke dekhein ki sab theek hain.
2. Customer ko batayein: dusri gaadi chahiye? Customer se kahein ki naya load post kare; purani trip ka record Disputes/claim mein rakhein.
3. Photos aur trip timeline Disputes mein rakhein. Insurance ka kaam driver/transporter ka hai; app insurance nahi deta.
4. Driver ki gaadi ke papers dekhein (Vehicles). Galti driver ki ho to Signals mein note.

### Fraud ka shak
1. Alerts ya Signals mein flag dekhein: duplicate device, bahut cancel, number bhejne ki koshish.
2. **Users** mein 360 view kholein: documents, trips, ratings, strikes, tickets, audit.
3. Pehle **hold** karein (kam sakht), ek line mein wajah likhein. Phone par baat karein.
4. Pakka ho to **Fraud cases** mein case banayein aur suspend karein. Ban jaisa bada kadam sochkar, audit log mein wajah ke saath.
5. Galat nikla to hold hatayein aur maafi maangein. Har action audit log mein hai.

### Dispute (damage, kami, delay, galat charge)
1. **Disputes** mein claim kholein: trip timeline, photos, chat (sirf us booking ka, jab dispute ho).
2. Dono taraf se 24 ghante mein jawab maangein.
3. Faisla likhein (kitna paisa kisko wapas). Paisa app se nahi jaata; dono ko seedha hisaab karne ko kahein aur faisle ka record rakhein.
4. Baar-baar wahi shikayat ho to us driver/customer par risk signal dekhein.

## 5. Kuch baatein jo yaad rakhein
- Jo cheez abhi "record only" hai (payment, payout, KYC) usko asli paisa ya asli verification na samjhein.
- Rules, indexes aur hosting ka deploy aap ke kehne par hi hota hai; naya code tab tak live nahi hota. Last deploy ke baad kya badla: docs/PROGRESS.md.
- Koi sawal ho: docs/WHERE_IS_WHAT.md (kaun si cheez kahan), docs/TEST_PLAN.md (kya test karna hai), docs/SECURITY_REVIEW.md (suraksha), docs/ANDROID_RELEASE.md (app release).
