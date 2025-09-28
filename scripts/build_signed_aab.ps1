# Build signed Android App Bundle with auto-incremented build number
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build_signed_aab.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VersionParts {
    param([string]$versionLine)
    # Expects a line like: version: 1.0.0+2
    if ($versionLine -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
        return @{ name = $Matches[1]; build = [int]$Matches[2] }
    }
    throw "Could not parse version line: $versionLine"
}

Write-Host "[1/4] Reading pubspec.yaml ..." -ForegroundColor Cyan
$pubspecPath = Join-Path $PSScriptRoot '..\pubspec.yaml'
if (!(Test-Path $pubspecPath)) { throw "pubspec.yaml not found at $pubspecPath" }

$content = Get-Content -LiteralPath $pubspecPath -Raw
$versionLine = ($content -split "\r?\n") | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
if (-not $versionLine) { throw "version: line not found in pubspec.yaml" }

$parts = Get-VersionParts -versionLine $versionLine
$versionName = $parts.name
$newBuild = $parts.build + 1
$newVersionLine = "version: $versionName+$newBuild"

Write-Host "Current version: $versionName+$($parts.build)" -ForegroundColor Yellow
Write-Host "New version:     $newVersionLine" -ForegroundColor Green

Write-Host "[2/4] Updating pubspec.yaml ..." -ForegroundColor Cyan
$contentUpdated = $content -replace [Regex]::Escape($versionLine), $newVersionLine
Set-Content -LiteralPath $pubspecPath -Value $contentUpdated -Encoding UTF8

Write-Host "[3/4] Fetching packages ..." -ForegroundColor Cyan
flutter pub get

Write-Host "[4/4] Building signed app bundle ..." -ForegroundColor Cyan
flutter build appbundle --release --build-name $versionName --build-number $newBuild

Write-Host "Build completed." -ForegroundColor Green
Write-Host "Output AAB: build/app/outputs/bundle/release/app-release.aab" -ForegroundColor Green
