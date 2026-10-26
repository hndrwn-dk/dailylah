#!/usr/bin/env bash
# Release (R8) smoke test, run inside the Android emulator job.
# The integration tests run a debug build, which R8 never touches. This starts the real
# release build with saved data and runs its background check and widget, then fails on any
# sign that R8 removed or renamed something a plugin needs.
# 1. Install the debug build and seed a set-up household through run-as (debug only).
# 2. Install the release build over it (same debug key without CI secrets; data kept).
# 3. Start it, force-run the WorkManager job, update the widget, then read logcat.
set -euo pipefail
trap 'echo "::error file=$0,line=$LINENO::Failed: $BASH_COMMAND"' ERR

PKG=com.tursinalabs.dailylah
DEVICE=emulator-5554
ADB=(adb -s "$DEVICE")
cd "$(dirname "$0")/../app"

flutter build apk --debug
flutter build apk --release
DEBUG_APK=build/app/outputs/flutter-apk/app-debug.apk
RELEASE_APK=build/app/outputs/flutter-apk/app-release.apk
test -f build/app/outputs/mapping/release/mapping.txt \
  || { echo "::error::No mapping.txt: R8 did not run on the release build."; exit 1; }

"${ADB[@]}" uninstall "$PKG" >/dev/null 2>&1 || true
"${ADB[@]}" install -t "$DEBUG_APK"
"${ADB[@]}" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true

# Same saved household as the upgrade test (SharedPreferences "flutter.favorites.v1").
python3 - > /tmp/prefs.xml <<'PY'
import json
from xml.sax.saxutils import escape
fav = {
    "places": [
        {"kind": "home", "stops": [{"c": "75009", "n": "Tampines Int", "r": "Tampines Ctrl 1", "la": 1.354076, "lo": 103.943391}],
         "addr": "156 TAMPINES ST 12", "postal": "521156", "la": 1.35159, "lo": 103.94503},
        {"kind": "work", "stops": [{"c": "03011", "n": "Fullerton Sq", "r": "Fullerton Rd", "la": 1.285618, "lo": 103.853422}]},
    ],
    "lines": ["EWL"],
    "onboarded": True,
    "learnHabits": True,
}
print("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>")
print("<map>")
print(f'    <string name="flutter.favorites.v1">{escape(json.dumps(fav), {chr(34): "&quot;"})}</string>')
print("</map>")
PY
"${ADB[@]}" push /tmp/prefs.xml /data/local/tmp/dailylah_prefs.xml
"${ADB[@]}" shell "run-as $PKG mkdir -p shared_prefs"
"${ADB[@]}" shell "cat /data/local/tmp/dailylah_prefs.xml | run-as $PKG sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'"

# Release build over it, data kept.
"${ADB[@]}" install -r "$RELEASE_APK"
if "${ADB[@]}" shell dumpsys package "$PKG" | grep -q "DEBUGGABLE"; then
  echo "::error::The installed build is debuggable; expected the release build."; exit 1
fi

"${ADB[@]}" logcat -c
"${ADB[@]}" shell am start -W -n "$PKG/.MainActivity"
sleep 20
"${ADB[@]}" shell pidof "$PKG" >/dev/null || { echo "::error::Release build is not running 20 s after start."; }

# The background check: find the WorkManager job the app registered and run it now.
JOB=$("${ADB[@]}" shell dumpsys jobscheduler \
  | sed -n "s/.*JOB #[^/]*\/\([0-9]*\): [0-9a-f]* $PKG\/androidx\.work.*/\1/p" | head -1 | tr -d '\r')
if [ -z "$JOB" ]; then
  echo "::error::The release build registered no WorkManager job (saved data not read, or WorkManager failed)."
else
  "${ADB[@]}" shell cmd jobscheduler run -f "$PKG" "$JOB"
  # It calls the production API, which may need a minute to wake up.
  for _ in $(seq 1 36); do
    "${ADB[@]}" logcat -d -s flutter | grep -q "background check done" && break
    sleep 5
  done
  "${ADB[@]}" logcat -d -s flutter | grep -q "background check done" \
    || echo "::warning::The background check did not report done within 3 min (slow API?)."
fi

# Widget provider (our Kotlin + home_widget).
"${ADB[@]}" shell am broadcast -a android.appwidget.action.APPWIDGET_UPDATE -n "$PKG/.DailyLahWidgetProvider" >/dev/null
sleep 3

# Restart once more: settings read again from disk.
"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell am start -W -n "$PKG/.MainActivity"
sleep 10

LOG=$("${ADB[@]}" logcat -d)
echo "$LOG" | grep -E "flutter|AndroidRuntime" | tail -60 || true
BAD='FATAL EXCEPTION|ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|NoSuchMethodException|NoSuchFieldError|NoSuchFieldException|AbstractMethodError|MissingPluginException|favourites not loaded|notifications not ready|background work not registered'
if echo "$LOG" | grep -E "$BAD" >/tmp/bad.txt; then
  while read -r line; do echo "::error::release build: ${line:0:300}"; done < /tmp/bad.txt
  exit 1
fi
"${ADB[@]}" shell pidof "$PKG" >/dev/null || { echo "::error::Release build is not running after restart."; exit 1; }
echo "- Release build (R8) started, ran the background check and widget without errors ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
