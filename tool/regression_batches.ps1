# Old name. Kept so older docs keep working: forwards everything to tool/run_regression.ps1.
param([string]$Out = 'build/regression.txt', [int]$Size = 30, [int]$Resume = 1, [int]$StallMinutes = 12, [string]$Only = '')
& (Join-Path $PSScriptRoot 'run_regression.ps1') -Out $Out -Size $Size -From $Resume -StallMinutes $StallMinutes -Only $Only
