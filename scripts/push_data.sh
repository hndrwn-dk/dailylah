#!/usr/bin/env bash
# Pushes a data update with the deploy key (docs/DEPLOY.md, "Data branch"). Used by the push jobs
# of data.yml and where-to-live.yml, which run in environment `data-push` and get the patch from
# the build job as an artifact, so the key never shares a job with pip or the build's
# third-party code.
#
# Usage: DATA_PUSH_SSH_KEY=<private key> [VERCEL_DEPLOY_HOOK=<url>] scripts/push_data.sh \
#          [--generate "<command>" --generated <path>...] <patch file | -> "<commit message>" \
#          <allowed path>...
#        scripts/push_data.sh --baseline
#
# Where the published data lives is one word in web/data-source.txt on main, read from main
# itself (so only a merged pull request changes it):
#   main  (also when the file is missing) The update is pushed to main, as it always was, and
#         Vercel deploys on that push. The branch `data` gets a copy of the data files, so it is
#         ready for the switch; it is written only, never read.
#   data  The update is pushed to the branch `data` and never to main (the main ruleset then
#         needs no bypass). Each try starts from the newest main for the code and lays the newest
#         data branch over it. Then the Vercel deploy hook starts a deployment, whose build step
#         (web/build.sh) lays the data branch over main. The hook is required in this mode.
# The data branch holds only the files in BRANCH_PATHS below, at the paths they have on main.
# Files in HAND_KEPT are written by people on main: main's copy always wins, and the next
# update carries it to the data branch.
# --baseline (the build jobs, no key): with source `data`, lay the data branch over the checkout
# and commit it locally, so the build starts from the published data and its patch is a diff
# against it. With source `main` there is nothing to do.
# The patch is `git diff --cached --binary` of the build job against that baseline. `-` instead of
# a patch file means no data change: only the --generate command runs (a change to main's page
# generator must reach the published pages too).
# The build job runs third-party code, so the patch is not trusted: every path it touches must be
# an allowed path, only regular, non-executable files may be added, changed or deleted, and every
# `*.json` file it leaves must parse as a JSON object or array.
# Allowed path forms: `dir/*.ext` (files with that extension directly in dir, not in subfolders),
# `dir/` (everything under dir) and anything else for exactly that one file. The workflows allow
# only JSON files in the patch, so the build job cannot add scripts or pages the site would serve.
# --generate runs <command> (with bash, from the repository root) after the patch is applied, so it
# is main's own code; it may write only the --generated paths (same forms), which are staged from
# its output. Generated paths are never accepted from the patch.
set -euo pipefail

DATA_BRANCH=data
# Everything the data branch may hold. With source `data`, main's files at these paths are only
# the copy the tests read; the published ones are on the data branch.
BRANCH_PATHS=(
  'web/data/*.json'
  'web/where-to-live-towns/*.html'
  web/sitemap.xml
  # The builds' own caches and report. Not backend/data/where_to_live_points.json: that one is
  # written by hand and belongs to main.
  backend/data/geocode.json
  backend/data/where_to_live_routes.json
  backend/data/build_report.json
)
# Written by hand on main (web/data/README.md); the builds only keep them and list them.
HAND_KEPT=(web/data/school_holidays.json)

baseline=""
generate=""
generated=()
while [ $# -gt 0 ]; do
  case $1 in
    --baseline) baseline=1; shift ;;
    --generate) generate=$2; shift 2 ;;
    --generated) generated+=("$2"); shift 2 ;;
    *) break ;;
  esac
done
if [ -z "$baseline" ]; then
  patch=$1
  [ "$patch" = - ] || patch=$(realpath "$patch")
  message=$2
  shift 2
  allowed=("$@")
  if [ "${#allowed[@]}" -eq 0 ]; then
    echo "::error::No allowed paths given."
    exit 1
  fi
  if [ -n "$generate" ] && [ "${#generated[@]}" -eq 0 ]; then
    echo "::error::--generate needs at least one --generated path."
    exit 1
  fi
fi

# Succeeds if $1 matches one of the paths that follow it.
matches() {
  local path=$1 entry dir ext rest
  shift
  for entry in "$@"; do
    if [[ "$entry" == */\*.* ]]; then
      dir=${entry%/*}/
      ext=.${entry##*.}
      rest=${path#"$dir"}
      [[ "$path" == "$dir"?* && "$rest" != */* && "$rest" == ?*"$ext" ]] && return 0
    elif [[ "$entry" == */ ]]; then
      [[ "$path" == "$entry"?* ]] && return 0
    else
      [[ "$path" == "$entry" ]] && return 0
    fi
  done
  return 1
}

# The git pathspec for one path form (`dir/*.ext`, `dir/` or one file).
pathspec() {
  if [[ "$1" == */\*.* ]]; then
    printf ':(glob)%s' "$1"
  elif [[ "$1" == */ ]]; then
    printf ':(glob)%s**' "$1"
  else
    printf ':(literal)%s' "$1"
  fi
}

# Lays the newest data branch of remote $1 over the checkout (index and files) and commits that
# locally as the baseline. Sets data_tip to the branch's commit, or to "" when there is no data
# branch yet (the baseline is then main's own copy). The branch may hold only BRANCH_PATHS as
# plain files: anything else stops here, so it can never replace code that runs later.
overlay_data() {
  local remote=$1 meta path mode kind entry specs=()
  fetch_data_tip "$remote" || return 1
  if [ -n "$data_tip" ]; then
    while IFS= read -r -d '' meta; do
      path=${meta#*$'\t'}
      read -r mode kind _ <<< "${meta%%$'\t'*}"
      if [ "$mode" != 100644 ] || [ "$kind" != blob ] || ! matches "$path" "${BRANCH_PATHS[@]}"; then
        echo "::error::The $DATA_BRANCH branch holds something it may not: $path ($mode $kind)"
        exit 1
      fi
    done < <(git ls-tree -r -z "$data_tip")
    for entry in "${BRANCH_PATHS[@]}"; do
      specs+=("$(pathspec "$entry")")
    done
    # Exactly the branch's files: a file it no longer has goes, also when main still has a copy.
    git rm -r --quiet --ignore-unmatch -- "${specs[@]}" || return 1
    git checkout --quiet "$data_tip" -- . || return 1
    # Files people write on main: main's copy, not the branch's older one.
    for entry in "${HAND_KEPT[@]}"; do
      if git cat-file -e "HEAD:$entry" 2>/dev/null; then
        git checkout --quiet HEAD -- "$entry" || return 1
      fi
    done
  else
    echo "No $DATA_BRANCH branch yet: starting from the copy on main."
  fi
  git commit --quiet --allow-empty -m "Data baseline" || return 1
}

# Sets data_tip to the commit of the data branch on remote $1, or to "" when it does not exist.
# Full ref names: a tag called `data` or `main` must never be taken for the branch.
fetch_data_tip() {
  local remote=$1 listed line want=""
  data_tip=""
  # ls-remote and fetch match a name by its end, so `refs/heads/data` would also find a branch
  # called `refs/heads/refs/heads/data`: only the line with exactly this ref counts.
  listed=$(git ls-remote "$remote" "refs/heads/$DATA_BRANCH" 2>/dev/null) || return 1
  while IFS= read -r line; do
    if [ "${line#*$'\t'}" = "refs/heads/$DATA_BRANCH" ]; then
      want=${line%%$'\t'*}
    fi
  done <<< "$listed"
  if [ -z "$want" ] && [ -n "$listed" ]; then
    # git would also push to such a look-alike when the real branch is missing.
    echo "::error::A branch whose name only ends in refs/heads/$DATA_BRANCH exists (${listed#*$'\t'}). Delete it: it is not the $DATA_BRANCH branch."
    return 1
  fi
  [ -n "$want" ] || return 0
  git fetch --quiet --depth 1 "$remote" "refs/heads/$DATA_BRANCH" || return 1
  [ "$(git rev-parse FETCH_HEAD)" = "$want" ] || return 1
  data_tip=$want
}

# Prints `main` or `data`: where the published data lives (web/data-source.txt of the checkout).
data_source() {
  local word=main
  if [ -f web/data-source.txt ]; then
    word=$(tr -d '[:space:]' < web/data-source.txt)
  fi
  if [ "$word" != main ] && [ "$word" != data ]; then
    echo "::error::web/data-source.txt must say main or data." >&2
    exit 1
  fi
  printf '%s' "$word"
}

# Prints the tree with only the BRANCH_PATHS files of the index: what the data branch gets.
data_tree() {
  local entry specs=() index="$dir/index"
  for entry in "${BRANCH_PATHS[@]}"; do
    specs+=("$(pathspec "$entry")")
  done
  rm -f "$index"
  git ls-files --stage -z -- "${specs[@]}" | GIT_INDEX_FILE="$index" git update-index -z --index-info
  GIT_INDEX_FILE="$index" git write-tree
}

# Tells Vercel to deploy the site again, so it serves the data just pushed. The hook can do
# nothing else. Its URL is a secret: no curl output is shown.
redeploy() {
  if [ -z "${VERCEL_DEPLOY_HOOK:-}" ]; then
    echo "::error::VERCEL_DEPLOY_HOOK is not set in environment data-push: nothing would publish the $DATA_BRANCH branch (docs/DEPLOY.md, Data branch)."
    exit 1
  fi
  if ! curl --fail --silent --max-time 30 --output /dev/null -X POST "$VERCEL_DEPLOY_HOOK"; then
    echo "::error::The data is on the $DATA_BRANCH branch, but Vercel did not take the deploy hook: the site still serves the old data. Re-run this job (it will only call the hook), or redeploy in Vercel."
    exit 1
  fi
  echo "Asked Vercel to deploy the site."
}

if [ -n "$baseline" ]; then
  source=$(data_source)
  if [ "$source" = main ]; then
    echo "Baseline: main (web/data-source.txt says main)"
    exit 0
  fi
  git config user.name "dailylah-bot"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  # No key here: the repository is public, so the build job reads the branch like anyone can.
  if ! overlay_data "https://github.com/${GITHUB_REPOSITORY:?}.git"; then
    echo "::error::Could not read the $DATA_BRANCH branch."
    exit 1
  fi
  echo "Baseline: $DATA_BRANCH branch ${data_tip:-(none yet, so main)}"
  exit 0
fi

# Fails unless $1 is one of the allowed paths (the patch may change only these).
check_path() {
  matches "$1" "${allowed[@]}" && return 0
  echo "::error::The data update touches a path it may not change: $1"
  exit 1
}

# Checks the patch's paths before anything is written to the working tree.
check_patch_paths() {
  local stats path
  [ "$patch" != - ] || return 0
  while IFS= read -r -d '' stats; do
    path=${stats#*$'\t'}
    path=${path#*$'\t'}
    if [ -z "$path" ]; then
      # A rename or copy: source and destination follow as separate fields.
      IFS= read -r -d '' path
      check_path "$path"
      IFS= read -r -d '' path
    fi
    check_path "$path"
  done < <(git apply --numstat -z "$patch")
}

# Checks what is staged for the commit: allowed or generated paths, regular files with mode
# 100644 only (no symlink, submodule, executable bit or mode change), JSON that parses.
check_staged() {
  local meta path src dst
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    if ! matches "$path" ${generated[@]+"${generated[@]}"}; then
      check_path "$path"
    fi
    read -r src dst _ <<< "${meta#:}"
    if [[ "$src" != 100644 && "$src" != 000000 ]] || [[ "$dst" != 100644 && "$dst" != 000000 ]]; then
      echo "::error::The data update changes a file type or mode: $path ($src -> $dst)"
      exit 1
    fi
    if [[ "$path" == *.json && "$dst" != 000000 ]] && ! check_json "$path"; then
      echo "::error::The data update has a JSON file that is not a JSON object or array: $path"
      exit 1
    fi
  done < <(git diff --cached --raw --no-renames -z HEAD)
}

# Succeeds if the staged file $1 parses as a JSON object or array (the runner's python3, stdlib).
check_json() {
  git show ":$1" | python3 -E -s -c '
import json, sys
sys.exit(0 if isinstance(json.load(sys.stdin), (dict, list)) else 1)' 2>/dev/null
}

# Runs the --generate command (main's own code, on main with the patched data) and stages what
# it wrote at the generated paths.
run_generate() {
  local entry spec specs=()
  [ -n "$generate" ] || return 0
  # The command never sees the key or the deploy hook: not in its environment, and the key is
  # not on disk while it runs.
  rm -f "$dir/key"
  env -u DATA_PUSH_SSH_KEY -u VERCEL_DEPLOY_HOOK bash -c "$generate"
  write_key
  for entry in "${generated[@]}"; do
    spec=$(pathspec "$entry")
    # Only pathspecs that match something: git add fails on one that matches nothing.
    if [ -n "$(git ls-files --cached --others --exclude-standard -- "$spec")" ]; then
      specs+=("$spec")
    fi
  done
  [ "${#specs[@]}" -eq 0 ] || git add -A -- "${specs[@]}"
}

check_patch_paths
if [ -n "${VERCEL_DEPLOY_HOOK:-}" ] \
  && [[ "$VERCEL_DEPLOY_HOOK" != https://api.vercel.com/v1/integrations/deploy/* ]]; then
  echo "::error::VERCEL_DEPLOY_HOOK is not a Vercel deploy hook URL."
  exit 1
fi
if [ -z "${DATA_PUSH_SSH_KEY:-}" ]; then
  echo "::error::DATA_PUSH_SSH_KEY is not set. Add it to environment data-push (docs/DEPLOY.md, Rulesets)."
  exit 1
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
umask 077
write_key() { printf '%s\n' "$DATA_PUSH_SSH_KEY" > "$dir/key"; }
write_key
# GitHub's published SSH host key (docs.github.com, "GitHub's SSH key fingerprints"), pinned so the
# push never trusts a host key it has not seen before.
echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" \
  > "$dir/known_hosts"
# No user or system ssh config and no git config from the runner: only this key and host key.
export GIT_SSH_COMMAND="ssh -F /dev/null -i $dir/key -o IdentitiesOnly=yes -o BatchMode=yes \
-o UserKnownHostsFile=$dir/known_hosts -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
remote="git@github.com:${GITHUB_REPOSITORY:?}.git"
git config user.name "dailylah-bot"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Applies the patch to the index and working tree. Returns 1 when it is already in (nothing left
# to do); exits when it no longer fits.
apply_patch() {
  [ "$patch" != - ] || return 0
  git apply --index "$patch" && return 0
  if git apply --check --reverse "$patch" 2>/dev/null; then
    return 1
  fi
  echo "::error::The data update no longer applies (another change touched the same files)."
  exit 1
}

# Source `main`: gives the data branch a copy of the data files just pushed to main. It is made
# from main alone; what the branch holds is only its parent, never read.
mirror_to_data() {
  local tree
  tree=$(data_tree) || return 1
  fetch_data_tip "$remote" || return 1
  if [ -n "$data_tip" ] && [ "$tree" = "$(git rev-parse "$data_tip^{tree}")" ]; then
    return 0
  fi
  git push --quiet "$remote" \
    "$(git commit-tree "$tree" ${data_tip:+-p "$data_tip"} -m "$message"):refs/heads/$DATA_BRANCH"
}

for try in 1 2 3; do
  # main first, by its full ref name: its code (this run's generator) and its data-source.txt.
  if git fetch --quiet --depth 1 "$remote" refs/heads/main && git reset --quiet --hard FETCH_HEAD; then
    main_tip=$(git rev-parse HEAD)
    source=$(data_source)
    if [ "$source" = main ]; then
      # As before the data branch: the update goes to main, and Vercel deploys on that push.
      if [ "$patch" = - ]; then
        echo "Nothing to do: the pages are published from main."
        exit 0
      fi
      if ! apply_patch; then
        echo "Nothing left to push: main already has these changes."
        exit 0
      fi
      check_staged
      run_generate
      check_staged
      if git diff --cached --quiet; then
        echo "Nothing left to push: main already has these changes."
        exit 0
      fi
      commit=$(git commit-tree "$(git write-tree)" -p "$main_tip" -m "$message")
      if git push --quiet "$remote" "$commit:refs/heads/main"; then
        echo "Pushed to main: $message"
        mirror_to_data || echo "::warning::The copy on the $DATA_BRANCH branch was not updated (docs/DEPLOY.md, Data branch). The site is not affected."
        exit 0
      fi
    elif overlay_data "$remote"; then
      # HEAD is now main's code with the data branch's data, committed locally as the baseline.
      [ -n "${VERCEL_DEPLOY_HOOK:-}" ] || redeploy # fails: no hook, so nothing may be pushed
      applied=1
      apply_patch || applied=""
      if [ -n "$applied" ]; then
        check_staged
        run_generate
        check_staged
      fi
      tree=$(data_tree)
      if [ -n "$data_tip" ] && [ "$tree" = "$(git rev-parse "$data_tip^{tree}")" ]; then
        # Also after a run that pushed and then could not start the deployment.
        echo "Nothing left to push: the $DATA_BRANCH branch already has these changes."
        redeploy
        exit 0
      fi
      # A commit with only the data files, on top of the branch (the first one has no parent).
      commit=$(git commit-tree "$tree" ${data_tip:+-p "$data_tip"} -m "$message")
      if git push --quiet "$remote" "$commit:refs/heads/$DATA_BRANCH"; then
        echo "Pushed to $DATA_BRANCH: $message"
        redeploy
        exit 0
      fi
    fi
  fi
  echo "::warning::Push try $try failed; trying again."
  sleep 10
done
exit 1
