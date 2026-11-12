#!/usr/bin/env bash
# Pushes a data update to the branch `data` with the deploy key (docs/DEPLOY.md, "Data branch").
# Nothing is pushed to main: the main ruleset has no bypass, and the website's build step
# (web/build.sh) lays the data branch over main at every deploy. Used by the push jobs of data.yml
# and where-to-live.yml, which run in environment `data-push` and get the patch from the build
# job as an artifact, so the key never shares a job with pip or the build's third-party code.
#
# Usage: DATA_PUSH_SSH_KEY=<private key> [VERCEL_DEPLOY_HOOK=<url>] scripts/push_data.sh \
#          [--generate "<command>" --generated <path>...] <patch file> "<commit message>" \
#          <allowed path>...
#        scripts/push_data.sh --baseline
# The data branch holds only the files in BRANCH_PATHS below, at the paths they have on main.
# Each try starts from the newest main (the code), lays the newest data branch over it, applies
# the patch and pushes a commit with only those files to `data`; up to 3 tries. Then the deploy
# hook, if given, tells Vercel to deploy the site again.
# Moving over: while VERCEL_DEPLOY_HOOK is not set, nothing would publish what is on the data
# branch, so the same update is also pushed to main as before (that needs the deploy key in the
# main ruleset's bypass list). With the hook set, main is never pushed to.
# --baseline (the build jobs, no key): lay the data branch over the checkout and commit it
# locally, so the build starts from the published data and its patch is a diff against it.
# The patch is `git diff --cached --binary` of the build job against that baseline.
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
# Everything the data branch may hold. A file of main at one of these paths is only the copy the
# tests read; the published one is on the data branch.
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
  patch=$(realpath "$1")
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
  local remote=$1 rc=0 meta path mode kind entry specs=()
  data_tip=""
  git ls-remote --exit-code --heads "$remote" "$DATA_BRANCH" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "No $DATA_BRANCH branch yet: starting from the copy on main."
  elif [ "$rc" -ne 0 ]; then
    return 1
  else
    git fetch --quiet --depth 1 "$remote" "$DATA_BRANCH" || return 1
    data_tip=$(git rev-parse FETCH_HEAD)
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
    git rm -r --quiet --ignore-unmatch -- "${specs[@]}"
    git checkout --quiet "$data_tip" -- .
  fi
  git commit --quiet --allow-empty -m "Data baseline"
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
  if ! curl --fail --silent --max-time 30 --output /dev/null -X POST "$VERCEL_DEPLOY_HOOK"; then
    echo "::error::The data was pushed, but Vercel did not take the deploy hook: the site still serves the old data. Run the workflow again or redeploy in Vercel."
    exit 1
  fi
  echo "Asked Vercel to deploy the site."
}

if [ -n "$baseline" ]; then
  git config user.name "dailylah-bot"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  # No key here: the repository is public, so the build job reads the branch like anyone can.
  if ! overlay_data "https://github.com/${GITHUB_REPOSITORY:?}.git"; then
    echo "::error::Could not read the $DATA_BRANCH branch."
    exit 1
  fi
  echo "Baseline: ${data_tip:-main (no $DATA_BRANCH branch yet)}"
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
# Before anything is pushed: a hook that cannot work must not leave pushed data unpublished.
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

for try in 1 2 3; do
  # main for the code (the generator below is main's own), the data branch for the data.
  if git fetch --quiet --depth 1 "$remote" main && git reset --quiet --hard FETCH_HEAD \
    && main_tip=$(git rev-parse HEAD) && overlay_data "$remote"; then
    if ! git apply --index "$patch"; then
      if git apply --check --reverse "$patch" 2>/dev/null; then
        echo "Nothing left to push: the $DATA_BRANCH branch already has these changes."
        exit 0
      fi
      echo "::error::The data update no longer applies to the $DATA_BRANCH branch (another change touched the same files)."
      exit 1
    fi
    check_staged
    run_generate
    check_staged
    tree=$(data_tree)
    if [ -n "$data_tip" ] && [ "$tree" = "$(git rev-parse "$data_tip^{tree}")" ]; then
      echo "Nothing left to push: the $DATA_BRANCH branch already has these changes."
      exit 0
    fi
    # A commit with only the data files, on top of the branch (the first one has no parent).
    commit=$(git commit-tree "$tree" ${data_tip:+-p "$data_tip"} -m "$message")
    if git push --quiet "$remote" "$commit:refs/heads/$DATA_BRANCH"; then
      echo "Pushed to $DATA_BRANCH: $message"
      if [ -n "${VERCEL_DEPLOY_HOOK:-}" ]; then
        redeploy
        exit 0
      fi
      # Moving over (see the top of this file): no hook yet, so main gets the update too and
      # Vercel deploys on that push, as before.
      echo "::warning::VERCEL_DEPLOY_HOOK is not set: also pushing to main so the site is deployed. Set the hook, then take the deploy key out of the main ruleset's bypass list (docs/DEPLOY.md, Data branch)."
      commit=$(git commit-tree "$(git write-tree)" -p "$main_tip" -m "$message")
      if git push --quiet "$remote" "$commit:refs/heads/main"; then
        echo "Pushed to main: $message"
        exit 0
      fi
      echo "::error::The data is on the $DATA_BRANCH branch, but main refused the push and no deploy hook is set: the site still serves the old data. Set VERCEL_DEPLOY_HOOK in environment data-push (docs/DEPLOY.md, Data branch)."
      exit 1
    fi
  fi
  echo "::warning::Push try $try failed; trying again."
  sleep 10
done
exit 1
