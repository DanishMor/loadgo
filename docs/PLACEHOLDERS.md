# Placeholders (P2)

The hosting pages (`hosting/`, `tool/templates/hosting/`) and the legal drafts in `docs/` carry open fields written as the word `add` inside square brackets (support e-mail and phone, Play Store link).

```powershell
.\tool\fill_placeholders.ps1 -Email "help@yourdomain.in" -Phone "+91 ..." -AppName "LoadGo" -Domain "yourdomain.in"   # look only
.\tool\fill_placeholders.ps1 -Email "help@yourdomain.in" -Phone "+91 ..." -DryRun false                              # write
dart run tool/apply_app_info.dart                                                                                     # keep hosting/ in step
.\tool\check_placeholders.ps1                                                                                         # what is left (exit 1 if any)
```

* Without `-Phone` the "email and phone" field becomes the e-mail only.
* `-PlayLink` (a `https://play.google.com/` link) fills the store-link field once the app is published.
* The scripts never deploy hosting. Run `firebase deploy --only hosting` yourself after the check says nothing is left.
* Before the first public release run `check_placeholders.ps1`; it should print "No open placeholders".
