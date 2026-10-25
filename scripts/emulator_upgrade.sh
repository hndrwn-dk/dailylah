#!/usr/bin/env bash
# Upgrade test (docs/QA.md section 5), run inside the Android emulator job.
# 1. Build and install the previous version (BASE_REF, default origin/main).
# 2. Give it the data a real user would have: a set-up household with a changed toggle.
# 3. Install the new build over it with `adb install -r` (no uninstall, data kept).
# 4. Run app/integration_test/upgrade_check_test.dart, which must find that data.
set -euo pipefail
# Name the failing command on the commit page (job logs are long).
trap 'echo "::error file=$0,line=$LINENO::Failed: $BASH_COMMAND"' ERR

PKG=com.tursinalabs.dailylah
DEVICE=emulator-5554
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_REF="${BASE_REF:-origin/main}"
OLD=/tmp/dailylah-old

echo "Previous version: $BASE_REF ($(git -C "$ROOT" rev-parse --short "$BASE_REF"))"
git -C "$ROOT" worktree add --force "$OLD" "$BASE_REF"
(cd "$OLD/app" && flutter pub get && flutter build apk --debug)
OLD_APK="$OLD/app/build/app/outputs/flutter-apk/app-debug.apk"

adb -s "$DEVICE" uninstall "$PKG" >/dev/null 2>&1 || true
adb -s "$DEVICE" install -t "$OLD_APK"
adb -s "$DEVICE" shell am start -W -n "$PKG/.MainActivity"
sleep 10
adb -s "$DEVICE" shell am force-stop "$PKG"

# Saved favourites in the format the app has always used (SharedPreferences key
# "flutter.favorites.v1"), with MRT alerts switched off by the user.
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
    "mrtAlerts": False,
    "onboarded": True,
}
print("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>")
print("<map>")
print(f'    <string name="flutter.favorites.v1">{escape(json.dumps(fav), {chr(34): "&quot;"})}</string>')
print("</map>")
PY
adb -s "$DEVICE" push /tmp/prefs.xml /data/local/tmp/dailylah_prefs.xml
adb -s "$DEVICE" shell "run-as $PKG mkdir -p shared_prefs"
adb -s "$DEVICE" shell "cat /data/local/tmp/dailylah_prefs.xml | run-as $PKG sh -c 'cat > shared_prefs/FlutterSharedPreferences.xml'"
adb -s "$DEVICE" shell "run-as $PKG cat shared_prefs/FlutterSharedPreferences.xml" | grep -q 'onboarded' \
  || { echo "::error::Could not seed the old version's saved data through run-as."; exit 1; }

# Let the old version start once with that data, as a user would before updating.
adb -s "$DEVICE" shell am start -W -n "$PKG/.MainActivity"
sleep 10
adb -s "$DEVICE" shell am force-stop "$PKG"

# Install the new build over the old one, keeping data.
cd "$ROOT/app"
flutter build apk --debug
adb -s "$DEVICE" install -r -t build/app/outputs/flutter-apk/app-debug.apk
echo "- Installed new build over $BASE_REF with adb install -r ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

flutter test integration_test/upgrade_check_test.dart -d "$DEVICE" --reporter expanded --file-reporter json:it.json \
  || { python3 ../scripts/test_failures.py it.json; exit 1; }
echo "- Saved data survived the upgrade ✅" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
