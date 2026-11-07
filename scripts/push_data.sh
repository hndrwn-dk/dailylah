#!/usr/bin/env bash
# Pushes a data update to main with the deploy key that the main ruleset lets bypass its rules
# (docs/HANDOFF.md, "Rulesets", route B). Used by the push jobs of data.yml and where-to-live.yml,
# which run in environment `data-push` and get the patch from the build job as an artifact, so
# the key never shares a job with pip or the build's third-party code.
#
# Usage: DATA_PUSH_SSH_KEY=<private key> scripts/push_data.sh <patch file> "<commit message>"
# The patch is `git diff --cached --binary` of the build job. It is applied to the newest main
# (which may have moved while the build ran) and pushed; up to 3 tries.
set -euo pipefail

patch=$(realpath "$1")
message=$2
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
