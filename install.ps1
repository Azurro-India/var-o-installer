#Requires -RunAsAdministrator
# VAR-O1 edge bootstrap. Public. No secrets.
# Intended use (Admin PowerShell):
#   irm https://raw.githubusercontent.com/Azurro-India/var-o-installer/main/install.ps1 | iex
#
# This script does not clone Azurro-India/Main.
# It downloads a payload zip, writes .env, and registers NSSM.

[CmdletBinding()]
param(
    [string] $InstallRoot = "C:\varo",
    [string] $PayloadUrl,
    [string] $PayloadSha256,
    [string] $DeviceToken,
    [string] $ApiUrl = "https://var-o1-api.onrender.com",
    [string] $ServiceName = "AzurroVaroSampler",
    [string] $Interval = "15",
    [switch] $SkipService
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prin = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this from an elevated PowerShell (Run as administrator)."
    }
}

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

function Get-VaroExe {
    param([string] $Root)
    $candidates = @(
        (Join-Path $Root "varo.exe"),
        (Join-Path $Root "bin\varo.exe"),
        (Join-Path $Root ".venv\Scripts\varo.exe"),
        (Join-Path $Root "Scripts\varo.exe")
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Install-Nssm {
    param([string] $Root)
    $existing = Get-NssmExe -Root $Root
    if ($existing) { return $existing }

    $nssmZipUrl = "https://nssm.cc/release/nssm-2.24.zip"
    $nssmSha = "F689EE9AF94B00E9E3F0BB072B34CAAF207F32DCB4F5782FC9CA351DF9A06C97"
    $tmp = Join-Path $env:TEMP ("nssm-2.24-" + [guid]::NewGuid().ToString() + ".zip")
    $stage = Join-Path $env:TEMP ("nssm-2.24-" + [guid]::NewGuid().ToString())
    Write-Host "Downloading NSSM 2.24..."
    Invoke-WebRequest -Uri $nssmZipUrl -OutFile $tmp -UseBasicParsing
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Expand-Archive -LiteralPath $tmp -DestinationPath $stage -Force

    $found = Get-ChildItem -Path $stage -Recurse -Filter nssm.exe |
        Where-Object { $_.FullName -match '\\win64\\nssm\.exe$' } |
        Select-Object -First 1
    if (-not $found) {
        throw "nssm.exe win64 not found inside nssm-2.24.zip"
    }

    $hash = (Get-FileHash -LiteralPath $found.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -ne $nssmSha) {
        throw "NSSM SHA256 mismatch. Expected $nssmSha got $hash"
    }

    $destDir = Join-Path $Root "bin"
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $dest = Join-Path $destDir "nssm.exe"
    Copy-Item -LiteralPath $found.FullName -Destination $dest -Force
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    return $dest
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

Assert-Administrator
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $PayloadUrl) {
    $PayloadUrl = Read-Host "Payload zip URL (private edge release, not the monorepo)"
}
if (-not $PayloadUrl) {
    throw "Payload URL is required. This installer does not clone Azurro-India/Main."
}

if (-not $DeviceToken) {
    $secure = Read-Host "VARO_DEVICE_TOKEN (input hidden)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $DeviceToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
if (-not $DeviceToken) {
    throw "Device token is required. Mint one with 'varo token issue' on the operator laptop."
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "models") | Out-Null

$zipPath = Join-Path $env:TEMP ("varo-payload-" + [guid]::NewGuid().ToString() + ".zip")
Write-Host "Downloading payload..."
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
    $dest = Join-Path $InstallRoot $_.Name
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $_.FullName -Destination $dest
}

if (Test-Path -LiteralPath (Join-Path $InstallRoot "yolo11m.pt")) {
    $modelDest = Join-Path $InstallRoot "models\yolo11m.pt"
    if (-not (Test-Path -LiteralPath $modelDest)) {
        Move-Item -LiteralPath (Join-Path $InstallRoot "yolo11m.pt") -Destination $modelDest
    }
}

$envPath = Join-Path $InstallRoot ".env"
@(
    "VARO_API_URL=$ApiUrl",
    "VARO_DEVICE_TOKEN=$DeviceToken"
) | Set-Content -LiteralPath $envPath -Encoding ascii

$varoExe = Get-VaroExe -Root $InstallRoot
if (-not $varoExe) {
    throw "Payload extracted to $InstallRoot but varo.exe was not found. Zip must contain varo.exe, bin\varo.exe, or .venv\Scripts\varo.exe."
}

$versionPath = Join-Path $InstallRoot "version.txt"
if (-not (Test-Path -LiteralPath $versionPath)) {
    "unknown" | Set-Content -LiteralPath $versionPath -Encoding ascii
}

if ($SkipService) {
    Write-Host "SkipService set. Files are in $InstallRoot. Not registering NSSM."
    return
}

$nssm = Install-Nssm -Root $InstallRoot
$stdout = Join-Path $InstallRoot "logs\varo-stdout.log"
$stderr = Join-Path $InstallRoot "logs\varo-stderr.log"
$existing = & $nssm status $ServiceName 2>$null
if ($LASTEXITCODE -eq 0 -or $existing) {
    Write-Host "Service $ServiceName already exists. Stopping and retargeting."
    & $nssm stop $ServiceName
    Start-Sleep -Seconds 2
} else {
    Write-Host "Installing service $ServiceName..."
    & $nssm install $ServiceName $varoExe "run --interval $Interval"
    if ($LASTEXITCODE -ne 0) {
        throw "nssm install failed with exit $LASTEXITCODE"
    }
}

& $nssm set $ServiceName Application $varoExe
& $nssm set $ServiceName AppParameters "run --interval $Interval"
& $nssm set $ServiceName AppDirectory $InstallRoot
& $nssm set $ServiceName Start SERVICE_AUTO_START
& $nssm set $ServiceName AppStdout $stdout
& $nssm set $ServiceName AppStderr $stderr
& $nssm set $ServiceName AppRotateFiles 1
& $nssm set $ServiceName ObjectName LocalSystem
& $nssm start $ServiceName
if ($LASTEXITCODE -ne 0) {
    throw "nssm start failed with exit $LASTEXITCODE. Check $stderr"
}

Write-Host ""
Write-Host "Installed $ServiceName"
Write-Host "  root:    $InstallRoot"
Write-Host "  exe:     $varoExe"
Write-Host "  env:     $envPath"
Write-Host "  logs:    $stdout"
Write-Host "Do not run interactive 'varo run' while this service is RUNNING."
sc.exe query $ServiceName
