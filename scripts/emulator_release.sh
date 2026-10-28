#!/usr/bin/env bash
# Release (R8) smoke test, run inside the Android emulator job.
# The integration tests run a debug build, which R8 never touches. This starts the real
# release build with saved data and runs its background check and widget, then fails on any
# sign that R8 removed or renamed something a plugin needs.
# 1. Install the debug build and seed a set-up household through run-as (debug only).
# 2. Install the release build over it (same debug key without CI secrets; data kept).
# 3. Start it, force-run the WorkManager job (which also updates the widget), then read logcat.
#    (APPWIDGET_UPDATE is a protected broadcast; adb cannot send it.)
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
# The App Bundle must carry native debug symbols for Play (ndk.debugSymbolLevel).
flutter build appbundle --release -v > /tmp/aab.log 2>&1 || { tail -40 /tmp/aab.log; exit 1; }
AAB=build/app/outputs/bundle/release/app-release.aab
# Diagnostics (shown on the commit): NDKs on the runner, what Gradle said about stripping and
# symbols, and the native files in the bundle.
echo "::notice title=NDKs on runner::$(ls "$ANDROID_HOME/ndk" 2>/dev/null | tr '\n' ' ')"
grep -iE "ndk|strip|debug ?symbol|debugsymbols" /tmp/aab.log | grep -viE "^\s*$" | sort -u | head -15 \
  | while read -r line; do echo "::notice title=gradle::${line:0:250}"; done
unzip -l "$AAB" | grep -E "\.so|BUNDLE-METADATA" | awk '{print $1, $4}' | head -20 \
  | while read -r line; do echo "::notice title=aab::$line"; done
unzip -l "$AAB" | grep -q "BUNDLE-METADATA/com.android.tools.build.debugsymbols/" \
  || { echo "::error::The release App Bundle has no native debug symbols."; exit 1; }

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
# Line format: "JOB #u0a209/1: ..." or, from Android 14, "JOB <namespace>:u0a209/1: ...".
LINE=$("${ADB[@]}" shell dumpsys jobscheduler | grep -m1 "$PKG/androidx.work" | tr -d '\r' || true)
JOB=$(echo "$LINE" | sed -n 's/.*JOB [^ ]*u[0-9a-z]*\/\([0-9]*\):.*/\1/p')
NS=$(echo "$LINE" | sed -n 's/.*JOB \([^# ][^ ]*\):u[0-9a-z]*\/.*/\1/p')
if [ -z "$JOB" ]; then
  echo "::error::The release build registered no WorkManager job (saved data not read, or WorkManager failed)."
  "${ADB[@]}" shell dumpsys jobscheduler | grep -i "$PKG" | head -5 \
    | while read -r line; do echo "::notice title=jobscheduler::${line:0:300}"; done
  JOB_MISSING=1
else
  "${ADB[@]}" shell cmd jobscheduler run -f ${NS:+-n "$NS"} "$PKG" "$JOB"
  # It calls the production API, which may need a minute to wake up.
  for _ in $(seq 1 36); do
    "${ADB[@]}" logcat -d -s flutter | grep -q "background check done" && break
    sleep 5
  done
  "${ADB[@]}" logcat -d -s flutter | grep -q "background check done" \
    || echo "::warning::The background check did not report done within 3 min (slow API?)."
fi

# Restart once more: settings read again from disk.
"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell am start -W -n "$PKG/.MainActivity"
sleep 10

LOG=$("${ADB[@]}" logcat -d)
echo "$LOG" | grep -E "flutter|AndroidRuntime" | tail -60 || true
# Job logs cannot always be read, so surface the app's own log lines on the commit too.
echo "$LOG" | grep -E " I flutter|AndroidRuntime" | tail -15 \
  | while read -r line; do echo "::notice title=logcat::${line:0:300}"; done
BAD='FATAL EXCEPTION|ClassNotFoundException|NoClassDefFoundError|NoSuchMethodError|NoSuchMethodException|NoSuchFieldError|NoSuchFieldException|AbstractMethodError|MissingPluginException|favourites not loaded|notifications not ready|background work not registered'
if echo "$LOG" | grep -E "$BAD" >/tmp/bad.txt; then
  while read -r line; do echo "::error::release build: ${line:0:300}"; done < /tmp/bad.txt
  exit 1
fi
"${ADB[@]}" shell pidof "$PKG" >/dev/null || { echo "::error::Release build is not running after restart."; exit 1; }
[ -z "${JOB_MISSING:-}" ] || exit 1
echo "- Release build (R8) started, ran the background check without errors ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
