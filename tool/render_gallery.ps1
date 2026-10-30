# E13: draws the design gallery (key screens x 3 looks x 2 phone sizes x languages) to PNG for a design review.
# Run: powershell -File tool/render_gallery.ps1 [-Out build/gallery] [-Full]
#   -Out dir   where the PNG files go (default build/gallery; build/ is not committed)
#   -Full      every screen x look x size x all 12 languages (about 500 images) instead of the review set (about 50)
# It waits for 3 GB of free memory (rule 10), runs one flutter test with --concurrency=1, and prints the problems
# file (overflow and other layout errors found while drawing). It builds no app and touches no device.
param(
  [string]$Out = 'build/gallery',
  [switch]$Full
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

for ($w = 0; $w -lt 10; $w++) {
  $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
  if ($free -ge 3) { break }
  Write-Host "Free memory $free GB is under 3 GB, waiting 2 minutes."
  Start-Sleep -Seconds 120
}

if (Test-Path $Out) { Get-ChildItem $Out -Filter '*.png' | Remove-Item }
$defines = @("--dart-define=OUT=$Out")
if ($Full) { $defines += '--dart-define=FULL=true' }
& flutter test --concurrency=1 tool/render_gallery_test.dart @defines
$code = $LASTEXITCODE

$pngs = @(Get-ChildItem $Out -Filter '*.png' -ErrorAction SilentlyContinue)
Write-Host "Images: $($pngs.Count) in $Out"
$problems = Join-Path $Out 'problems.txt'
if (Test-Path $problems) {
  Write-Host 'Layout problems:'
  Get-Content $problems | ForEach-Object { Write-Host "  $_" }
}
exit $code
