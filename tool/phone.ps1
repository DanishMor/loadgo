<#
.SYNOPSIS
  Owner tool for a real Android phone: devices, install, run, logs. Claude never runs this file.

.EXAMPLE
  .\tool\phone.ps1 devices
  .\tool\phone.ps1 install                      (uses build\app\outputs\flutter-apk\app-release.apk)
  .\tool\phone.ps1 install -Apk C:\x\app.apk -ReinstallClean
  .\tool\phone.ps1 run                          (opens the app on the phone)
  .\tool\phone.ps1 logs -Seconds 60             (saves build\phone_logs.txt, masked; read it before you send it)

.NOTES
  Only a real phone is used (never emulator-*). adb is looked for on PATH, then in the Android SDK folders.
  A lost connection is retried 3 times with adb wait-for-usb-device.
  -ReinstallClean uninstalls the app first (the phone's local data of the app is lost), then installs.
#>
param(
  [Parameter(Position = 0)][ValidateSet('devices', 'install', 'run', 'logs')][string]$Action = 'devices',
  [string]$Apk = '',
  [switch]$ReinstallClean,
  [int]$Seconds = 30
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. (Join-Path $PSScriptRoot 'phone_lib.ps1')

function Find-Adb {
  $c = Get-Command adb -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($base in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if ($base) {
      $p = Join-Path $base 'platform-tools\adb.exe'
      if (Test-Path $p) { return $p }
    }
  }
  return $null
}

$adb = Find-Adb
if (-not $adb) { Write-Host 'adb nahi mila. Android Studio > SDK Manager > SDK Tools > Android SDK Platform-Tools install karein.'; exit 2 }

function Get-Phone {
  $text = (& $adb devices -l | Out-String)
  $devices = ConvertFrom-AdbDevices -Text $text
  $s = Get-PhoneStatus -Devices $devices
  return $s
}

function Show-Devices {
  $text = (& $adb devices -l | Out-String)
  $devices = ConvertFrom-AdbDevices -Text $text
  foreach ($d in $devices) {
    $kind = if ($d.IsEmulator) { 'emulator (ignored)' } else { 'phone' }
    Write-Host ("{0}  {1}  {2}  {3}" -f $d.Serial, $d.State, $d.Model, $kind)
  }
  $s = Get-PhoneStatus -Devices $devices
  if ($s.Status -ne 'ready') { Write-Host ''; Write-Host (Get-PhoneAdvice -Status $s.Status) } else { Write-Host ''; Write-Host "Phone taiyaar: $($s.Phone.Serial)" }
  return $s
}

function Invoke-Adb {
  # Runs adb for the phone with up to 3 tries; between tries it waits for the phone to come back.
  param([string]$Serial, [string[]]$AdbArgs)
  for ($i = 1; $i -le 3; $i++) {
    $out = (& $adb -s $Serial @AdbArgs 2>&1 | Out-String)
    if (-not (Test-TransientAdbFailure -Output $out)) { return $out }
    Write-Host "Connection toota (koshish $i/3). Phone ka wait kar rahe hain ..."
    & $adb -s $Serial wait-for-usb-device | Out-Null
    Start-Sleep -Seconds 2
  }
  return $out
}

$pkg = Get-PackageIdFromGradleProperties -Path (Join-Path $root 'android\gradle.properties')
if (-not $pkg) { $pkg = 'com.example.transport_app' }

$status = Show-Devices
if ($Action -eq 'devices') { exit 0 }
if ($status.Status -ne 'ready') { exit 1 }
$serial = $status.Phone.Serial

switch ($Action) {
  'install' {
    if (-not $Apk) { $Apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk' }
    if (-not (Test-Path $Apk)) { Write-Host "APK nahi mila: $Apk. Pehle build karein (docs/ANDROID_RELEASE.md)."; exit 1 }
    if ($ReinstallClean) {
      Write-Host "Purani app ($pkg) hata rahe hain ..."
      Invoke-Adb -Serial $serial -AdbArgs @('uninstall', $pkg) | Out-Host
    }
    $out = Invoke-Adb -Serial $serial -AdbArgs @('install', '-r', $Apk)
    $problem = Get-InstallProblem -Output $out
    if ($null -eq $problem) { Write-Host 'Install ho gaya.'; exit 0 }
    Write-Host $problem.Message
    if ($problem.Code -eq 'OTHER') { Write-Host $out }
    exit 1
  }
  'run' {
    $out = Invoke-Adb -Serial $serial -AdbArgs @('shell', 'monkey', '-p', $pkg, '-c', 'android.intent.category.LAUNCHER', '1')
    Write-Host $out
    exit 0
  }
  'logs' {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null
    $file = Join-Path $root 'build\phone_logs.txt'
    Write-Host "$Seconds second ke liye log pakad rahe hain. Ab phone par woh kaam karein jo fail hota hai ..."
    Invoke-Adb -Serial $serial -AdbArgs @('logcat', '-c') | Out-Null
    $job = Start-Job -ScriptBlock { param($a, $s) & $a -s $s logcat -v time 2>&1 } -ArgumentList $adb, $serial
    Start-Sleep -Seconds $Seconds
    Stop-Job $job
    $raw = @(Receive-Job $job)
    Remove-Job $job -Force
    $kept = foreach ($l in $raw) { $line = "$l"; if (Test-LogLineWanted -Line $line) { Get-MaskedLogLine -Line $line } }
    $kept | Set-Content -Path $file -Encoding ASCII
    Write-Host "Saved: $file ($(@($kept).Count) lines, phone numbers / ids / tokens masked)."
    Write-Host 'BHEJNE SE PEHLE KHUD PADH LO: file kholo aur dekho ki koi personal cheez to nahi bachi.'
    exit 0
  }
}
