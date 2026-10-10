<#
.SYNOPSIS
  Lists every "[add ..." placeholder that is still open in hosting, its templates and the docs.
  Exit code 1 when any is left (use it as a release gate), 0 when none.
#>
param([string]$Root)

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$skip = 'MASTER_PLAN_7.md', 'WINDOWS_FINISH.md', 'PLACEHOLDERS.md', 'DECISIONS.md', 'PROGRESS.md'

$left = 0
foreach ($dir in 'hosting', 'tool\templates\hosting', 'docs') {
  $p = Join-Path $Root $dir
  if (-not (Test-Path $p)) { continue }
  foreach ($f in Get-ChildItem -Path $p -Include *.html, *.md -Recurse -File) {
    if ($skip -contains $f.Name) { continue }
    $lines = [System.IO.File]::ReadAllLines($f.FullName, $utf8)
    for ($i = 0; $i -lt $lines.Length; $i++) {
      foreach ($m in [regex]::Matches($lines[$i], '\[add [^\]]*\]')) {
        $rel = $f.FullName.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
        Write-Host ("{0}:{1}: {2}" -f $rel, ($i + 1), $m.Value)
        $left++
      }
    }
  }
}
if ($left -eq 0) { Write-Host 'No open [add ...] placeholders.'; exit 0 }
Write-Host "$left placeholder(s) still open."
exit 1
