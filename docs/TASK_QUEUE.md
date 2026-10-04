# Task queue (saved verbatim from the owner's message)

Order of work: finish Tasks 8, 9, 10 of the earlier 10-task list as they were running, then do Tasks 11 to 30 one after another by themselves. Permission is given in advance; do not ask in between. Resume after a restart from `docs/PROGRESS.md` and this file.

RULES (same as before):
1. Sirf FREE stack: Flutter + Firebase Auth + Firestore + free Dart/Flutter packages. Storage, Cloud Functions, FCM sender, Maps API, payment gateway, KYC APIs, SMS: sirf `// LATER(paid): ...` + docs note.
2. Har task ke baad: flutter analyze 0 issues, naye tests, flutter test pass, rules badle to rules tests pass, git commit. Har 3 tasks ke baad git push.
3. docs/PROGRESS.md har task ke baad update. Restart/limit ke baad PROGRESS.md + TASK_QUEUE.md se resume.
4. Naya text 12 languages mein. Paisa integer paise mein. Unsafe-without-server cheezein "record only" + `// TODO(functions)`.
5. Block ho to docs/BLOCKED.md mein likho, agle task par jao. Jo cheez pehle se bani ho use skip ya poora karo, duplicate mat banao.
6. customer/, driver/, admin/ ek dusre ko import na karein.
7. Firebase rules/indexes khud deploy mat karo. End mein batao deploy chahiye ya nahi.
8. Context bahut bhar jaye to PROGRESS.md update karke /compact karo aur aage badho.

TASK 11 - Scheduled booking: date/time chun kar advance booking, driver ko upcoming list, time aane par active. Cancel window config se.
TASK 12 - Empty truck posting (Vahak/BlackBuck style): driver "khali truck A se B, date, vehicle" post kare, customer browse karke request bheje. Return-load suggestion: delivery city se wapsi wale loads dikhao.
TASK 13 - Fleet owner role: ek owner ke kai vehicles aur drivers, driver invite/assign, har vehicle ka status aur earnings record, fleet dashboard. Role lock aur identity rules ke saath.
TASK 14 - Business account: company profile, team members (owner/booker), monthly statement record, cost center tag per booking.
TASK 15 - Repeat aur templates: pichli booking dobara, load templates, favourite drivers, driver block list (blocked driver ko us customer ke loads na dikhein).
TASK 16 - Ratings aur reviews dono taraf: categories (time, behaviour, maal ki safety), avg rating profile par, 3 se kam rating par admin flag.
TASK 17 - Damage/dispute claims: booking se claim kholna, text evidence + timeline, admin resolution flow, status customer aur driver dono ko.
TASK 18 - Invoices: free `pdf` package se GST invoice PDF device par banana/share, invoice number series, e-way bill fields (record only).
TASK 19 - Wallet ledger UI (record only): customer aur driver ki transaction history, filters, CSV export.
TASK 20 - Document expiry auto-actions: expired DL/insurance/permit par vehicle/driver auto "suspended", admin override, renew ke baad wapas.
TASK 21 - Advanced search: loads aur trucks ke liye route, date, weight, vehicle, price range filters + saved searches + pagination.
TASK 22 - Trip timeline aur ETA: har status ka time, offline distance se ETA estimate, delay hone par in-app alert.
TASK 23 - Notification center: read/unread, category-wise on/off settings, sab in-app reminders yahin.
TASK 24 - Abuse limits rules mein: ek user ek ghante mein max loads/bids/chat messages (timestamp counters), har form par input validation aur length limits.
TASK 25 - Admin user management: search, suspend/ban/unban, internal notes, force re-verify, sab actions audit log mein.
TASK 26 - Admin analytics: daily bookings, GMV record, cancellation rate, top routes, active drivers, city-wise chart, CSV export.
TASK 27 - Offline aur reliability: Firestore offline persistence, connectivity banner, failed actions par retry, consistent loading/empty/error states har screen par.
TASK 28 - Help aur legal: FAQ (12 languages), first-time onboarding slides, Terms, Privacy Policy, Refund/Cancellation policy screens, aur ACCOUNT DELETION flow (Play Store ke liye zaroori: data delete + Auth delete + identity_index cleanup).
TASK 29 - UI polish aur accessibility: dark mode, bade text par layout na toote, consistent theme, chhote phone (360px) par sab screens check.
TASK 30 - Final audit: poora regression test, ROADMAP_STATUS.md ke naye counts (Done/Partial/Todo-free/Paid), NEXT_TASKS.md update, README update, git push, aur mujhe chhoti summary: kya bana, kya blocked, deploy chahiye ya nahi.
