#!/usr/bin/env bash
# Daily check of the public web side (docs/QA.md, "Web check"), run by .github/workflows/web-check.yml.
# - https://dailylah.sg opens and is the DailyLah site.
# - /privacy and /terms on dailylah.sg lead to the policy pages on tursinalabs.com, which open.
# - Redirects are followed; a host that answers through a redirect (dailylah.sg -> www) is a warning.
# - data/manifest.json loads from every host in webUrls (app/lib/api.dart) and is valid: a version,
#   a non-empty list of files, each with a path and a sha256; one small bundle matches its sha256.
# - /where-to-live opens with its Content-Security-Policy, and data/where-to-live.json is valid
#   (26 towns, a commute for every office area).
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

# Server values (redirect targets, versions) go into workflow commands; keep them on one line.
clean() { printf '%s' "$1" | tr -d '\r\n%' | cut -c1-200; }

# fetch URL OUTFILE -> prints "status final_url redirects"; follows up to 5 redirects.
fetch() {
  curl -sS -L --max-redirs 5 --max-time 30 --retry 2 --retry-delay 5 --retry-all-errors \
    -A "dailylah-web-check" -o "$2" -w '%{http_code} %{url_effective} %{num_redirects}' "$1" \
    2>/dev/null || echo "000 $1 0"
}

# note URL FINAL HOPS: a warning when a host answers through a redirect (an extra hop for the app).
note_redirect() {
  if [ "$3" != 0 ]; then
    echo "::warning::$1 redirects to $(clean "$2") ($3 hop): one extra request for every download"
    echo "- ⚠️ $1 redirects to $(clean "$2")" >> "$SUMMARY"
  fi
}

echo "### Web check" >> "$SUMMARY"

# 1. The site opens.
read -r code final hops <<< "$(fetch "$SITE/" "$TMP/home.html")"
if [ "$code" = 200 ] && grep -qi "dailylah" "$TMP/home.html"; then
  ok "$SITE opens (200)"
  note_redirect "$SITE" "$final" "$hops"
else
  fail "$SITE answered $code at $(clean "$final") or is not the DailyLah page"
fi

# 2. Privacy and terms end on the right pages, and those pages open.
for page in privacy terms; do
  read -r code final _ <<< "$(fetch "$SITE/$page" "$TMP/$page.html")"
  if [ "$code" = 200 ] && [ "$final" = "$POLICY/$page" ]; then
    ok "$SITE/$page leads to $POLICY/$page (200)"
  else
    fail "$SITE/$page ends at $(clean "$final") with $code, expected $POLICY/$page"
  fi
done

# 3. The manifest loads from every host and is valid JSON with the expected shape.
versions=()
for host in "${HOSTS[@]}"; do
  file="$TMP/manifest-$(echo "$host" | tr -c 'a-z0-9' '_').json"
  read -r code final hops <<< "$(fetch "$host/data/manifest.json" "$file")"
  if [ "$code" != 200 ]; then
    fail "$host/data/manifest.json answered $code at $(clean "$final")"
    continue
  fi
  note_redirect "$host/data" "$final" "$hops"
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
    version=$(clean "$version")
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
  read -r code _ _ <<< "$(fetch "${HOSTS[0]}/data/$path" "$TMP/bundle")"
  got=$(sha256sum "$TMP/bundle" | cut -d' ' -f1)
  if [ "$code" = 200 ] && [ "$got" = "$want" ]; then
    ok "${HOSTS[0]}/data/$path matches its sha256"
  else
    fail "${HOSTS[0]}/data/$(clean "$path") answered $code with sha256 $got, manifest says $(clean "$want")"
  fi
fi

# 5. The Where to live? page opens with its CSP, and its data file is valid.
read -r code final _ <<< "$(fetch "$SITE/where-to-live" "$TMP/wtl.html")"
csp=$(curl -sS -L --max-time 30 -A "dailylah-web-check" -o /dev/null -D - "$SITE/where-to-live" 2>/dev/null \
  | grep -i '^content-security-policy:' | tail -1)
if [ "$code" = 200 ] && grep -q 'id="board-body"' "$TMP/wtl.html" && [ -n "$csp" ]; then
  ok "$SITE/where-to-live opens (200) with a Content-Security-Policy"
elif [ "${GITHUB_EVENT_NAME:-}" = pull_request ] && [ "$code" = 404 ]; then
  # The live site serves main: a pull request that adds or moves the page cannot pass this yet.
  echo "::warning::$SITE/where-to-live answered 404; expected before the page is on main"
  echo "- ⚠️ $SITE/where-to-live answered 404 (not on main yet)" >> "$SUMMARY"
else
  fail "$SITE/where-to-live answered $code at $(clean "$final"), board missing or no CSP header"
fi
read -r code _ _ <<< "$(fetch "$SITE/data/where-to-live.json" "$TMP/wtl.json")"
if [ "$code" = 200 ] && python3 - "$TMP/wtl.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
areas = [a["id"] for a in d["areas"]]
assert len(d["towns"]) == 26 and len(areas) == 6
for t in d["towns"]:
    assert set(areas) <= set(t["commute"]), t["id"]
PY
then
  ok "$SITE/data/where-to-live.json is valid (26 towns, 6 office areas)"
else
  fail "$SITE/data/where-to-live.json answered $code or is not valid"
fi

rm -rf "$TMP"
if [ "$failures" -gt 0 ]; then
  echo "$failures problem(s) found."
  exit 1
fi
echo "All web checks passed."
