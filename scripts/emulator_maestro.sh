#!/usr/bin/env bash
# Maestro flows (app/maestro) on the release build, as a person would use it (docs/QA.md).
# - Release run (app workflow, AAB_ARTIFACT set): a universal APK made with bundletool from the
#   exact App Bundle that goes to Google Play, signed with a throwaway key (the upload key never
#   reaches this job; the signature does not change how the app behaves).
# - Pull request: the R8 release APK built from this commit (debug key, no CI secrets).
# Fails when the installed build is debuggable, i.e. not a release build.
# Before the flows: waits until the emulator answers on adb and wakes the API on Render. A failed
# run prints why (report.xml, the failed step, crash buffer, app log, screen) and runs every flow
# once more; passing then is a warning ("Maestro flaky"), failing twice fails the job.
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

API="https://dailylah-api.onrender.com"
ADB=(adb -s "$DEVICE")

# Workflow commands take one line; keep server and log text from breaking them.
clean() { tr -d '\r%' | tr '\n' ' ' | sed 's/::/: :/g' | cut -c1-400; }

# The emulator runner reports "booted" before adb always answers ("device offline" in some runs).
wait_for_device() {
  timeout 120 "${ADB[@]}" wait-for-device || true
  for _ in $(seq 1 60); do
    if [ "$("${ADB[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] \
      && "${ADB[@]}" shell pm path android >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "::warning::The emulator was not fully online after 2 min; running the flows anyway."
}

# Render's free tier sleeps; wake the API here so a cold start does not land inside a flow.
warm_api() {
  local start=$SECONDS
  while [ $((SECONDS - start)) -lt 90 ]; do
    if curl -fsS -m 20 -o /dev/null "$API/health" 2>/dev/null; then
      echo "API awake after $((SECONDS - start)) s"
      return 0
    fi
    sleep 5
  done
  echo "::warning::$API/health did not answer within 90 s; the flows may wait for a cold start."
}

# run_attempt N: fresh install, then every flow in order. Results go to $OUT/attempt-N.
run_attempt() {
  local dir="$OUT/attempt-$1"
  mkdir -p "$dir"
  wait_for_device
  # Singapore time, as users have it: the emulator image runs on UTC, which shows night-time cards
  # (no trains, buses stopped) in the Singapore afternoon.
  "${ADB[@]}" shell cmd alarm set-timezone Asia/Singapore >/dev/null 2>&1 \
    || echo "::warning::Could not set the emulator to Singapore time; flows run on its default zone."
  "${ADB[@]}" uninstall "$PKG" >/dev/null 2>&1 || true
  "${ADB[@]}" install "$APK" >/dev/null
  "${ADB[@]}" logcat -c 2>/dev/null || true
  # Screenshots and recordings go to --test-output-dir (Maestro 2 ignores the working directory).
  (cd "$dir" && maestro --device "$DEVICE" test --config "$ROOT/app/maestro/config.yaml" \
    "$ROOT/app/maestro" --format junit --output "$dir/report.xml" --debug-output "$dir/debug" \
    --test-output-dir "$dir/output")
}

# flow_lines N: one line per flow in the job summary, from the JUnit report.
flow_lines() {
  python3 - "$OUT/attempt-$1/report.xml" <<'EOF'
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
}

# reasons N: "flow: message" for each failed flow (report.xml, else the failed step in debug/).
reasons() {
  python3 - "$OUT/attempt-$1" <<'EOF'
import glob, json, os, sys
import xml.etree.ElementTree as ET
d = sys.argv[1]
out = []
try:
    for case in ET.parse(os.path.join(d, "report.xml")).getroot().iter("testcase"):
        bad = case.find("failure") if case.find("failure") is not None else case.find("error")
        if bad is not None:
            msg = (bad.get("message") or bad.text or "").strip().splitlines()
            out.append(f"{case.get('name')}: {msg[0] if msg else 'no message'}")
except (OSError, ET.ParseError):
    out.append("Maestro did not finish (no report.xml)")
print("; ".join(out) or "unknown")
EOF
}

# diagnose N: why attempt N failed, in the job log (artifacts cannot always be read).
diagnose() {
  local dir="$OUT/attempt-$1"
  echo "::group::Attempt $1: failed flows (report.xml)"
  python3 - "$dir/report.xml" <<'EOF' || true
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except (OSError, ET.ParseError):
    print("No report.xml: Maestro stopped before writing it.")
    raise SystemExit
for case in root.iter("testcase"):
    for tag in ("failure", "error"):
        bad = case.find(tag)
        if bad is not None:
            print(f"{case.get('name')} ({case.get('time')} s): {bad.get('message') or ''}")
            if bad.text and bad.text.strip():
                print("  " + "\n  ".join(bad.text.strip().splitlines()[:20]))
EOF
  echo "::endgroup::"
  echo "::group::Attempt $1: last steps before the failure (debug output)"
  python3 - "$dir" <<'EOF' || true
import glob, json, os, sys
d = sys.argv[1]
def describe(cmd):
    if not isinstance(cmd, dict) or not cmd:
        return str(cmd)[:200]
    name, body = next(iter(cmd.items()))
    return f"{name} {json.dumps(body, separators=(',', ':'))[:200]}"
def command_lists(node):
    # commands*.json is a list of {command, metadata}; find such lists wherever they sit.
    if isinstance(node, list):
        if node and all(isinstance(c, dict) and "metadata" in c for c in node):
            yield node
        for c in node:
            yield from command_lists(c)
    elif isinstance(node, dict):
        for v in node.values():
            yield from command_lists(v)
found = False
files = glob.glob(os.path.join(d, "**", "commands*.json"), recursive=True)
for f in sorted(files):
    try:
        data = json.load(open(f))
    except (OSError, ValueError):
        continue
    for cmds in command_lists(data):
        failed = [i for i, c in enumerate(cmds) if (c.get("metadata") or {}).get("status") == "FAILED"]
        if not failed:
            continue
        found = True
        i = failed[0]
        print(f"{os.path.relpath(f, d)}:")
        for c in cmds[max(0, i - 5):i + 1]:
            print(f"  {(c.get('metadata') or {}).get('status', '?'):9} {describe(c.get('command'))}")
        err = (cmds[i].get("metadata") or {}).get("error") or {}
        print(f"  error: {err.get('message') if isinstance(err, dict) else err}")
if not found:
    logs = sorted(glob.glob(os.path.join(d, "**", "maestro.log"), recursive=True))
    names = sorted(os.path.relpath(p, d) for p in glob.glob(os.path.join(d, "**", "*"), recursive=True))
    print(f"No failed step in {len(files)} commands*.json file(s). Files: {', '.join(names[:30]) or 'none'}")
    if logs:
        lines = open(logs[-1], errors="replace").read().splitlines()
        print(f"Last lines of {os.path.relpath(logs[-1], d)}:")
        print("\n".join(lines[-40:]))
EOF
  echo "::endgroup::"
  echo "::group::Attempt $1: crash buffer (adb logcat -b crash)"
  "${ADB[@]}" logcat -d -b crash 2>/dev/null | tail -100 || true
  echo "::endgroup::"
  echo "::group::Attempt $1: app log (flutter, AndroidRuntime, $PKG)"
  "${ADB[@]}" logcat -d -v time 2>/dev/null | grep -E "flutter|AndroidRuntime|$PKG" \
    | grep -vE "I/Maestro|D/UiDevice|WindowManager|AppsFilter|nativeloader|ImeTracker" \
    | cut -c1-300 | tail -200 || true
  echo "::endgroup::"
  echo "::group::Attempt $1: screen when the flows stopped"
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
  "${ADB[@]}" logcat -d -t 400 '*:E' > "$dir/logcat-errors.txt" 2>/dev/null || true
}

warm_api

# "|| rc=$?" keeps the ERR trap quiet: a failed first attempt is not yet a job failure.
rc=0
run_attempt 1 || rc=$?
echo "- Attempt 1:" >> "$SUMMARY"
flow_lines 1 | sed 's/^/  /' >> "$SUMMARY"

if [ "$rc" -ne 0 ]; then
  first=$(reasons 1 | clean)
  diagnose 1
  # One more run of every flow (01 sets up the household the others need), on a fresh install.
  echo "Attempt 1 failed ($first); running all flows once more."
  warm_api
  rc=0
  run_attempt 2 || rc=$?
  echo "- Attempt 2:" >> "$SUMMARY"
  flow_lines 2 | sed 's/^/  /' >> "$SUMMARY"
  if [ "$rc" -eq 0 ]; then
    echo "::warning title=Maestro flaky::Passed on retry. Attempt 1 failed: $first"
    echo "- ⚠️ Maestro flaky: passed on retry. Attempt 1 failed: $first" >> "$SUMMARY"
  else
    diagnose 2
    echo "::error title=Maestro::Failed twice. Attempt 1: $first. Attempt 2: $(reasons 2 | clean)"
  fi
  echo "- Screenshots, videos, reports and logs: artifact maestro-results" >> "$SUMMARY"
else
  # Nothing to keep when every flow passed the first time.
  rm -rf "$OUT/attempt-1"
fi
exit "$rc"
