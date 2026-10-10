<#
.SYNOPSIS
  Fills the "[add ...]" placeholders in hosting pages, their templates and the docs. DryRun is the default.

.EXAMPLE
  .\tool\fill_placeholders.ps1 -Email "help@example.in" -AppName "LoadGo" -Domain "loadgo.in"
  .\tool\fill_placeholders.ps1 -Email "help@example.in" -Phone "+91 98xxxxxx" -DryRun false

.NOTES
  Placeholders it knows:
    [add support email and phone]            -> "<Email>, <Phone>"  (only the email when -Phone is not given)
    [add support email]                      -> <Email>
    [add Play Store link after publishing]   -> <PlayLink>          (only when -PlayLink is given)
    [add app name]                           -> <AppName>
    [add domain] / [add website]             -> <Domain>
  Anything else that starts with "[add" is reported and left alone. Run tool\check_placeholders.ps1 to list what is left.
  After it runs on tool/templates/hosting, run:  dart run tool/apply_app_info.dart   (keeps hosting/ in step).
  It never deploys hosting.
#>
param(
  [string]$Email,
  [string]$AppName,
  [string]$Domain,
  [string]$Phone,
  [string]$PlayLink,
  [string]$DryRun = 'true',
  [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$isDry = -not ($DryRun -match '^(false|0|\$false|no)$')
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($Email -and $Email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw "Email does not look like an e-mail address." }
if ($Domain -and $Domain -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { throw "Domain must look like example.in (no https://, no path)." }
if ($PlayLink -and $PlayLink -notmatch '^https://play\.google\.com/') { throw "PlayLink must start with https://play.google.com/" }

# Order matters: the longer token first.
$rules = New-Object System.Collections.Generic.List[object]
if ($Email) {
  $with = if ($Phone) { "$Email, $Phone" } else { $Email }
  $rules.Add(@{ Token = '[add support email and phone]'; Value = $with })
  $rules.Add(@{ Token = '[add support email]'; Value = $Email })
}
if ($PlayLink) { $rules.Add(@{ Token = '[add Play Store link after publishing]'; Value = $PlayLink }) }
if ($AppName) { $rules.Add(@{ Token = '[add app name]'; Value = $AppName }) }
if ($Domain) {
  $rules.Add(@{ Token = '[add domain]'; Value = $Domain })
  $rules.Add(@{ Token = '[add website]'; Value = $Domain })
}
if ($rules.Count -eq 0) { Write-Host 'Nothing to fill: give at least -Email, -AppName, -Domain or -PlayLink.'; return }

$targets = @()
foreach ($dir in 'hosting', 'tool\templates\hosting', 'docs') {
  $p = Join-Path $Root $dir
  if (Test-Path $p) { $targets += Get-ChildItem -Path $p -Include *.html, *.md -Recurse -File }
}
# Plan documents quote the tokens on purpose.
$skip = 'MASTER_PLAN_7.md', 'WINDOWS_FINISH.md', 'PLACEHOLDERS.md', 'DECISIONS.md', 'PROGRESS.md'
$targets = $targets | Where-Object { $skip -notcontains $_.Name }

Write-Host $(if ($isDry) { 'DRY RUN - nothing is written. Add -DryRun false to apply.' } else { 'APPLYING' })
$total = 0
foreach ($f in $targets) {
  $text = [System.IO.File]::ReadAllText($f.FullName, $utf8)
  $new = $text; $n = 0
  foreach ($r in $rules) {
    $c = ([regex]::Matches($new, [regex]::Escape($r.Token))).Count
    if ($c -gt 0) { $new = $new.Replace($r.Token, $r.Value); $n += $c }
  }
  if ($n -gt 0) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
    Write-Host ("  {0}: {1} placeholder(s)" -f $rel, $n)
    $total += $n
    if (-not $isDry) { [System.IO.File]::WriteAllText($f.FullName, $new, $utf8) }
  }
}
Write-Host "Total: $total"
if ($Email -and -not $Phone) { Write-Host 'Note: "[add support email and phone]" became the e-mail only (no -Phone given).' }
Write-Host 'Next: powershell -File tool\check_placeholders.ps1   (what is still open)'
