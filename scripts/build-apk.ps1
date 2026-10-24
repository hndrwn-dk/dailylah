# Builds the signed release APK on Windows with the version and commit shown on About.
# Set ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD first.
# Usage (from the repo root): powershell -ExecutionPolicy Bypass -File scripts\build-apk.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sha = (git -C $root rev-parse --short=7 HEAD).Trim()
if (git -C $root status --porcelain) { $sha = "$sha-dirty" }
$version = ((Select-String -Path "$root\app\pubspec.yaml" -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)

if (-not $env:ANDROID_KEYSTORE_PATH) { throw 'ANDROID_KEYSTORE_PATH is not set; the APK would not install over the old one.' }

Push-Location "$root\app"
try {
  flutter build apk --release --dart-define=APP_VERSION=$version --dart-define=GIT_SHA=$sha
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
  Copy-Item build\app\outputs\flutter-apk\app-release.apk "build\dailylah-$version-$sha.apk"
  Write-Host "Built app\build\dailylah-$version-$sha.apk"
} finally {
  Pop-Location
}
