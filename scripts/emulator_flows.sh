#!/usr/bin/env bash
# Runs inside the Android emulator job (.github/workflows/emulator.yml).
# Installs the app with location revoked and notifications allowed, runs the on-device
# flows in app/integration_test/app_test.dart, then checks the system really posted the
# background MRT notification.
set -euo pipefail
# Name the failing command on the commit page (job logs are long).
trap 'echo "::error file=$0,line=$LINENO::Failed: $BASH_COMMAND"' ERR

PKG=com.tursinalabs.dailylah
DEVICE=emulator-5554
cd "$(dirname "$0")/../app"

flutter build apk --debug
APK=build/app/outputs/flutter-apk/app-debug.apk

# Report the minimum Android version the APK supports, so the device matrix stays honest.
AAPT=$(ls "$ANDROID_HOME"/build-tools/*/aapt | tail -1)
MIN_SDK=$("$AAPT" dump badging "$APK" | sed -n "s/^sdkVersion:'\([0-9]*\)'/\1/p")
TARGET_SDK=$("$AAPT" dump badging "$APK" | sed -n "s/^targetSdkVersion:'\([0-9]*\)'/\1/p")
API=$(adb -s "$DEVICE" shell getprop ro.build.version.sdk | tr -d '\r')
{
  echo "### Emulator API $API"
  echo "- APK minSdk: $MIN_SDK, targetSdk: $TARGET_SDK"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [ "${EXPECT_MIN_API:-}" = "true" ] && [ "$API" != "$MIN_SDK" ]; then
  echo "::warning::This job is meant to run on the lowest supported Android, but the APK minSdk is $MIN_SDK and the emulator is API $API. Update the matrix in emulator.yml."
fi

adb -s "$DEVICE" install -r -t "$APK"

# The home screen widget provider is registered with the system.
if adb -s "$DEVICE" shell dumpsys package "$PKG" | grep -q "DailyLahWidgetProvider"; then
  echo "- Home screen widget provider: registered ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
else
  echo "::error::DailyLahWidgetProvider (APPWIDGET_UPDATE receiver) is missing from the installed package."
  exit 1
fi
# Notifications allowed (API 33+ only has this runtime permission), location refused.
adb -s "$DEVICE" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
adb -s "$DEVICE" shell pm revoke "$PKG" android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
adb -s "$DEVICE" shell pm revoke "$PKG" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true

flutter test integration_test/app_test.dart -d "$DEVICE" --reporter expanded --file-reporter json:it.json \
  || { python3 ../scripts/test_failures.py it.json; exit 1; }

echo "- On-device flows incl. real notification: passed ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
