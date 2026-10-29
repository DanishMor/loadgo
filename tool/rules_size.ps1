# Prints the size of firestore.rules and storage.rules and fails above the budget (E2).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$budget = 235KB
$root = Split-Path -Parent $PSScriptRoot
foreach ($name in 'firestore.rules', 'storage.rules') {
  $size = (Get-Item (Join-Path $root $name)).Length
  Write-Output ("{0}: {1} bytes ({2:N1} KB)" -f $name, $size, ($size / 1KB))
}
$fs = (Get-Item (Join-Path $root 'firestore.rules')).Length
if ($fs -gt $budget) { Write-Output "FAIL: firestore.rules is over the budget of $budget bytes"; exit 1 }
Write-Output "OK: under the budget of $budget bytes"
