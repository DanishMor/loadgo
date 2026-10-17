<#
.SYNOPSIS
  Read-only check before going live (G44). It changes nothing and deploys nothing.

.DESCRIPTION
  Prints: which Firebase account and project the CLI is using, whether git is clean, whether the
  local secret files are in the right state (a key present or not, never its value), which feature
  switches exist in the code and their defaults, and the go-live checklist from docs/GO_LIVE_RUNBOOK.md.
  The live value of each switch is in the Admin panel (Admin > Features); the command line cannot read it
  without a service account, which this script never asks for.

.EXAMPLE
  powershell -File tool\golive_check.ps1
#>
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)
$problems = 0
function Say($t) { Write-Host $t }
function Ok($t) { Write-Host "  [ok]   $t" }
function Warn($t) { Write-Host "  [todo] $t"; $script:problems++ }

Say '== 1. Firebase login and project =='
$fb = $null
if (Get-Command firebase -ErrorAction SilentlyContinue) { $fb = 'firebase' }
elseif (Test-Path 'firestore_rules_test\node_modules\.bin\firebase.cmd') { $fb = (Resolve-Path 'firestore_rules_test\node_modules\.bin\firebase.cmd').Path }
if ($fb) {
  $accounts = (& $fb login:list 2>&1 | Out-String).Trim()
  if ($accounts -match 'No authorized accounts') { Warn 'not signed in: run  firebase login' } else { Ok 'signed in:'; $accounts -split "`n" | Select-Object -First 4 | ForEach-Object { Say "         $($_.Trim())" } }
  $use = (& $fb use 2>&1 | Out-String).Trim()
  if ($use -match 'No active project|Error') { Warn 'no active project: run  firebase use <project-id>' } else { Ok "active project: $($use -split "`n" | Select-Object -First 1)" }
} else {
  Warn 'firebase CLI not found: npm install -g firebase-tools'
}

Say ''
Say '== 2. The laptop =='
$dirty = @(git status --short | Where-Object { $_ -notmatch 'GeneratedPluginRegistrant|generated_plugin' })
if ($dirty.Count -eq 0) { Ok 'git is clean' } else { Warn "git has $($dirty.Count) changed file(s): commit or stash before a release build" }
if (Test-Path 'functions\.secret.local') { Warn 'functions\.secret.local exists (a leftover of an emulator run): delete it' } else { Ok 'no leftover functions\.secret.local' }
foreach ($f in @('android\key.properties')) { if (Test-Path $f) { Ok "$f exists (never committed: git ignores it)" } else { Warn "$f missing: needed for a signed release build (docs/SIGNING.md)" } }
if (Test-Path 'android\local.properties') {
  $hasMaps = [bool](Select-String -Path 'android\local.properties' -Pattern '^MAPS_API_KEY=.+' -Quiet)
  if ($hasMaps) { Ok 'MAPS_API_KEY is set in android\local.properties (value not shown)' } else { Say '  [info] MAPS_API_KEY not set: the trip map stays empty; fine while the maps switch is OFF' }
}
$tracked = @(git ls-files | Where-Object { $_ -match '(^|/)(key\.properties|local\.properties|\.secret\.local|.*\.jks|.*\.keystore)$' })
if ($tracked.Count -eq 0) { Ok 'no key or secret file is tracked by git' } else { Warn "tracked secret-like file(s): $($tracked -join ', ')" }

Say ''
Say '== 3. Feature switches in the code (all OFF unless the pilot default says ON) =='
$src = Get-Content lib\core\features\features.dart -Raw
$specs = [regex]::Matches($src, 'FeatureSpec\(FeatureKey\.(\w+), pilotOn: (true|false)(?:, normalOn: (true|false))?\)')
foreach ($m in $specs) { Say ('  {0,-22} pilot={1,-5} normal={2}' -f $m.Groups[1].Value, $m.Groups[2].Value, $(if ($m.Groups[3].Success) { $m.Groups[3].Value } else { 'true' })) }
Say ''
Say '  The live value of each switch: Admin panel > Features. Turn them on in the order of docs/GO_LIVE_RUNBOOK.md step 6.'

Say ''
Say '== 4. Checklist (from docs/GO_LIVE_RUNBOOK.md) =='
if (Test-Path docs\GO_LIVE_RUNBOOK.md) {
  Get-Content docs\GO_LIVE_RUNBOOK.md | Where-Object { $_ -match '^## \d' } | ForEach-Object { Say "  [ ] $($_ -replace '^## ','')" }
} else { Warn 'docs\GO_LIVE_RUNBOOK.md missing' }

Say ''
if ($problems -eq 0) { Say 'Nothing to fix. Follow docs/GO_LIVE_RUNBOOK.md from step 1.' } else { Say "$problems thing(s) to look at (marked [todo])." }
exit 0
