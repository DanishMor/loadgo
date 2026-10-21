<#
.SYNOPSIS
  Changes the Android application id (package id) everywhere it is written in the repo. DRY RUN by default.

.EXAMPLE
  .\tool\change_package_id.ps1 -NewId in.load20.app                 (dry run: lists what would change)
  .\tool\change_package_id.ps1 -NewId in.load20.app -Apply          (writes the change)
  .\tool\change_package_id.ps1 -NewId in.load20.app -Apply -MoveNamespace   (also moves the Kotlin package folder and namespace)

.NOTES
  Changed: android\gradle.properties (loadgo.applicationId), the Play Store link in lib, linux APPLICATION_ID, tests and docs that
  hard-code the old id. With -MoveNamespace also: namespace in android\app\build.gradle.kts, the package line of MainActivity.kt and its
  folder (kotlin\<id as folders>). Old history docs (MASTER_PLAN_*, PROGRESS.md) are left as they are.
  NOT changed (owner steps, printed at the end): google-services.json, Firebase app, SHA keys, assetlinks.json, Play Console.
  The deep-link intent filter in AndroidManifest.xml uses the web host, not the package id, so it needs no change.
  Use -Root to run on a copy of the repo (the test does this).
#>
param(
  [Parameter(Mandatory = $true)][string]$NewId,
  [switch]$Apply,
  [switch]$MoveNamespace,
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path
Set-Location $Root

$pattern = '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
if ($NewId -notmatch $pattern) { throw "Id '$NewId' theek nahi: chhote akshar, ankh, _ aur dots (jaise in.load20.app)." }
if ($NewId -like 'com.example.*') { throw "Play Store com.example.* accept nahi karta." }

$propsPath = Join-Path $Root 'android\gradle.properties'
$old = $null
foreach ($line in Get-Content $propsPath) { if ($line -match '^\s*loadgo\.applicationId\s*=\s*(\S+)\s*$') { $old = $Matches[1] } }
if (-not $old) { throw 'android\gradle.properties mein loadgo.applicationId nahi mila.' }
if ($old -eq $NewId) { Write-Host 'Id pehle se yahi hai. Kuch nahi badla.'; exit 0 }

$skipDirs = @('\.git\', '\build\', '\.dart_tool\', '\node_modules\', '\coverage\', '\.gradle\')
$skipNames = @('google-services.json', 'PROGRESS.md')
$exts = @('.kts', '.kt', '.java', '.properties', '.xml', '.dart', '.md', '.txt', '.json', '.ps1', '.js', '.cmake', '.yml', '.yaml')
$candidates = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
  $p = $_.FullName
  $ok = $exts -contains $_.Extension.ToLower() -or $_.Name -eq 'CMakeLists.txt'
  if ($ok) { foreach ($d in $skipDirs) { if ($p.Contains($d)) { $ok = $false } } }
  if ($ok -and ($skipNames -contains $_.Name)) { $ok = $false }
  if ($ok -and $_.Name -like 'MASTER_PLAN*') { $ok = $false }
  if ($ok -and $_.FullName -like '*tool\change_package_id.ps1') { $ok = $false }
  $ok
}

$oldFolder = ($old -replace '\.', '\')
$newFolder = ($NewId -replace '\.', '\')
$oldSlash = ($old -replace '\.', '/')
$newSlash = ($NewId -replace '\.', '/')

$changed = @()
foreach ($f in $candidates) {
  $text = [IO.File]::ReadAllText($f.FullName)
  $new = $text
  # The Kotlin namespace line and the package line only move with -MoveNamespace.
  if (-not $MoveNamespace) {
    # Replace everything except those protected spots: split around them (odd parts are the protected matches).
    $parts = [regex]::Split($new, '(namespace\s*=\s*"' + [regex]::Escape($old) + '"|(?m)^package ' + [regex]::Escape($old) + '\s*$|kotlin/' + [regex]::Escape($oldSlash) + ')')
    for ($i = 0; $i -lt $parts.Count; $i += 2) { $parts[$i] = $parts[$i].Replace($old, $NewId) }
    $new = -join $parts
  } else {
    $new = $new.Replace($old, $NewId).Replace($oldSlash, $newSlash)
  }
  if ($new -ne $text) {
    $n = ([regex]::Matches($text, [regex]::Escape($old))).Count
    $changed += [pscustomobject]@{ Path = $f.FullName; Count = $n; Text = $new }
  }
}

Write-Host ("Purani id: $old  ->  nayi id: $NewId" + $(if ($MoveNamespace) { '  (namespace aur Kotlin folder bhi)' } else { '' }))
foreach ($c in $changed) { Write-Host ("  {0}  ({1} jagah)" -f $c.Path.Substring($Root.Length + 1), $c.Count) }

$kt = Join-Path $Root ('android\app\src\main\kotlin\' + $oldFolder)
if ($MoveNamespace -and (Test-Path $kt)) { Write-Host "  FOLDER MOVE: android\app\src\main\kotlin\$oldFolder -> kotlin\$newFolder" }

if (-not $Apply) {
  Write-Host ''
  Write-Host 'DRY RUN: kuch likha nahi gaya. Likhne ke liye -Apply lagayein.'
} else {
  foreach ($c in $changed) { [IO.File]::WriteAllText($c.Path, $c.Text) }
  if ($MoveNamespace -and (Test-Path $kt)) {
    $dest = Join-Path $Root ('android\app\src\main\kotlin\' + $newFolder)
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem $kt | ForEach-Object { Move-Item $_.FullName (Join-Path $dest $_.Name) }
    # Remove the now empty old folders (from the leaf upward) but never the kotlin folder itself.
    $stop = Join-Path $Root 'android\app\src\main\kotlin'
    $d = $kt
    while ($d.Length -gt $stop.Length -and (Test-Path $d) -and -not (Get-ChildItem $d -Force)) {
      Remove-Item $d
      $d = Split-Path -Parent $d
    }
  }
  Write-Host ''
  Write-Host "Likh diya: $($changed.Count) file."
}

Write-Host ''
Write-Host '=== FIREBASE / STORE STEPS (aapko haath se karne hain) ==='
Write-Host " 1. Firebase Console > Project settings > Add app > Android: package name = $NewId"
Write-Host ' 2. SHA-1 aur SHA-256 jodein (keystore ka: keytool -list -v ... ; Play App Signing ke baad Google ki key ka bhi).'
Write-Host ' 3. Naya google-services.json download karke android\app\ mein rakhein (purani file ko replace karein; commit se pehle docs/SECRETS_AUDIT.md dekhein).'
Write-Host ' 4. Phone login ke test numbers (+91 9999900001/2/3, code 123456) naye app ke liye bhi chalte hain kyunki ve project ke Authentication mein hain; check kar lein.'
Write-Host ' 5. hosting\.well-known\assetlinks.json mein package_name = nayi id aur SHA-256 (template: docs\assetlinks.template.json), phir hosting deploy aap karein.'
Write-Host ' 6. Play Console mein app isi nayi id se banayein (id upload ke baad kabhi nahi badalti).'
Write-Host ''
Write-Host 'CHETAVNI: nayi id = Android ke liye bilkul nayi app. Phone par purani app (purani id) alag rahegi; usse uninstall karna padega, uska login/local data nayi app mein nahi aata.'
