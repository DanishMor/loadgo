# Testing on this laptop (Z11)

Rule: never the whole suite at once. Flutter tests only with `--concurrency=1`; free memory 3 GB or more (builds 5 GB). One emulator job at a time.

| Kaam | Command |
|---|---|
| Poora regression (batches, laptop jaage rehta hai) | `powershell -File tool/run_regression.ps1 -Out build/regression.txt` |
| Chhota batch size | `... -Size 15` |
| Restart ke baad wahin se | `... -From 7` (summary ki aakhri `batch N of M` line + 1; purani summary file ke aage nahi likhta jab `-From` 1 se zyada ho) |
| Sirf kuch files | `... -Only lr_` (path mein yeh text ho) |
| Sirf ek file | `flutter test --concurrency=1 test/diagnose_test.dart` |
| Status (sirf padhta hai) | `powershell -File tool/status.ps1` |
| Index check | `node tool/check_indexes.js` |
| Rules vs app fields | `node tool/rules_app_drift.js` |
| Rules tests (emulator, Java chahiye) | `sh run-tests.sh` inside `firestore_rules_test` |

## What the runner does
- Windows ko jaage rakhta hai (sirf is process ke liye, koi system setting nahi badalti).
- Har batch ka log `build/regression_batch_N.log`; summary `build/regression.txt`. Poora hone par aakhri line `DONE`.
- Stall watchdog: agar batch ka log `-StallMinutes` (12) minute tak nahi badhta, wahi batch band karke `STALLED` likhta hai aur aage badhta hai.
- Sleep gap: agar 30 second ke intezaar mein 5 minute se zyada nikle (laptop so gaya) to `SLEEP GAP` likhta hai aur stall timer reset karta hai, taaki neend ko hang na samjha jaye.
- Kam memory (2 GB se neeche) par batch do aadhe hisson mein chalta hai.
- Purana naam `tool/regression_batches.ps1` ab isi ko call karta hai.

## status.ps1 kya dikhata hai
Time, free memory, chalte test/build processes, sabse nayi regression summary, git (branch, last 5, uncommitted), task prefix ke hisaab se commits, `docs/RESUME.md` ke LAST_DONE aur NEXT, aur phones (sirf agar adb server pehle se chal raha ho; yeh script adb ko khud start nahi karta).
