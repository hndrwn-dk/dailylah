#!/usr/bin/env bash
# Maestro flows (app/maestro) on the release build, as a person would use it (docs/QA.md).
# - Release run (app workflow, AAB_ARTIFACT set): a universal APK made with bundletool from the
#   exact App Bundle that goes to Google Play, signed with a throwaway key (the upload key never
#   reaches this job; the signature does not change how the app behaves).
# - Pull request: the R8 release APK built from this commit (debug key, no CI secrets).
# Fails when the installed build is debuggable, i.e. not a release build.
set -euo pipefail
trap 'echo "::error file=$0,line=$LINENO::Failed: $BASH_COMMAND"' ERR

PKG=com.tursinalabs.dailylah
DEVICE=emulator-5554
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${RUNNER_TEMP:-/tmp}/maestro-out"
mkdir -p "$OUT"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -n "${AAB_ARTIFACT:-}" ]; then
  AAB="${RUNNER_TEMP:-/tmp}/aab/dailylah.aab"
  KS="${RUNNER_TEMP:-/tmp}/maestro.jks"
  keytool -genkeypair -keystore "$KS" -storepass maestro -keypass maestro -alias maestro \
    -keyalg RSA -keysize 2048 -validity 1 -dname "CN=Maestro CI" >/dev/null 2>&1
  java -jar "${RUNNER_TEMP:-/tmp}/bundletool.jar" build-apks --mode=universal --overwrite \
    --bundle="$AAB" --output="$OUT/dailylah.apks" \
    --ks="$KS" --ks-pass=pass:maestro --ks-key-alias=maestro --key-pass=pass:maestro
  unzip -o -q "$OUT/dailylah.apks" universal.apk -d "$OUT"
  APK="$OUT/universal.apk"
  SOURCE="universal APK from the App Bundle uploaded to Google Play"
else
  APK="$ROOT/app/build/app/outputs/flutter-apk/app-release.apk"
  SOURCE="R8 release APK built from this commit"
fi

AAPT=$(ls "$ANDROID_HOME"/build-tools/*/aapt | tail -1)
if "$AAPT" dump badging "$APK" | grep -q "application-debuggable"; then
  echo "::error::$APK is debuggable; Maestro must test a release build."
  exit 1
fi
VERSION=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
{
  echo "### Maestro flows (release build)"
  echo "- Tested: $SOURCE, version $VERSION"
} >> "$SUMMARY"

adb -s "$DEVICE" uninstall "$PKG" >/dev/null 2>&1 || true
adb -s "$DEVICE" install "$APK"

set +e
cd "$OUT"  # takeScreenshot and startRecording write here
maestro --device "$DEVICE" test --config "$ROOT/app/maestro/config.yaml" "$ROOT/app/maestro" \
  --format junit --output "$OUT/report.xml" \
  --debug-output "$OUT/debug"
rc=$?
set -e

# One line per flow in the job summary, from the JUnit report.
python3 - "$OUT/report.xml" >> "$SUMMARY" <<'EOF'
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except (OSError, ET.ParseError):
    print("- No report: Maestro did not finish.")
    raise SystemExit
for case in root.iter("testcase"):
    failed = case.find("failure") is not None or case.find("error") is not None
    print(f"- {case.get('name')}: {'❌ failed' if failed else '✅ passed'}")
EOF

# Where the app stopped: the texts on screen, to read the failure without the artifact.
if [ "$rc" -ne 0 ]; then
  echo "::group::Screen when the flows stopped"
  maestro --device "$DEVICE" hierarchy 2>/dev/null | python3 -c '
import json, sys
def walk(n):
    a = n.get("attributes", {})
    for k in ("text", "accessibilityText", "hintText", "resource-id"):
        v = (a.get(k) or "").strip()
        if v:
            print(f"{k}: {v[:160]}")
    for c in n.get("children", []):
        walk(c)
try:
    walk(json.load(sys.stdin))
except ValueError:
    print("(no hierarchy)")
' || true
  echo "::endgroup::"
  adb -s "$DEVICE" logcat -d -t 400 '*:E' > "$OUT/logcat-errors.txt" 2>/dev/null || true
  echo "- Screenshots, videos and logs: artifact maestro-results" >> "$SUMMARY"
fi
# TEMPORARY (Phase 3 work): print the screenshots so the flows can be written from real screens.
adb -s "$DEVICE" logcat -d 2>/dev/null | grep -E "flutter|AndroidRuntime|dailylah|FATAL" | tail -60 || true
for f in "$OUT"/discover_*.png $(find "$OUT/debug" -name '*.png' 2>/dev/null | head -8); do
  [ -f "$f" ] || continue
  echo "::group::SHOT $(basename "$f")"
  convert "$f" -resize 45% -quality 55 jpg:- | base64 -w0
  echo
  echo "::endgroup::"
done
exit "$rc"
