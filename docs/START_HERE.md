# START HERE (owner ke liye)

Is repo mein bahut saare docs hain. Yeh page batata hai kaun sa doc kis kaam ka hai aur kab padhna hai. Pehle `OWNER_TODO.md` kholein: usme aapke saare non-code kaam ek order mein hain.

## 1. Roz / abhi
| Doc | Ek line mein kaam | Kab padhein |
|---|---|---|
| OWNER_TODO.md | Aapke saare non-code kaam, checkbox ke saath, ek order mein | Sabse pehle, aur har kaam ke baad |
| RESUME.md | Claude kahan ruka tha (LAST_DONE aur NEXT) | Restart ke baad |
| PHONE_SMOKE_SHEET.md | Do phone par 31 step ka test, pass/fail ke khane ke saath | Naya APK lagane ke baad |
| PHONE_TOOLS.md | `tool/phone.ps1`: phone check, install, logs | Phone par APK lagate waqt |
| RULES_PUBLISH.md | Rules aur indexes publish karne ke steps, test list, rollback | Publish se pehle |
| TESTING.md | Tests aur regression kaise chalayein, status.ps1 | Laptop par test chalane se pehle |

## 2. Go-live ka raasta
| Doc | Kaam | Kab |
|---|---|---|
| FIREBASE_CONSOLE_CHECKLIST.md | Firebase Console mein kya kya set karna hai | Pehle hafte |
| MANUAL_SETUP.md, MANUAL_TODO.md | Haath se karne wale setup aur paid kaam | Jab OWNER_TODO bole |
| BLAZE_GO_LIVE.md | Blaze plan aur functions ka ordered checklist | Blaze lene se pehle |
| COST_WATCH.md | Kharcha kahan se aata hai, budget alert | Blaze ke saath |
| GO_LIVE_RUNBOOK.md | Go-live ke din ka runbook | Go-live se ek din pehle |
| RELEASE_CANDIDATE.md | Release ki poori checklist (sections G aur H phone rows) | Release se pehle |
| ANDROID_RELEASE.md, SIGNING.md | APK/appbundle aur keystore | Release build se pehle |
| PLAY_STORE_CHECKLIST.md, PLAY_SUBMISSION_STEPS.md, PLAY_LISTING.md | Play Store submit karna | Play Console ke time |
| PILOT_KIT.md, ADDON_PILOT.md, OWNER_GUIDE.md | Pilot kaise chalayein, roz ki checklist, admin screens | Pilot ke pehle aur dauran |

## 3. Naam, legal, brand
| Doc | Kaam | Kab |
|---|---|---|
| NAME_CHECKLIST.md, NAMING.md, RENAME.md, PLACEHOLDERS.md | Naam ka check, rename tool, placeholders (support email waghera) | Naam final karte waqt |
| LOGO_BRIEF.md, ICON_AND_SPLASH.md, BRAND.md | Logo brief, icon, brand rules | Designer ko dene se pehle |
| LEGAL_QUESTIONS.md, WALLET_LEGAL.md | Vakeel aur CA ke sawaal | Vakeel/CA se milne se pehle |
| TERMS.md, PRIVACY_POLICY.md, REFUND_POLICY.md, DRIVER_AGREEMENT.md, TRANSPORTER_AGREEMENT.md | Draft policies (vakeel se review zaroori) | Publish se pehle |
| TRANSLATION_REVIEW.md | Bhasha review ka tareeka aur CSV files | Translation review ke time |

## 4. Safety, security, risk
| Doc | Kaam | Kab |
|---|---|---|
| KNOWN_RISKS.md, KNOWN_ISSUES.md, LAUNCH_RISKS.md | Jo abhi pakka nahi ya limit hai | Go/no-go se pehle |
| SECURITY_SCORECARD.md, THREAT_MODEL.md, SECURITY_DECISIONS.md | Security ki sthiti aur faisle | Review ke time |
| PENTEST_CHECKLIST.md, VULNERABILITY_DISCLOSURE.md | Bahar ke tester ke liye | Pentest karwate waqt |
| INCIDENT_RESPONSE.md, ALERT_THRESHOLDS.md | Kuch toote ya attack ho to kya karein | Incident par |
| OTP_SECURITY.md, SECRETS_AUDIT.md, SECRETS_SCAN_PART5.md | OTP limits aur secrets ki jaanch | Security review par |
| RULES_CONTRACT.md, RULES_APP_DRIFT.md, RULES_CHANGES_NEEDED.md | Rules vs app ka mel, owner review ki cheezein | Rules badalne se pehle |
| INDEX_CHECK.md | Firestore indexes ka mel | Indexes publish se pehle |

## 5. Wallet aur paisa
WALLET_GO_LIVE.md (kab asli paisa chalne dein), WALLET_SECURITY.md, WALLET_LEGAL.md, WALLET_PLAN.md, GST_EWAY.md, PAID_ADAPTERS.md, KYC_PARTNER_CHECKLIST.md, SMS_SETUP.md. Flags OFF rahte hain jab tak aap khud ON na karein.

## 6. Developer ke liye (jab tak zarurat na ho mat padhein)
ARCHITECTURE.md, DESIGN_SYSTEM.md, FLOW_SPEC.md, FUNCTIONS.md, FUNCTIONS_SECURITY.md, DATA_MAP.md, WHERE_IS_WHAT.md (har feature kis screen par, flags), SCREEN_INVENTORY.md, DEPENDENCIES.md, PERFORMANCE.md, BUG_REPORT.md, PROGRESS.md, DECISIONS.md, BLOCKED.md, TEST_PLAN.md, aur purane `MASTER_PLAN_*.md`, `TASK_QUEUE*.md` (sirf itihaas).
