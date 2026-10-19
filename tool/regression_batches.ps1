# Runs every Flutter test file in small batches (about 30 files each, --concurrency=1) so the laptop never holds
# the whole suite at once. Writes one summary line per batch to the file given as -Out. Read-only for the project.
# Run: powershell -File tool/regression_batches.ps1 -Out build/regression.txt [-Size 30] [-Resume 1]
#
# Part 5: the laptop used to go into Modern Standby in the middle of a batch and the run looked "stuck" for half an
# hour (it was asleep, nothing was hanging). So: (1) the script asks Windows to stay awake while it runs, for this
# process only, no system setting is changed; (2) a watchdog stops a batch whose log did not grow for -StallMinutes
# (a real hang), marks it FAILED in the summary and goes on with the next batch.
param(
  [string]$Out = 'build/regression.txt',
  [int]$Size = 30,
  [int]$Resume = 1,
  [int]$StallMinutes = 12
)
Set-Location (Split-Path -Parent $PSScriptRoot)

Add-Type -Namespace Win32 -Name Power -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
# ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x1): no idle sleep while this script runs.
[void][Win32.Power]::SetThreadExecutionState([uint32]2147483649)

$files = @(Get-ChildItem test -Filter '*_test.dart' -Recurse | Sort-Object FullName | ForEach-Object { ($_.FullName.Substring((Get-Location).Path.Length + 1)) -replace '\\', '/' })
$batches = [Math]::Ceiling($files.Count / $Size)
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
if ($Resume -le 1) { "files: $($files.Count), batches: $batches" | Set-Content $Out -Encoding utf8 }
try {
  for ($b = $Resume; $b -le $batches; $b++) {
    # Wait for free memory (rule: 3 GB or more) for up to 2 minutes at a time. Under 2 GB the batch runs as two halves.
    $low = $false
    for ($w = 0; $w -lt 10; $w++) {
      $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
      if ($free -ge 3) { break }
      if ($free -lt 2) { $low = $true }
      Start-Sleep -Seconds 120
    }
    $slice = @($files[(($b - 1) * $Size)..([Math]::Min($b * $Size, $files.Count) - 1)])
    $log = "build/regression_batch_$b.log"
    Remove-Item $log -ErrorAction SilentlyContinue
    # Under 2 GB free the batch is run as two halves, one after the other.
    # (An ArrayList keeps each chunk as ONE element; a plain array would be flattened into one run per file.)
    $chunks = New-Object System.Collections.ArrayList
    if ($low) {
      $half = [int]($slice.Count / 2)
      [void]$chunks.Add(@($slice[0..($half - 1)]))
      [void]$chunks.Add(@($slice[$half..($slice.Count - 1)]))
    } else {
      [void]$chunks.Add($slice)
    }
    $stalled = $false
    foreach ($chunk in $chunks) {
      $err = "build/regression_batch_$b.err"
      $part = "build/regression_batch_$b.part"
      $p = Start-Process -FilePath 'flutter' -ArgumentList (@('test', '--concurrency=1') + $chunk) -RedirectStandardOutput $part -RedirectStandardError $err -NoNewWindow -PassThru
      $lastSize = -1
      $lastChange = Get-Date
      while (-not $p.HasExited) {
        Start-Sleep -Seconds 30
        $len = if (Test-Path $part) { (Get-Item $part).Length } else { 0 }
        if ($len -ne $lastSize) { $lastSize = $len; $lastChange = Get-Date }
        elseif (((Get-Date) - $lastChange).TotalMinutes -ge $StallMinutes) {
          $stalled = $true
          # Only the test processes of this run, never java / emulators.
          Get-Process flutter_tester, dartaotruntime -ErrorAction SilentlyContinue | Stop-Process -Force
          if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
          break
        }
      }
      Get-Content $part | Add-Content $log -Encoding utf8
    }
    $tail = (Get-Content $log -Tail 40 | Where-Object { $_ -match 'All tests passed|Some tests failed|\+\d+' } | Select-Object -Last 1)
    $failed = @(Get-Content $log | Where-Object { $_ -match '^\s+C:/.*_test\.dart:' } | Sort-Object -Unique)
    "batch $b of ${batches}: $tail" | Add-Content $Out -Encoding utf8
    if ($stalled) {
      $lastFile = (Get-Content $log | Where-Object { $_ -match '_test\.dart' } | Select-Object -Last 1)
      "   STALLED for $StallMinutes minutes and stopped. Last line: $lastFile" | Add-Content $Out -Encoding utf8
    }
    foreach ($f in $failed) { "   FAILED: $f" | Add-Content $Out -Encoding utf8 }
  }
  'DONE' | Add-Content $Out -Encoding utf8
} finally {
  [void][Win32.Power]::SetThreadExecutionState([uint32]2147483648)
}
