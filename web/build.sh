#!/usr/bin/env bash
# Vercel build step for dailylah.sg (web/vercel.json "buildCommand"; runs in web/).
# The site is static and needs no build. Where the published data lives is one word in
# data-source.txt (docs/DEPLOY.md, "Data branch"):
#   main  nothing to do: the data workflows push to main, and the site is served as it is.
#   data  the workflows push to the branch `data`, never to main, so every deploy takes the
#         bundles, the "Living in <town>" pages and the sitemap from there; main's own copies
#         are what the tests read.
# Only plain files of the kinds listed below are taken, into the folders they belong to; nothing
# else on that branch reaches the site. Any download problem, a missing branch included, fails
# the build, so the previous deployment (with its newer data) stays up.
set -euo pipefail

source=main
[ ! -f data-source.txt ] || source=$(tr -d '[:space:]' < data-source.txt)
if [ "$source" = main ]; then
  echo "Data source: main. Nothing to lay over the site."
  exit 0
elif [ "$source" != data ]; then
  echo "data-source.txt must say main or data."
  exit 1
fi

url="https://codeload.github.com/hndrwn-dk/dailylah/tar.gz/refs/heads/data"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${DATA_TARBALL:-}" ]; then
  # Tests: a tarball on disk instead of the download.
  cp "$DATA_TARBALL" "$tmp/data.tgz"
else
  code=$(curl --silent --show-error --location --max-time 120 \
    --output "$tmp/data.tgz" --write-out '%{http_code}' "$url") || code=000
  if [ "$code" != 200 ]; then
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
  [ -d "$src/$dir" ] && [ ! -L "$src/$dir" ] || return 0
  count=$(find "$src/$dir" -maxdepth 1 -type f -name "*.$ext" | wc -l)
  [ "$count" -gt 0 ] || return 0
  mkdir -p "$dir"
  find "$dir" -maxdepth 1 -type f -name "*.$ext" -delete
  # -type f: plain files only, never a link to something else.
  # `+`: a failed copy fails find, and so the build. (sh -c instead of GNU's `cp -t`.)
  find "$src/$dir" -maxdepth 1 -type f -name "*.$ext" -exec sh -c 'cp "$@" "$0"/' "$dir" {} +
  echo "$dir: $count .$ext files from the data branch"
}

if [ -L "$tmp/tree/web" ] || [ -L "$src/data" ] \
  || [ ! -f "$src/data/manifest.json" ] || [ -L "$src/data/manifest.json" ]; then
  echo "The data branch has no web/data/manifest.json."
  exit 1
fi
take data json
take where-to-live-towns html
if [ -f "$src/sitemap.xml" ] && [ ! -L "$src/sitemap.xml" ]; then
  # Take it only if every line is one of the lines main's generator writes: the two header
  # lines, one <url> line per page of this site, the closing line. Whole lines, so nothing can
  # hide in a tag spread over several lines, a comment, an entity or another namespace.
  # Taken only when grep answers "no other line" (1): any other answer, an error included,
  # keeps main's. It must also be a whole sitemap: not empty, with its opening and closing line.
  # -a: a NUL is a byte like any other (without it grep would take it for a line end).
  lines=0
  LC_ALL=C grep -avqxE \
    '<\?xml version="1\.0" encoding="UTF-8"\?>|<urlset xmlns="http://www\.sitemaps\.org/schemas/sitemap/0\.9">|  <url><loc>https://dailylah\.sg/[A-Za-z0-9/_-]*</loc>(<lastmod>[0-9]{4}-[0-9]{2}-[0-9]{2}</lastmod>)?</url>|</urlset>' \
    "$src/sitemap.xml" || lines=$?
  if [ "$lines" -eq 1 ] && [ -s "$src/sitemap.xml" ] \
    && LC_ALL=C grep -aqxF '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' "$src/sitemap.xml" \
    && LC_ALL=C grep -aqxF '</urlset>' "$src/sitemap.xml"; then
    cp "$src/sitemap.xml" sitemap.xml
    echo "sitemap.xml from the data branch"
  else
    echo "The data branch's sitemap.xml is not a plain list of dailylah.sg URLs: keeping main's."
  fi
fi
[ -s data/manifest.json ] || { echo "data/manifest.json is empty after the overlay."; exit 1; }
