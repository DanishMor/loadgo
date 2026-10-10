<#
.SYNOPSIS
  Renames the app from one place. DryRun is the default: it only lists what would change.

.EXAMPLE
  .\tool\rename_app.ps1 -Name "NewName" -Tagline "Truck & Cargo Booking" -PackageId "in.newname.app"
  .\tool\rename_app.ps1 -Name "NewName" -PackageId "in.newname.app" -DryRun:$false

.NOTES
  What it changes (see docs/RENAME.md):
   - lib/core/app_info.dart          name, tagline (English; the 11 other scripts are reported, not guessed)
   - android/gradle.properties       loadgo.applicationId   (only when -PackageId is given)
   - README.md, docs/PLAY_*.md       the old name written in plain text
   - then runs tool/apply_app_info.dart, which writes the strings' {app} users, AndroidManifest label,
     web/index.html, web/manifest.json, hosting/*.html and ios Info.plist from app_info.dart.
  It never deploys and never touches keys or google-services.json.
#>
param(
  [Parameter(Mandatory = $true)][string]$Name,
  [string]$Tagline,
  [string]$PackageId,
  [string]$DryRun = 'true',   # default: list only. Apply with -DryRun false  (or -DryRun:$false in a shell)
  [string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$DryRun = -not ($DryRun -match '^(false|0|\$false|no)$')
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Text($path) { [System.IO.File]::ReadAllText($path, $utf8) }
function Write-Text($path, $text) { [System.IO.File]::WriteAllText($path, $text, $utf8) }

if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9 &\-]{1,29}$') {
  throw "Name must be 2-30 Latin letters, digits, space, & or - (the other scripts are set by hand in app_info.dart)."
}
if ($PackageId -and $PackageId -notmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$') {
  throw "PackageId must look like in.example.app (lowercase, dots, at least two parts)."
}

$infoPath = Join-Path $Root 'lib\core\app_info.dart'
$info = Read-Text $infoPath
$oldName = [regex]::Match($info, "static const String name = '([^']*)';").Groups[1].Value
$oldTagline = [regex]::Match($info, "static const String tagline = '([^']*)';").Groups[1].Value
if (-not $oldName) { throw "Could not read AppInfo.name from $infoPath" }

$changes = New-Object System.Collections.Generic.List[string]
$newFiles = @{}

# 1. app_info.dart
$text = $info.Replace("static const String name = '$oldName';", "static const String name = '$Name';")
if ($Tagline) { $text = $text.Replace("static const String tagline = '$oldTagline';", "static const String tagline = '$Tagline';") }
if ($text -ne $info) {
  $newFiles[$infoPath] = $text
  $changes.Add("lib/core/app_info.dart: name '$oldName' -> '$Name'" + $(if ($Tagline) { ", tagline -> '$Tagline'" } else { '' }))
}

# 2. package id
$gradlePath = Join-Path $Root 'android\gradle.properties'
if ($PackageId) {
  $g = Read-Text $gradlePath
  $oldId = [regex]::Match($g, 'loadgo\.applicationId=(\S+)').Groups[1].Value
  if ($oldId -and $oldId -ne $PackageId) {
    $newFiles[$gradlePath] = $g -replace 'loadgo\.applicationId=\S+', "loadgo.applicationId=$PackageId"
    $changes.Add("android/gradle.properties: applicationId '$oldId' -> '$PackageId'")
  }
}

# 3. plain-text mentions of the old name
if ($oldName -ne $Name) {
  $docs = @(Join-Path $Root 'README.md')
  $docs += Get-ChildItem -Path (Join-Path $Root 'docs') -Filter 'PLAY_*.md' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  foreach ($d in $docs) {
    if (-not (Test-Path $d)) { continue }
    $t = Read-Text $d
    $n = ([regex]::Matches($t, [regex]::Escape($oldName))).Count
    if ($n -gt 0) {
      $newFiles[$d] = $t.Replace($oldName, $Name)
      $changes.Add(("{0}: {1} mention(s) of '{2}'" -f ($d.Substring($Root.Length).TrimStart('\') -replace '\\', '/'), $n, $oldName))
    }
  }
}

# 4. what apply_app_info.dart will then write
$generated = @(
  'android/app/src/main/AndroidManifest.xml (android:label)',
  'ios/Runner/Info.plist (display name and permission sentences)',
  'web/index.html, web/manifest.json',
  'hosting/*.html (from tool/templates/hosting)',
  'strings: every {app} in the 12 languages is filled from AppInfo at run time (no file change)'
)

Write-Host ''
Write-Host $(if ($DryRun) { 'DRY RUN - nothing is written. Add -DryRun false to apply.' } else { 'APPLYING' })
Write-Host '--- files this script edits ---'
if ($changes.Count -eq 0) { Write-Host '(nothing to change)' } else { $changes | ForEach-Object { Write-Host "  $_" } }
Write-Host '--- files tool/apply_app_info.dart then regenerates ---'
$generated | ForEach-Object { Write-Host "  $_" }
Write-Host '--- by hand ---'
Write-Host "  AppInfo.nameInLanguage / taglines for hi, kn, ta, te, mr, gu, bn, pa, ks, ur keep the OLD name in their script until you write the new one."
if ($PackageId) {
  Write-Host "  NEW package id: register a NEW Android app in Firebase, download the new google-services.json,"
  Write-Host "  add the new SHA-1 and SHA-256 (docs/RENAME.md). Do this BEFORE the first Play Store upload."
}

if ($DryRun) { return }

foreach ($kv in $newFiles.GetEnumerator()) { Write-Text $kv.Key $kv.Value }
Push-Location $Root
try {
  & dart run tool/apply_app_info.dart
  if ($LASTEXITCODE -ne 0) { throw "tool/apply_app_info.dart failed" }
} finally { Pop-Location }
Write-Host 'Done. Now run: flutter test test/naming_test.dart'
