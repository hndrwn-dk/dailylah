#!/usr/bin/env bash
# Sign the release App Bundle with the upload key (docs/QA.md "Release signing").
# Run by the `sign` job in app.yml, which checks out only this file and runs no Gradle or pub
# code, so the key is never readable by third-party build code. JDK tools only.
#   scripts/sign_aab.sh <unsigned.aab> <signed.aab>
# Env: KEYSTORE_B64 (base64 keystore), KS_PASS, KEY_ALIAS, KEY_PASS, EXPECTED_SHA256 (the upload
# certificate's SHA-256 from Play Console; colons and case do not matter).
set -euo pipefail
IN=$1
OUT=$2
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
norm() { tr -d ': \r\n' | tr '[:lower:]' '[:upper:]'; }

[ -f "$IN" ] || { echo "::error::No App Bundle at $IN."; exit 1; }
for v in KEYSTORE_B64 KS_PASS KEY_ALIAS KEY_PASS EXPECTED_SHA256; do
  [ -n "${!v:-}" ] || { echo "::error::$v is not set (environment \"signing\": secrets ANDROID_KEYSTORE_*, variable UPLOAD_CERT_SHA256)."; exit 1; }
done

# The build must be unsigned: a second signature (e.g. the debug key) would ship next to ours.
if unzip -Z1 "$IN" | grep -Eiq '^META-INF/[^/]+\.(RSA|DSA|EC)$'; then
  echo "::error::$IN is already signed ($(unzip -Z1 "$IN" | grep -Ei '^META-INF/[^/]+\.(RSA|DSA|EC)$' | tr '\n' ' ')); build it with DAILYLAH_UNSIGNED_RELEASE=1."
  exit 1
fi

KS=$(mktemp)
# The keystore never outlives the script; a failed signing leaves no signed file behind.
trap 'rc=$?; rm -f "$KS"; [ "$rc" -eq 0 ] || rm -f "$OUT"' EXIT
printf '%s' "$KEYSTORE_B64" | base64 -d > "$KS"

mkdir -p "$(dirname "$OUT")"
cp "$IN" "$OUT"
jarsigner -keystore "$KS" -storepass:env KS_PASS -keypass:env KEY_PASS -digestalg SHA-256 \
  "$OUT" "$KEY_ALIAS" >/dev/null
# Not -strict: an upload certificate is self-signed, which -strict always rejects. Instead: the
# signature verifies, every entry is signed, and the certificate is the expected one (below).
verify=$(jarsigner -verify "$OUT" 2>&1) || { echo "::error::jarsigner -verify failed: $verify"; exit 1; }
if ! grep -q '^jar verified' <<< "$verify" || grep -Eqi 'unsigned entries|is not signed|not signed by' <<< "$verify"; then
  echo "::error::The signed App Bundle does not verify: $(tr '\n' ' ' <<< "$verify" | cut -c1-300)"
  exit 1
fi

got=$(keytool -printcert -jarfile "$OUT" | sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' | head -1 | norm)
want=$(printf '%s' "$EXPECTED_SHA256" | norm)
if [ -z "$got" ] || [ "$got" != "$want" ]; then
  echo "::error::Signed with certificate SHA-256 ${got:-none}, but UPLOAD_CERT_SHA256 is $want. Wrong keystore or alias; nothing is uploaded."
  exit 1
fi
echo "Signed $OUT; upload certificate SHA-256 $got matches."
echo "- App Bundle signed with the upload key ✅ (certificate SHA-256 ${got:0:16}…)" >> "$SUMMARY"
