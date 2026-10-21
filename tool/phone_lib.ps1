# Pure helpers for tool/phone.ps1 (no adb call in here, so they can be tested with pasted adb output).
# Dot-source it: . tool/phone_lib.ps1

function ConvertFrom-AdbDevices {
  # Input: the text of `adb devices -l`. Output: one object per line with Serial, State, IsEmulator, Model.
  param([string]$Text)
  $rows = @()
  foreach ($line in ($Text -split "`r?`n")) {
    $l = $line.Trim()
    if ($l -eq '' -or $l -like 'List of devices*' -or $l -like '* daemon *' -or $l -like '*daemon started*') { continue }
    $parts = $l -split '\s+'
    if ($parts.Count -lt 2) { continue }
    $model = ''
    foreach ($p in $parts) { if ($p -like 'model:*') { $model = $p.Substring(6) } }
    $rows += [pscustomobject]@{
      Serial     = $parts[0]
      State      = $parts[1]
      IsEmulator = ($parts[0] -like 'emulator-*')
      Model      = $model
    }
  }
  return , $rows
}

function Get-PhoneStatus {
  # Picks the real phone (never emulator-*). Status: ready, unauthorized, offline, none, many.
  param($Devices)
  $real = @($Devices | Where-Object { -not $_.IsEmulator })
  if ($real.Count -eq 0) { return [pscustomobject]@{ Status = 'none'; Phone = $null } }
  $ready = @($real | Where-Object { $_.State -eq 'device' })
  if ($ready.Count -gt 1) { return [pscustomobject]@{ Status = 'many'; Phone = $null } }
  if ($ready.Count -eq 1) { return [pscustomobject]@{ Status = 'ready'; Phone = $ready[0] } }
  $u = @($real | Where-Object { $_.State -eq 'unauthorized' })
  if ($u.Count -gt 0) { return [pscustomobject]@{ Status = 'unauthorized'; Phone = $u[0] } }
  return [pscustomobject]@{ Status = 'offline'; Phone = $real[0] }
}

function Get-PhoneAdvice {
  # What to do on the phone, in Hinglish, for each status.
  param([string]$Status)
  switch ($Status) {
    'none' { return "Phone nahi mila. 1) USB cable lagayein (data wali cable). 2) Phone mein USB mode 'File transfer' chunein. 3) Settings > Developer options > USB debugging ON karein. 4) Phir yeh command dobara chalayein." }
    'unauthorized' { return "Phone ne laptop ko allow nahi kiya. Phone ki screen par 'Allow USB debugging?' aayega: 'Always allow from this computer' tick karke Allow dabayein. Samsung par na aaye to: Developer options > 'Revoke USB debugging authorizations', cable nikalein, dobara lagayein." }
    'offline' { return "Phone 'offline' dikh raha hai. Cable nikal kar dobara lagayein, USB mode 'File transfer' rakhein, USB debugging OFF karke ON karein. Samsung par: Developer options > Revoke USB debugging authorizations, phir dobara lagayein." }
    'many' { return "Ek se zyada phone judein hain. Sirf ek phone lagayein (baaki cable nikaal dein) aur dobara chalayein." }
    default { return '' }
  }
}

function Get-InstallProblem {
  # Reads the output of `adb install` and says what went wrong, in Hinglish. Returns $null when it worked.
  param([string]$Output)
  if ($Output -match 'Success') { return $null }
  if ($Output -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
    return [pscustomobject]@{ Code = 'UPDATE_INCOMPATIBLE'; Message = "Phone par pehle se isi naam ki app hai jo doosri key (signature) se bani hai, isliye update nahi ho sakta. Purani app hata kar nayi lagani padegi (is phone ka local data, jaise login, hat jayega). Chalayein: .\tool\phone.ps1 install -ReinstallClean" }
  }
  if ($Output -match 'INSTALL_FAILED_VERSION_DOWNGRADE') {
    return [pscustomobject]@{ Code = 'VERSION_DOWNGRADE'; Message = "Phone par is APK se nayi version pehle se hai. -ReinstallClean se purani hata kar lagayein." }
  }
  if ($Output -match 'INSTALL_FAILED_INSUFFICIENT_STORAGE') {
    return [pscustomobject]@{ Code = 'STORAGE'; Message = "Phone mein jagah kam hai. Kuch hata kar dobara try karein." }
  }
  if ($Output -match 'INSTALL_FAILED_USER_RESTRICTED|INSTALL_FAILED_ABORTED') {
    return [pscustomobject]@{ Code = 'USER_RESTRICTED'; Message = "Phone ne install roka. Developer options mein 'Install via USB' ON karein (Samsung/Xiaomi par), aur phone ki screen par aane wala 'Install' prompt Allow karein." }
  }
  if ($Output -match 'device offline|no devices|closed|more than one') {
    return [pscustomobject]@{ Code = 'CONNECTION'; Message = "Connection beech mein toot gaya." }
  }
  return [pscustomobject]@{ Code = 'OTHER'; Message = "Install nahi hua. Neeche ka message padhein aur zarurat ho to bhejein." }
}

function Test-TransientAdbFailure {
  param([string]$Output)
  return [bool]($Output -match 'device offline|no devices|device not found|closed|protocol fault|error: device')
}

function Get-PackageIdFromGradleProperties {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*loadgo\.applicationId\s*=\s*(\S+)\s*$') { return $Matches[1] }
  }
  return $null
}

function Test-LogLineWanted {
  # Which logcat lines are worth keeping: flutter, AndroidRuntime, FATAL, and E/ (error) lines.
  param([string]$Line)
  return [bool]($Line -match '\bflutter\b|AndroidRuntime|FATAL|^\S*\s*\d*\s*\d*\s*E\s|(^|\s)E/')
}

function Get-MaskedLogLine {
  # Same idea as the app's Redactor: no phone numbers, ids, emails, links, keys or tokens leave this laptop in a log.
  param([string]$Line)
  $t = $Line
  $rules = @(
    @('rzp_(live|test)_\w+', '#key'),
    @('AIza[\w-]{30,}', '#key'),
    @('\bgh[pousr]_\w{20,}', '#token'),
    @('(?i)\bBearer\s+\S+', 'Bearer #'),
    @('-----BEGIN[^-]*PRIVATE KEY-----', '#key'),
    @('(?i)upi://\S+', ' '),
    @('\S+@\S+', ' '),
    @('(?i)https?://\S+|www\.\S+', ' '),
    @('\beyJ[\w-]+\.[\w-]+\.[\w-]*', '#token'),
    @('\b[\w-]{16,}(:[\w-]{16,})+', '#token'),
    @('\b[A-Z]{4}0[A-Z0-9]{6}\b', '#ifsc'),
    @('\b[A-Z]{5}\d{4}[A-Z]\b', '#pan'),
    @('\b[A-Z]{2}[ -]?\d{1,2}[ -]?[A-Z]{1,3}[ -]?\d{4}\b', '#vehicle'),
    @('(?i)(otp|code|pin)\W{0,3}\d{4,8}', '$1 #'),
    @('[-+]?\d{1,3}\.\d{4,}\s*,\s*[-+]?\d{1,3}\.\d{4,}', '#geo'),
    @('(\+?\d[\s-]?){7,}\d', '#'),
    @('\b\d{6}\b', '#'),
    @('\b[A-Za-z0-9]{28}\b', '#uid'),
    @('\b(?=[\w-]*\d)[\w-]{32,}', '#token')
  )
  foreach ($r in $rules) { $t = [regex]::Replace($t, $r[0], $r[1]) }
  return ([regex]::Replace($t, '\s+', ' ')).Trim()
}
