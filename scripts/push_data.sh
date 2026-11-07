#!/usr/bin/env bash
# Pushes a data update to main with the deploy key that the main ruleset lets bypass its rules
# (docs/HANDOFF.md, "Rulesets", route B). Used by the push jobs of data.yml and where-to-live.yml,
# which run in environment `data-push` and get the patch from the build job as an artifact, so
# the key never shares a job with pip or the build's third-party code.
#
# Usage: DATA_PUSH_SSH_KEY=<private key> scripts/push_data.sh <patch file> "<commit message>" \
#          <allowed path>...
# The patch is `git diff --cached --binary` of the build job. It is applied to the newest main
# (which may have moved while the build ran) and pushed; up to 3 tries.
# The build job runs third-party code, so the patch is not trusted: every path it touches must be
# an allowed path (an entry ending in / allows everything under that folder, any other entry
# allows that one file), and only regular, non-executable files may be added, changed or deleted.
set -euo pipefail

patch=$(realpath "$1")
message=$2
shift 2
allowed=("$@")
if [ "${#allowed[@]}" -eq 0 ]; then
  echo "::error::No allowed paths given."
  exit 1
fi

# Fails unless $1 is one of the allowed paths.
check_path() {
  local entry
  for entry in "${allowed[@]}"; do
    if [[ "$entry" == */ ]]; then
      [[ "$1" == "$entry"?* ]] && return 0
    else
      [[ "$1" == "$entry" ]] && return 0
    fi
  done
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

# Checks what the applied patch staged: allowed paths, regular files with mode 100644 only
# (no symlink, submodule, executable bit or mode change).
check_staged() {
  local meta path src dst
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    check_path "$path"
    read -r src dst _ <<< "${meta#:}"
    if [[ "$src" != 100644 && "$src" != 000000 ]] || [[ "$dst" != 100644 && "$dst" != 000000 ]]; then
      echo "::error::The data update changes a file type or mode: $path ($src -> $dst)"
      exit 1
    fi
  done < <(git diff --cached --raw --no-renames -z HEAD)
}

check_patch_paths
if [ -z "${DATA_PUSH_SSH_KEY:-}" ]; then
  echo "::error::DATA_PUSH_SSH_KEY is not set. Add it to environment data-push (docs/HANDOFF.md, Rulesets)."
  exit 1
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
umask 077
printf '%s\n' "$DATA_PUSH_SSH_KEY" > "$dir/key"
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
