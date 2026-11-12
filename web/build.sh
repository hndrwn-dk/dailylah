#!/usr/bin/env bash
# Vercel build step for dailylah.sg (web/vercel.json "buildCommand"; runs in web/).
# The site is static and needs no build. This only lays the published data over the copy on
# main: the daily and weekly data workflows push to the branch `data`, not to main
# (docs/DEPLOY.md, "Data branch"), so every deploy takes the bundles, the "Living in <town>"
# pages and the sitemap from there. main's own copies are what the tests read.
#
# Only plain files of the kinds listed below are taken, into the folders they belong to; nothing
# else on that branch reaches the site. No data branch yet: main's copies are served. Any other
# download problem fails the build, so the previous deployment (with its newer data) stays up.
set -euo pipefail

url="https://codeload.github.com/hndrwn-dk/dailylah/tar.gz/refs/heads/data"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${DATA_TARBALL:-}" ]; then
  # Tests: a tarball on disk instead of the download.
  cp "$DATA_TARBALL" "$tmp/data.tgz"
else
  code=$(curl --silent --show-error --location --max-time 120 \
    --output "$tmp/data.tgz" --write-out '%{http_code}' "$url") || code=000
  if [ "$code" = 404 ]; then
    echo "No data branch yet: serving the data committed on main."
    exit 0
  elif [ "$code" != 200 ]; then
    echo "Could not download the data branch (HTTP $code)."
    exit 1
  fi
fi

mkdir "$tmp/tree"
tar -xzf "$tmp/data.tgz" -C "$tmp/tree" --strip-components=1 --no-same-owner
src="$tmp/tree/web"

# take <folder> <extension>: the folder's files of that kind become exactly the branch's.
take() {
  local dir=$1 ext=$2 count
  [ -d "$src/$dir" ] || return 0
  count=$(find "$src/$dir" -maxdepth 1 -type f -name "*.$ext" | wc -l)
  [ "$count" -gt 0 ] || return 0
  mkdir -p "$dir"
  find "$dir" -maxdepth 1 -type f -name "*.$ext" -delete
  # -type f: plain files only, never a link to something else.
  find "$src/$dir" -maxdepth 1 -type f -name "*.$ext" -exec cp {} "$dir/" \;
  echo "$dir: $count .$ext files from the data branch"
}

if [ ! -f "$src/data/manifest.json" ] || [ -L "$src/data/manifest.json" ]; then
  echo "The data branch has no web/data/manifest.json."
  exit 1
fi
take data json
take where-to-live-towns html
if [ -f "$src/sitemap.xml" ] && [ ! -L "$src/sitemap.xml" ]; then
  cp "$src/sitemap.xml" sitemap.xml
  echo "sitemap.xml from the data branch"
fi
[ -s data/manifest.json ] || { echo "data/manifest.json is empty after the overlay."; exit 1; }
