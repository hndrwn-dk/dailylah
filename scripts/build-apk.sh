#!/usr/bin/env bash
# Builds the signed release APK with the version and commit shown on About.
# Set ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sha="$(git -C "$root" rev-parse --short=7 HEAD)"
[ -n "$(git -C "$root" status --porcelain)" ] && sha="$sha-dirty"
version="$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "$root/app/pubspec.yaml")"

: "${ANDROID_KEYSTORE_PATH:?ANDROID_KEYSTORE_PATH is not set; the APK would not install over the old one.}"

cd "$root/app"
flutter build apk --release --dart-define=APP_VERSION="$version" --dart-define=GIT_SHA="$sha"
cp build/app/outputs/flutter-apk/app-release.apk "build/dailylah-$version-$sha.apk"
echo "Built app/build/dailylah-$version-$sha.apk"
