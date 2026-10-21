<#
.SYNOPSIS
  OWNER runs this once to make the upload keystore and android\key.properties. Claude never runs it.

.EXAMPLE
  .\tool\make_keystore.ps1
  .\tool\make_keystore.ps1 -Alias upload -Name "Your Name" -City Delhi -State Delhi

.NOTES
  - keytool is taken from Android Studio's jbr (or JAVA_HOME / PATH if that is missing).
  - The keystore is made OUTSIDE the repo: %USERPROFILE%\load20-keys\load20-upload.jks
  - Passwords are asked as hidden input. They are never printed, never put on a command line (keytool reads them from
    a temporary environment variable of its own process) and never saved anywhere except the git-ignored
    android\key.properties that the release build needs.
  - It refuses to overwrite an existing keystore or key.properties.
#>
param(
  [string]$Alias = 'upload',
  [string]$Name = '',
  [string]$Org = 'Load 20',
  [string]$City = '',
  [string]$State = '',
  [string]$Country = 'IN'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Find-Keytool {
  $studio = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe'
  if (Test-Path $studio) { return $studio }
  if ($env:JAVA_HOME) {
    $j = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    if (Test-Path $j) { return $j }
  }
  $c = Get-Command keytool -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}

function ConvertTo-PlainText([securestring]$s) {
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

$keytool = Find-Keytool
if (-not $keytool) { throw 'keytool nahi mila. Android Studio install karein (jbr\bin\keytool.exe).' }

$dir = Join-Path $env:USERPROFILE 'load20-keys'
$jks = Join-Path $dir 'load20-upload.jks'
$props = Join-Path $root 'android\key.properties'
if ($dir.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Keystore repo ke andar nahi ban sakta.' }
if (Test-Path $jks) { throw "Keystore pehle se hai: $jks. Purana overwrite nahi karte. Use hi rakhein ya khud hata kar dobara chalayein." }
if (Test-Path $props) { throw "android\key.properties pehle se hai. Overwrite nahi karte." }

if (-not $Name) { $Name = Read-Host 'Aapka naam (certificate ke liye)' }
if (-not $City) { $City = Read-Host 'Sheher' }
if (-not $State) { $State = Read-Host 'Rajya' }
foreach ($v in @($Name, $Org, $City, $State, $Country, $Alias)) {
  if ($v -match '[,="\\]') { throw 'Naam, sheher waghera mein , = " ya \ nahi chalega.' }
}

$p1 = Read-Host 'Store password (kam se kam 8 akshar, screen par nahi dikhega)' -AsSecureString
$p2 = Read-Host 'Store password dobara' -AsSecureString
$store = ConvertTo-PlainText $p1
if ($store -ne (ConvertTo-PlainText $p2)) { throw 'Dono password alag hain. Dobara chalayein.' }
if ($store.Length -lt 8) { throw 'Password 8 akshar se chhota hai.' }
$same = Read-Host 'Key password bhi wahi rakhein? (Y/n)'
if ($same -eq 'n' -or $same -eq 'N') {
  $k1 = Read-Host 'Key password' -AsSecureString
  $key = ConvertTo-PlainText $k1
  if ($key.Length -lt 8) { throw 'Key password 8 akshar se chhota hai.' }
} else { $key = $store }

New-Item -ItemType Directory -Force -Path $dir | Out-Null
$dname = "CN=$Name, O=$Org, L=$City, ST=$State, C=$Country"
try {
  # keytool reads the passwords from environment variables of THIS child process only.
  $env:L20_STORE_PW = $store
  $env:L20_KEY_PW = $key
  & $keytool -genkeypair -keystore $jks -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 -dname $dname -storepass:env L20_STORE_PW -keypass:env L20_KEY_PW
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $jks)) { throw 'keytool fail hua. Keystore nahi bana.' }

  $storePath = $jks -replace '\\', '/'
  $lines = @("storeFile=$storePath", "storePassword=$store", "keyAlias=$Alias", "keyPassword=$key")
  Set-Content -Path $props -Value $lines -Encoding ASCII
} finally {
  Remove-Item Env:\L20_STORE_PW -ErrorAction SilentlyContinue
  Remove-Item Env:\L20_KEY_PW -ErrorAction SilentlyContinue
  $store = $null; $key = $null
}

Write-Host ''
Write-Host "Keystore ban gaya: $jks"
Write-Host 'android\key.properties ban gayi (git-ignored, commit nahi hogi).'
Write-Host ''
Write-Host 'ABHI KARO: BACKUP'
Write-Host ' 1. load20-upload.jks ki copy do alag jagah rakhein (encrypted pen drive + private cloud ka password-protected zip).'
Write-Host ' 2. Dono password apne password manager mein likhein. Chat, e-mail ya repo mein kabhi nahi.'
Write-Host ' 3. Yeh file kho gayi to app update nahi ho payegi (Play App Signing ON rakhein: docs/SIGNING.md).'
Write-Host ''
Write-Host 'SHA dekhne ke liye (sirf terminal mein, kahin likhna nahi; password poochhega):'
Write-Host "  & `"$keytool`" -list -v -keystore `"$jks`" -alias $Alias"
