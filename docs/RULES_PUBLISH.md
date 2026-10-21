# Rules aur indexes publish karne ke steps (Z6)

Yeh kaam OWNER karta hai. Claude kabhi `firebase deploy` nahi chalata. Rules galat publish ho jaye to poori app (load post, bid, trip) ruk sakti hai, isliye is order mein chalein.

Pehle ek baat: LR register par "taking longer than usual" ka sabse sambhav karan yeh hai ki naye rules / indexes Firebase par publish nahi hue (repo mein query aur rules mel khaate hain, dekho Z2 in docs/DECISIONS.md). Publish ke baad bhi na chale to app mein Help > "Diagnose problem" chalao aur report bhejo.

## A. Publish se pehle (10 minute)
1. Firebase Console > Firestore Database > Rules kholo. Maujooda rules ka poora text select karke copy karo.
2. Ek file mein save karo, jaise `C:\Users\<aap>\load20-backup\rules_BEFORE_<date>.txt` (repo ke bahar). Yeh rollback ka sabse pakka tareeka hai.
3. Indexes: Console > Firestore > Indexes mein jo composite indexes dikh rahe hain unka screenshot lo.
4. Laptop par: `node tool/check_indexes.js` (0 missing aana chahiye) aur `sh run-tests.sh` inside `firestore_rules_test` (sab green).
5. Koi trip chal rahi ho to publish ko baad mein karo (kam traffic ka time chuno).

## B. Publish (do tareeke)
**Console se (sabse aasaan):** Firestore > Rules mein `firestore.rules` ka poora text paste karo > Publish. Phir Firestore > Indexes mein `firestore.indexes.json` ke naye indexes haath se banao, ya CLI chalao.
**CLI se:** `.\tool\deploy_rules.ps1 -Account "<aapka email>" -Project "loadgo-defc2"` (yeh script account check karti hai, YES likhwati hai).
Indexes banne mein kuch minute lagte hain; Console mein status "Building" se "Enabled" hone tak ruko.

## C. Publish ke turant baad: phone par test (2 phone: customer + driver)
Har row RULES_CONTRACT ke flows se juda hai (docs/RULES_CONTRACT.md, 65 flows). Sab ek ke baad ek, jaise hi rules live hon.

| # | Phone par kya karo | Rules ka flow (contract) | Pass | Fail par bhejo |
|---|---|---|---|---|
| 1 | Customer: normal load post karo (budget ke bina, phir budget ke saath) | `loads` plain | [ ] | Diagnose report + screen ka code (E-PERM?) |
| 2 | Customer: freight load fare estimate ke saath, promo code ke saath | `loads` + `promos` | [ ] | wahi |
| 3 | Customer: instant load post karo | `loads` instant | [ ] | wahi |
| 4 | Customer: rental / movers load post karo | `loads` rental, movers | [ ] | wahi |
| 5 | Driver: load par bid bhejo, phir edit, phir withdraw | `offers` send, edit, withdraw | [ ] | wahi |
| 6 | Customer: counter bhejo; driver counter accept kare | `offers` counter | [ ] | wahi |
| 7 | Customer: bid select / accept kare; driver confirm kare | `offers` select, accept; `bookings` | [ ] | wahi |
| 8 | Driver: instant load accept karo | `bookings` instant | [ ] | wahi |
| 9 | Driver: trip steps (arriving, loading, picked up, in transit, unloading, delivered) | `bookings` steps | [ ] | wahi |
| 10 | Trip OTP: pickup aur delivery par OTP daalo | `otp_attempts` | [ ] | wahi |
| 11 | Chat: dono taraf se message bhejo | `messages` | [ ] | wahi |
| 12 | Bilty: LR banao, 3 copy dekho, phir LR register kholo (list aani chahiye) | `lrs`, `lr_series`, `lr_shares` | [ ] | Register ka Diagnose report |
| 13 | Support: ticket banao, escalate, close | `tickets` | [ ] | wahi |
| 14 | Rating do (customer aur driver) | `ratings` | [ ] | wahi |
| 15 | Payment: customer "paid" mark kare, driver confirm kare | `bookings`, `ledger` | [ ] | wahi |
| 16 | Tip, claim, SOS (test number se), trip share link | `tips`, `claims`, `sos_alerts`, `trip_shares` | [ ] | wahi |
| 17 | Cancel: driver pickup se pehle cancel kare; customer open load cancel kare | cancel flows | [ ] | wahi |
| 18 | Wallet / payout request (sirf agar `walletHub` flag ON ho) | `payouts` | [ ] | wahi |
| 19 | Driver: empty truck post, vehicle add | `truck_posts`, `vehicles` | [ ] | wahi |

Har flow ke liye: Help > Diagnose problem > Run check chalao, sab OK aana chahiye. Koi row E-PERM de to turant rollback (neeche).

## D. Rollback
1. Console > Firestore > Rules > purana text jo A.2 mein save kiya tha paste karo > Publish.
2. Console mein Rules ke "version history" ka option hota hai: UNVERIFIED (is repo se pakka nahi pata ki kitne purane version dikhte hain aur restore ka button kaisa hai). Isliye A.2 ki file par bharosa rakho.
3. Indexes rollback ki zarurat nahi: extra index nuksaan nahi karta. Hatana ho to Console > Indexes se delete karo.
4. Rollback ke baad bhi dikkat ho to `docs/INCIDENT_RESPONSE.md` dekho.

## E. Kya yaad rakhna
- `firestore.rules` mein koi bhi badlav tabhi publish karo jab `sh run-tests.sh` poora green ho.
- Rules ka koi badlav jo owner review chahta hai `docs/RULES_CHANGES_NEEDED.md` mein likha jata hai (abhi koi nahi, Z5 ke baad dekho).
