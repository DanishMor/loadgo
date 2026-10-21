# Read-only status. Changes nothing, starts nothing except `git`/`adb devices` reads.
# Run: powershell -File tool/status.ps1
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "== Time ==" ; Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Write-Host ''; Write-Host '== Free memory =='
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $gb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
  Write-Host "$gb GB free"
  if ($gb -lt 3) { Write-Host 'LOW: wait 2 minutes before running flutter test (builds need 5 GB).' }
} catch { Write-Host 'could not read memory' }

Write-Host ''; Write-Host '== Test / build processes =='
$procs = @(Get-Process flutter_tester, dartaotruntime, dart, flutter, java, gradle -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) { Write-Host 'none running' } else { $procs | Group-Object ProcessName | ForEach-Object { Write-Host ("{0} x{1}" -f $_.Name, $_.Count) } }

Write-Host ''; Write-Host '== Newest regression summary =='
$reg = Get-ChildItem build -Filter 'regression*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($reg) {
  Write-Host ("{0}  (written {1})" -f $reg.Name, $reg.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
  Get-Content $reg.FullName -Tail 8
} else { Write-Host 'none yet (tool/run_regression.ps1 makes one)' }

Write-Host ''; Write-Host '== Git =='
git rev-parse --abbrev-ref HEAD
git log --oneline -5
$dirty = @(git status --short)
Write-Host "uncommitted files: $($dirty.Count)"
$dirty | Select-Object -First 10

Write-Host ''; Write-Host '== Commits per task prefix (e.g. Z, H, U, F, G) =='
$subjects = @(git log --format=%s)
$subjects | ForEach-Object { if ($_ -match '^([A-Z]{1,3})\d+') { $Matches[1] } } | Group-Object | Sort-Object Count -Descending | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }

Write-Host ''; Write-Host '== docs/RESUME.md: LAST_DONE and NEXT =='
if (Test-Path docs/RESUME.md) {
  Get-Content docs/RESUME.md | Where-Object { $_ -match '^(LAST_DONE|NEXT):' } | ForEach-Object { $_ }
} else { Write-Host 'missing' }

Write-Host ''; Write-Host '== Phones (only if the adb server is already running; this script never starts it) =='
$adbProc = Get-Process adb -ErrorAction SilentlyContinue
$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
  foreach ($base in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'AndroidSdk'))) {
    if ($base -and (Test-Path (Join-Path $base 'platform-toolsadb.exe'))) { $adb = Get-Item (Join-Path $base 'platform-toolsadb.exe'); break }
  }
}
if (-not $adb) { Write-Host 'adb not found (only needed for a phone; see docs/PHONE_TOOLS.md)' }
elseif (-not $adbProc) { Write-Host 'adb server is not running, so no phone list. Run: .	oolphone.ps1 devices' }
else {
  $path = if ($adb.PSObject.Properties.Name -contains 'Source') { $adb.Source } else { $adb.FullName }
  & $path devices -l | Where-Object { $_ -and $_ -notlike 'List of*' -and $_ -notlike '*daemon*' }
}
