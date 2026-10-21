# Not free, or not mine to decide (Z21)

Things that stay open after Load 20 FINAL2, each with the reason. "Owner" means a decision or a step only the owner can take.

| Item | Why it is not done | What closes it |
|---|---|---|
| Deploy Cloud Functions (46) and the server switches | Needs the Blaze plan; `firebase deploy` is never run here | Owner: docs/BLAZE_GO_LIVE.md |
| Publish rules and indexes | Only the owner publishes (docs/RULES_PUBLISH.md). This is the most likely reason the LR register did not load on the phone | Owner |
| Push that rings a closed app, server wave, auto-accept | Functions + Blaze | Deploy, then flags |
| Photos and POD files (Storage) | Storage bucket needs Blaze | Owner |
| Online payment, SMS (DLT), KYC partner, e-way bill, Maps | Paid providers, keys the owner holds (docs/KNOWN_ISSUES.md) | Owner contracts and secrets |
| App Check enforcement | Console registration and a monitoring period | docs/SECURITY_DECISIONS.md |
| Admin Test lab (fake bidders, one-tap driver approval) | The rules only let a driver write their own bid; letting an admin write for other ids weakens them | Owner decision; server-side Function after Blaze (BLOCKED.md) |
| Extra fields on a new load (KNOWN_RISKS 1) | The `loads` create rule is at the 1000-expression limit; fixing it means splitting the rule (owner review, republish) or a Function | Owner review; RULES_CHANGES_NEEDED.md when designed |
| Vehicle papers readable by every signed-in user (KNOWN_RISKS 9) | Needs a private subcollection, a data migration and a rules change | Owner review |
| Queued trip code in plain preferences (KNOWN_RISKS 6) | `flutter_secure_storage` is free but must be checked on a real phone (Android Keystore) and is a dependency change | Owner phone check |
| LR register for the customer and fleet-owner side | Rules allow reading by customer and fleet owner, but which copy a non-issuer may see is a product decision | Owner decision |
| Firebase major upgrades (KGP warning) | Only majors are newer; major upgrades need regression and a phone check (docs/DEPENDENCIES.md) | Owner + a separate job |
| Dropping x86_64 from the release APK | Needs a release build and a phone to verify (docs/SIZE.md) | Owner |
| Real phone runs (docs/PHONE_SMOKE_SHEET.md), pentest, store listing, vakeel and CA review, keystore, package id, logo, translation review | Only the owner can do them (docs/OWNER_TODO.md) | Owner |
