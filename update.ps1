#Requires -RunAsAdministrator
# Replace the payload under C:\varo and restart the NSSM service.
# Does not clone the monorepo. Does not rotate the device token.

[CmdletBinding()]
param(
    [string] $InstallRoot = "C:\varo",
    [string] $PayloadUrl,
    [string] $PayloadSha256,
    [string] $ServiceName = "AzurroVaroSampler"
)

$ErrorActionPreference = "Stop"

function Get-NssmExe {
    param([string] $Root)
    $candidates = @(
        (Join-Path $Root "nssm.exe"),
        (Join-Path $Root "bin\nssm.exe")
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Flatten-Payload {
    param([string] $Root)
    $kids = @(Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -ne "logs" })
    if ($kids.Count -eq 1 -and $kids[0].PSIsContainer) {
        $inner = $kids[0].FullName
        Get-ChildItem -LiteralPath $inner -Force | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $Root $_.Name) -Force
        }
        Remove-Item -LiteralPath $inner -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$prin = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this from an elevated PowerShell (Run as administrator)."
}

if (-not (Test-Path -LiteralPath $InstallRoot)) {
    throw "$InstallRoot not found. Run install.ps1 first."
}

if (-not $PayloadUrl) {
    $PayloadUrl = Read-Host "Payload zip URL"
}
if (-not $PayloadUrl) {
    throw "Payload URL is required."
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$nssm = Get-NssmExe -Root $InstallRoot
if ($nssm) {
    Write-Host "Stopping $ServiceName..."
    & $nssm stop $ServiceName
    Start-Sleep -Seconds 2
}

$keep = @(".env", "logs", "spool.jsonl", "spool.jsonl.sending")
$zipPath = Join-Path $env:TEMP ("varo-payload-" + [guid]::NewGuid().ToString() + ".zip")
Invoke-WebRequest -Uri $PayloadUrl -OutFile $zipPath -UseBasicParsing
if ($PayloadSha256) {
    $got = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $want = $PayloadSha256.ToUpperInvariant()
    if ($got -ne $want) {
        throw "Payload SHA256 mismatch. Expected $want got $got"
    }
}

$stageRoot = Join-Path $env:TEMP ("varo-extract-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
Expand-Archive -LiteralPath $zipPath -DestinationPath $stageRoot -Force
Flatten-Payload -Root $stageRoot

Get-ChildItem -LiteralPath $stageRoot -Force | ForEach-Object {
    if ($keep -contains $_.Name) { return }
    $dest = Join-Path $InstallRoot $_.Name
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $_.FullName -Destination $dest
}

if ($nssm) {
    & $nssm start $ServiceName
    if ($LASTEXITCODE -ne 0) {
        throw "nssm start failed with exit $LASTEXITCODE"
    }
}

Write-Host "Updated $InstallRoot"
sc.exe query $ServiceName
