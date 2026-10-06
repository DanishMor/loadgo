# MASTER PLAN (saved verbatim from the owner's message)

Ye MASTER instruction hai. Ise pehle docs/MASTER_PLAN.md mein bina badle save karke commit karo. Permission mat maango, beech mein mat ruko, jab tak sab khatam na ho.

PHASE 1 - Adhoora kaam:
Task 28 poora karo (help, FAQ, legal, onboarding, account deletion: Firestore data + Auth delete + identity_index cleanup). Phir docs/TASK_QUEUE.md ke Task 29 aur 30.

PHASE 2 - Poori free list banao (kuch chhootna nahi chahiye):
Ye 4 jagah se har bacha hua free kaam nikalo:
a) docs/ROADMAP_STATUS.md ke saare "Partial" aur "Todo-free" rows
b) docs/NEXT_TASKS.md ke saare free items
c) docs/BLOCKED.md ke items (dobara check karo, jo ab free mein ho sakta hai)
d) code mein `TODO` comments (grep -rn "TODO" lib test), `TODO(functions)` aur `LATER(paid)` chhod kar
Sabko module ke hisaab se Task 31 se aage bade tasks (har task 8-15 items) mein baanto. docs/TASK_QUEUE_2.md mein save karo, har task ke saath uske row codes/file names. Commit.

PHASE 3 - Sab tasks karo, ek ke baad ek.

PHASE 4 - Loop check:
Sab tasks ke baad ROADMAP_STATUS.md dobara gino. Agar koi bhi row abhi bhi "Partial" ya "Todo-free" hai aur uska free hissa ban sakta hai, to naye tasks banao (TASK_QUEUE_2.md mein jodo) aur karo. Ye tab tak dohraao jab tak free ke liye kuch na bache. Jo row sirf paid service ke bina poori nahi ho sakti, uska free hissa banao aur baaki ke liye "Paid/Later" + reason likho.

RULES:
1. Sirf FREE stack: Flutter + Firebase Auth + Firestore + free Dart/Flutter packages. Storage, Cloud Functions, FCM sender, Maps API, payment gateway, KYC APIs, SMS, masked calling, insurance, AI APIs: sirf `// LATER(paid): ...` + docs note.
2. Har task ke baad: flutter analyze 0 issues, naye tests, flutter test pass (exit code seedha check karo), rules badle to rules tests pass, git commit. Har 3 tasks ke baad git push.
3. docs/PROGRESS.md har task ke baad update.
4. Naya text 12 languages mein. Paisa integer paise mein. Server ke bina unsafe cheez "record only" + `// TODO(functions)`.
5. Block ho to docs/BLOCKED.md mein reason, agle par jao. Duplicate mat banao, jo bani hai use poora karo.
6. customer/, driver/, fleet/, admin/ ek dusre ko import na karein.
7. Rules/indexes khud deploy mat karo.
8. Context bhar jaye to PROGRESS.md update karke /compact karo.
9. Restart/limit ke baad: git status, PROGRESS.md, MASTER_PLAN.md, TASK_QUEUE_2.md padh kar wahin se resume.

FINAL: Poora regression test, ROADMAP_STATUS.md final counts (Done / Paid-Later, Partial aur Todo-free free ke liye 0), NEXT_TASKS.md mein sirf paid items with cost reason, README update, git push. Phir mujhe summary: kya bana, kitne rows Done, kitne paid ki wajah se baaki, rules/indexes deploy chahiye ya nahi.
