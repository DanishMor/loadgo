<#
.SYNOPSIS
  Deploys Firestore rules and indexes after checking the Firebase CLI is signed in as the right account.
  The OWNER runs this, nobody else (Claude never runs it).

.EXAMPLE
  .\tool\deploy_rules.ps1 -Account "owner@example.com" -Project "loadgo-defc2"

.NOTES
  Steps: firebase login:list must show -Account  ->  firebase login:use -Account  ->  type YES  ->
  firebase deploy --only firestore:rules,firestore:indexes.
  Storage rules are NOT deployed here (add storage with -WithStorage).
  On a 409 error (the rules or indexes were changed in the Console meanwhile, or an index already exists)
  it prints the steps to publish from the Console instead.
#>
param(
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Project,
  [switch]$WithStorage
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  throw "firebase CLI not found. Install: npm install -g firebase-tools"
}

Write-Host "1. Checking the signed-in accounts (firebase login:list) ..."
$list = (& firebase login:list 2>&1 | Out-String)
Write-Host $list
if ($list -notmatch [regex]::Escape($Account)) {
  Write-Host "Account $Account is not signed in. Run:  firebase login:add $Account   (then run this script again)"
  exit 2
}

Write-Host "2. Using $Account for this folder (firebase login:use) ..."
& firebase login:use $Account
if ($LASTEXITCODE -ne 0) { Write-Host "Could not switch to $Account."; exit 2 }

$what = 'firestore:rules,firestore:indexes'
if ($WithStorage) { $what += ',storage' }
Write-Host ""
Write-Host "About to deploy ($what) to project $Project as $Account."
$answer = Read-Host "Type YES to continue"
if ($answer -ne 'YES') { Write-Host 'Cancelled. Nothing was deployed.'; exit 0 }

Write-Host "3. Deploying ..."
$out = (& firebase deploy --only $what --project $Project 2>&1 | Out-String)
Write-Host $out
if ($LASTEXITCODE -eq 0) { Write-Host 'Done. Verify in the Console: Firestore > Rules (published time) and Indexes (status Enabled).'; exit 0 }

if ($out -match '409') {
  Write-Host ''
  Write-Host '409 from the deploy. Publish from the Console instead:'
  Write-Host '  Rules:   Firebase Console > Firestore Database > Rules > paste the whole of firestore.rules > Publish.'
  Write-Host '  Storage: Firebase Console > Storage > Rules > paste storage.rules > Publish.'
  Write-Host '  Indexes: Firebase Console > Firestore Database > Indexes > Composite > create the ones in firestore.indexes.json'
  Write-Host '           that are missing (or open the link in the error text of a failing query, it pre-fills the index).'
  Write-Host '  An index that "already exists" (409) is fine: check its status is Enabled and go on.'
  exit 3
}
Write-Host 'Deploy failed (not a 409). Read the error above; nothing else was changed.'
exit 1
