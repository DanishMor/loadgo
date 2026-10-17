# Runs every Flutter test file in small batches (about 30 files each, --concurrency=1) so the laptop never holds
# the whole suite at once. Writes one summary line per batch to the file given as -Out. Read-only for the project.
# Run: powershell -File tool/regression_batches.ps1 -Out build/regression.txt [-Size 30] [-Resume 1]
param(
  [string]$Out = 'build/regression.txt',
  [int]$Size = 30,
  [int]$Resume = 1
)
Set-Location (Split-Path -Parent $PSScriptRoot)
$files = @(Get-ChildItem test -Filter '*_test.dart' -Recurse | Sort-Object FullName | ForEach-Object { ($_.FullName.Substring((Get-Location).Path.Length + 1)) -replace '\\', '/' })
$batches = [Math]::Ceiling($files.Count / $Size)
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
if ($Resume -le 1) { "files: $($files.Count), batches: $batches" | Set-Content $Out -Encoding utf8 }
for ($b = $Resume; $b -le $batches; $b++) {
  # Wait for free memory (rule: 3 GB or more) for up to 2 minutes at a time.
  for ($w = 0; $w -lt 10; $w++) {
    $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    if ($free -ge 3) { break }
    Start-Sleep -Seconds 120
  }
  $slice = $files[(($b - 1) * $Size)..([Math]::Min($b * $Size, $files.Count) - 1)]
  $log = "build/regression_batch_$b.log"
  & flutter test --concurrency=1 @slice *> $log
  $tail = (Get-Content $log -Tail 40 | Where-Object { $_ -match 'All tests passed|Some tests failed|\+\d+' } | Select-Object -Last 1)
  $failed = @(Get-Content $log | Where-Object { $_ -match '^\s+C:/.*_test\.dart:' } | Sort-Object -Unique)
  "batch $b of ${batches}: $tail" | Add-Content $Out -Encoding utf8
  foreach ($f in $failed) { "   FAILED: $f" | Add-Content $Out -Encoding utf8 }
}
'DONE' | Add-Content $Out -Encoding utf8
