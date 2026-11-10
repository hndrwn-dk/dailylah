#!/usr/bin/env bash
# Pushes a data update to main with the deploy key that the main ruleset lets bypass its rules
# (docs/DEPLOY.md, "Rulesets"). Used by the push jobs of data.yml and where-to-live.yml,
# which run in environment `data-push` and get the patch from the build job as an artifact, so
# the key never shares a job with pip or the build's third-party code.
#
# Usage: DATA_PUSH_SSH_KEY=<private key> scripts/push_data.sh \
#          [--generate "<command>" --generated <path>...] <patch file> "<commit message>" \
#          <allowed path>...
# The patch is `git diff --cached --binary` of the build job. It is applied to the newest main
# (which may have moved while the build ran) and pushed; up to 3 tries.
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

generate=""
generated=()
while [ $# -gt 0 ]; do
  case $1 in
    --generate) generate=$2; shift 2 ;;
    --generated) generated+=("$2"); shift 2 ;;
    *) break ;;
  esac
done
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

# Runs the --generate command on the patched main and stages what it wrote at the generated paths.
run_generate() {
  local entry spec specs=()
  [ -n "$generate" ] || return 0
  # The command never sees the key: not in its environment, not on disk while it runs.
  rm -f "$dir/key"
  env -u DATA_PUSH_SSH_KEY bash -c "$generate"
  write_key
  for entry in "${generated[@]}"; do
    if [[ "$entry" == */\*.* ]]; then
      spec=":(glob)$entry"
    elif [[ "$entry" == */ ]]; then
      spec=":(glob)$entry**"
    else
      spec=":(literal)$entry"
    fi
    # Only pathspecs that match something: git add fails on one that matches nothing.
    if [ -n "$(git ls-files --cached --others --exclude-standard -- "$spec")" ]; then
      specs+=("$spec")
    fi
  done
  [ "${#specs[@]}" -eq 0 ] || git add -A -- "${specs[@]}"
}

check_patch_paths
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
  if git fetch --quiet --depth 1 "$remote" main && git reset --quiet --hard FETCH_HEAD; then
    if ! git apply --index "$patch"; then
      if git apply --check --reverse "$patch" 2>/dev/null; then
        echo "Nothing left to push: main already has these changes."
        exit 0
      fi
      echo "::error::The data update no longer applies to main (another change touched the same files)."
      exit 1
    fi
    check_staged
    run_generate
    check_staged
    if git diff --cached --quiet; then
      echo "Nothing left to push: main already has these changes."
      exit 0
    fi
    git commit --quiet -m "$message"
    if git push --quiet "$remote" HEAD:main; then
      echo "Pushed: $message"
      exit 0
    fi
  fi
  echo "::warning::Push try $try failed; trying again."
  sleep 10
done
exit 1
