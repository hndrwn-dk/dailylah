#!/usr/bin/env bash
# Daily check of the public web side (docs/QA.md, "Web check"), run by .github/workflows/web-check.yml.
# - https://dailylah.sg opens and is the DailyLah site.
# - /privacy and /terms on dailylah.sg redirect to the policy pages on tursinalabs.com, which open.
# - data/manifest.json loads from every host in webUrls (app/lib/api.dart) and is valid: a version,
#   a non-empty list of files, each with a path and a sha256; one small bundle matches its sha256.
# Every problem is printed as an error; the script fails at the end if there was any.
set -uo pipefail

SITE=https://dailylah.sg
HOSTS=(https://dailylah.sg https://dailylah.tursinalabs.com https://dailylah-web.vercel.app)
POLICY=https://www.tursinalabs.com/dailylah
TMP=$(mktemp -d)
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
failures=0

fail() { echo "::error::$1"; echo "- ❌ $1" >> "$SUMMARY"; failures=$((failures + 1)); }
ok() { echo "ok: $1"; echo "- ✅ $1" >> "$SUMMARY"; }

# fetch URL OUTFILE -> prints "status redirect_url"; never follows redirects.
fetch() {
  curl -sS --max-time 30 --retry 2 --retry-delay 5 --retry-all-errors \
    -A "dailylah-web-check" -o "$2" -w '%{http_code} %{redirect_url}' "$1" 2>/dev/null || echo "000 "
}

echo "### Web check" >> "$SUMMARY"

# 1. The site opens.
read -r code _ <<< "$(fetch "$SITE/" "$TMP/home.html")"
if [ "$code" = 200 ] && grep -qi "dailylah" "$TMP/home.html"; then
  ok "$SITE opens (200)"
else
  fail "$SITE answered $code or is not the DailyLah page"
fi

# 2. Privacy and terms redirect to the right pages, and those pages open.
for page in privacy terms; do
  read -r code location <<< "$(fetch "$SITE/$page" /dev/null)"
  if [[ "$code" =~ ^30[1278]$ ]] && [ "$location" = "$POLICY/$page" ]; then
    read -r target _ <<< "$(fetch "$location" "$TMP/$page.html")"
    if [ "$target" = 200 ]; then
      ok "$SITE/$page redirects to $location (200)"
    else
      fail "$SITE/$page redirects to $location, which answered $target"
    fi
  else
    fail "$SITE/$page answered $code to '${location:-nothing}', expected a redirect to $POLICY/$page"
  fi
done

# 3. The manifest loads from every host and is valid JSON with the expected shape.
versions=()
for host in "${HOSTS[@]}"; do
  file="$TMP/manifest-$(echo "$host" | tr -c 'a-z0-9' '_').json"
  read -r code _ <<< "$(fetch "$host/data/manifest.json" "$file")"
  if [ "$code" != 200 ]; then
    fail "$host/data/manifest.json answered $code"
    continue
  fi
  if version=$(python3 - "$file" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
files = m["files"]
assert isinstance(m["version"], str) and m["version"], "no version"
assert isinstance(files, dict) and files, "no files"
for name, f in files.items():
    assert f.get("path") and len(f.get("sha256", "")) == 64, f"bad entry {name}"
print(m["version"])
PY
  ); then
    ok "$host/data/manifest.json is valid (version $version)"
    versions+=("$version")
  else
    fail "$host/data/manifest.json is not a valid manifest"
  fi
done
if [ "${#versions[@]}" -gt 1 ] && [ "$(printf '%s\n' "${versions[@]}" | sort -u | wc -l)" -gt 1 ]; then
  # Same Vercel deployment behind every host; a difference is only a cache (max-age 1 h) catching up.
  echo "::warning::Hosts serve different manifest versions: ${versions[*]}"
  echo "- ⚠️ Hosts serve different manifest versions: ${versions[*]}" >> "$SUMMARY"
fi

# 4. One small bundle from the first host matches the sha256 in its manifest.
first="$TMP/manifest-$(echo "${HOSTS[0]}" | tr -c 'a-z0-9' '_').json"
if [ -s "$first" ] && pick=$(python3 - "$first" <<'PY' 2>/dev/null
import json, sys
files = json.load(open(sys.argv[1]))["files"]
name = min(files, key=lambda n: files[n].get("count", 10**9))
print(files[name]["path"], files[name]["sha256"])
PY
); then
  read -r path want <<< "$pick"
  read -r code _ <<< "$(fetch "${HOSTS[0]}/data/$path" "$TMP/bundle")"
  got=$(sha256sum "$TMP/bundle" | cut -d' ' -f1)
  if [ "$code" = 200 ] && [ "$got" = "$want" ]; then
    ok "${HOSTS[0]}/data/$path matches its sha256"
  else
    fail "${HOSTS[0]}/data/$path answered $code with sha256 $got, manifest says $want"
  fi
fi

rm -rf "$TMP"
if [ "$failures" -gt 0 ]; then
  echo "$failures problem(s) found."
  exit 1
fi
echo "All web checks passed."
