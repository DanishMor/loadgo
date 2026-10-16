# Read-only status of the Part 3 (G tasks) work. Changes nothing.
# Run: powershell -File tool/status.ps1
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host '== Last 5 commits =='
git log --oneline -5

Write-Host ''
Write-Host '== G tasks done (commits starting with G<n>:) =='
$g = @(git log --format=%s | Where-Object { $_ -match '^G\d+:' })
Write-Host $g.Count

Write-Host ''
Write-Host '== Uncommitted files =='
$dirty = @(git status --short)
Write-Host $dirty.Count
$dirty | Select-Object -First 15

Write-Host ''
Write-Host '== Free memory =='
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $gb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
  Write-Host "$gb GB free"
  if ($gb -lt 3) { Write-Host 'LOW: wait 2 minutes before running flutter test.' }
} catch { Write-Host 'could not read memory' }

Write-Host ''
Write-Host '== docs/RESUME.md =='
if (Test-Path docs/RESUME.md) { Get-Content docs/RESUME.md } else { Write-Host 'missing' }
