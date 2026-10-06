Ye MASTER-2 instruction hai. Pehle ise docs/MASTER_PLAN_2.md mein bina badle save karke commit karo. Permission mat maango, beech mein mat ruko jab tak sab khatam na ho.

PHASE 1 - GAP AUDIT (docs/GAP_AUDIT.md):
Code aur docs/ROADMAP_STATUS.md dekh kar in 8 angles se har kami likho. Jo pehle se bana hai use skip karo:
1. Customer journey (post se delivery tak) mein kahan user atakega ya confuse hoga
2. Driver journey (signup se payout request tak), kam padhe-likhe driver ke liye bhi
3. Porter, Uber, Rapido, Vahak, BlackBuck, Lorry-wale apps ke common features jo hamare paas nahi
4. Production-readiness: crash reporting, force update, maintenance mode, feature flags, error messages, empty states, slow network
5. Security: har collection ki rules review, abuse paths (promo, credits, referral, bids, chat spam, fake ratings)
6. Cost control: Firestore reads/writes kam karo (reminder refresh gap, nearby queries ki 9 live streams, bade listeners, pagination)
7. Play Store ready: privacy policy, terms, data safety, account deletion link, app icon/splash, permission texts
8. Quality: slow/old phone, 360px screen, bada font, dark mode, 12 languages ki galat ya adhoori lines
Har gap ko FREE ya PAID mark karo. Sirf FREE wale aage jayenge.

PHASE 2 - TASKS (docs/TASK_QUEUE_3.md, Task 41 se aage, har task mein 8-15 items). Ye zaroor shamil karo (jo bana hai wo skip):
- Firestore reads kam karna. Promo, credits, referral ko admin switch config/offers ke peeche default OFF rakho
- Firebase Crashlytics, Analytics, Remote Config (force update, maintenance mode, feature flags). google-services setup docs mein likho
- Load WhatsApp/share (share_plus), booking confirm hone ke baad hi tap-to-call, Google Maps navigation ke liye url_launcher (koi API key nahi), load ka share link
- Peak/night/festival surge admin config se
- Driver Simple Mode: bade button, icons, kam text, Hindi voice input (speech_to_text) load aur bid form mein
- Offline toll aur fuel estimate table (estimate likha ho), trip ka total cost preview
- LoadGo Sahayak: in-app rule-based assistant dono apps mein, 12 languages + Hinglish, intents: meri booking, load post pre-fill, nearby loads, OTP/bid/payment/cancel FAQ, support ticket, AssistantEngine interface (// LATER(paid): LLM engine), samajh na aaye wale sawaal admin log mein
- Driver earnings summary (daily/weekly), trip history filters, customer spending summary, cancel reasons, goods value declaration, in-app feedback form, rating reminder, app-wide search
- Admin: support reply templates, bulk actions, user/booking export, system health screen (counts, errors)
- Demo/seed data tool (sirf testing ke liye, admin-only) aur docs/TEST_PLAN.md (customer, driver, fleet, admin ka manual test checklist)
- Docs: docs/PLAY_STORE_CHECKLIST.md, docs/PRIVACY_POLICY.md aur docs/TERMS.md (public hosting ke liye Firebase Hosting steps), docs/PAID_UPGRADE_PLAN.md (har Paid row: kaunsi service, kab, andaza kharch)
- Phase 1 ke har naye FREE gap ke liye aur tasks

PHASE 3 - Sab tasks ek ke baad ek karo.

PHASE 4 - LOOP: Phase 1 ka audit dobara chalao. Naya FREE gap mile to TASK_QUEUE_3.md mein jodo aur karo. Tab tak dohraao jab tak ek bhi FREE gap na bache. Aakhri mein docs/GAP_AUDIT.md mein likho "Free gaps: 0".

RULES:
1. Sirf FREE stack: Flutter + Firebase Auth + Firestore + Hosting/Crashlytics/Analytics/Remote Config + free Dart/Flutter packages. Storage, Cloud Functions, FCM sender, Maps API, payment gateway, KYC APIs, SMS, masked calling, AI APIs: sirf `// LATER(paid): ...` + docs note.
2. Har task ke baad: flutter analyze 0 issues, naye tests, flutter test pass, rules badle to rules tests pass, git commit. Har 3 tasks ke baad git push.
3. docs/PROGRESS.md har task ke baad update.
4. Naya text 12 languages mein. Paisa integer paise mein. Server ke bina unsafe cheez "record only" + `// TODO(functions)`.
5. Block ho to docs/BLOCKED.md, agle par jao. Duplicate mat banao, jo bani hai use poora karo.
6. customer/, driver/, fleet/, admin/ ek dusre ko import na karein.
7. Rules/indexes khud deploy mat karo.
8. Context bhar jaye to PROGRESS.md update karke /compact karo.
9. Restart/limit ke baad MASTER_PLAN_2.md, PROGRESS.md, TASK_QUEUE_3.md padh kar wahin se resume.

FINAL: regression test, ROADMAP_STATUS.md aur GAP_AUDIT.md ke final counts, README update, git push. Phir summary: kya bana, kitne gaps band hue, rules/indexes deploy chahiye ya nahi.
