---
name: review-pr
description: Advisory AI review of open DailyLah pull requests, on top of the owner's claude-toolkit security SOP (hndrwn-dk/security-memory). Bugs and CLAUDE.md rules go in one PR comment; security findings go through the toolkit's security-reviewer and its private memory format. Use for "review PR #N", "review open PRs", "security gate for PR #N", or when the scheduled review task fires.
---

# Review DailyLah pull requests

This is the AI layer of the pipeline (docs/QA.md, "AI review"). It is advisory: it never blocks,
approves or merges anything. Two sources of rules:

- `.github/prompts/review.md` (this repo): the PR comment, bugs and CLAUDE.md rules.
- The owner's claude-toolkit in the private `hndrwn-dk/security-memory`
  (`claude-toolkit/global/`): `CLAUDE.md` (the security SOP and disclosure rules),
  `agents/security-reviewer.md`, `commands/security-gate.md`, `commands/vuln-scan.md` (memory
  format) and `commands/find-critical-bugs.md`. Where they differ, the toolkit wins on security.

## Setup
1. Clone or pull `https://github.com/hndrwn-dk/security-memory` (private) into a directory
   outside this repo, for example `../security-memory`. If it cannot be reached, still review, but
   write security details nowhere: the PR shows only the count, and the run summary says the
   private notes were not saved.
2. Read `claude-toolkit/global/CLAUDE.md`, `agents/security-reviewer.md` and the memory section of
   `commands/vuln-scan.md` from that clone, and `.claude/security-profile.md` from this repo.
   Do not install the toolkit into `~/.claude`; reading it is enough.
3. Visibility: this repo is PUBLIC.

## Which pull requests
- Asked for one PR ("review PR #N"): review that one, even if it was reviewed before.
- Run by the scheduled task, or asked to review open PRs: every open PR of hndrwn-dk/dailylah that
  - changes `app/`, `backend/`, `contracts/`, `web/` (not `web/data/`), `scripts/`, `.github/` or
    `.claude/`,
  - is not a draft, does not come from a fork, and is not authored by `dailylah-bot`,
    `dependabot[bot]` or another bot,
  - has no review comment yet for its current head commit: look for an existing comment that starts
    with `<!-- dailylah-ai-review sha=<head sha> -->`. If one exists for that sha, skip the PR.
- More than 5 PRs waiting: review the 5 most recently updated and say so in the run summary.

## Steps per pull request
1. Fetch the PR head into a worktree (`git fetch origin pull/<N>/head`); never run code from it.
2. Bugs and rules: review the diff against `origin/main` as `.github/prompts/review.md` says.
3. Security: dispatch a fresh subagent (no conversation history, no opinion of yours) with the full
   text of `agents/security-reviewer.md` as its instructions, plus the repo path, base
   `origin/main`, head sha and the profile. It returns findings JSON. Keep medium, high and
   critical; low findings are not reported in this public repo.
4. Private memory, for medium+ security findings only, as `commands/vuln-scan.md` says:
   - Skip findings already in `dailylah/dailylah---flagged-vulnerabilities*.json` (same title or
     same location and cause).
   - Write `dailylah/reports/<YYYY-MM-DD>-pr<N>-review.md` (date in Asia/Singapore) with each new
     finding in full: attacker, input, path with file:line, impact, fix.
   - Append new findings to the JSON family with Python (`json.load` / `json.dump(indent=4)`):
     `title`, `severity`, `location`, `status: "active"`, `commit_hash` (PR head), `detected_at`
     (ISO 8601, +08:00), `reported_link` (the report path).
   - Commit and push the memory repo: `dailylah: PR #<N> review <short sha>`.
5. PR comment: if a comment of yours with the `<!-- dailylah-ai-review` marker exists on the PR,
   update it; otherwise create one. Security findings appear only as a count. End it with the
   attribution footer the session requires.
6. Never push to the PR, approve, request changes, merge, close, label or rerun anything.

## Security gate before a merge (on request)
When asked for the security gate on a PR before it is merged, follow
`commands/security-gate.md` from the toolkit: fresh reviewer, the profile's test commands (the app
side is covered by the PR's green `app` workflow, since Flutter is not installed in cloud sessions),
and at most two fix rounds with a separate fixer subagent whose instructions are
`agents/security-fixer.md`. On a pass, post the neutral comment
`Security gate: pass at <short sha>.` on the PR. Any later commit needs a new gate.

## Scheduled run extras
After the PR reviews, run `commands/find-critical-bugs.md` from the toolkit on `main` for the
profile's window (7 days), with its memory file `dailylah/bugs.md` and its disclosure rule for this
public repo.

## Run summary
End with a short summary: PRs reviewed (number, verdict, counts), PRs skipped and why, whether
the private notes were saved, and the critical-bug scan result. When nothing needed a review and no
critical bug was found, say so in one line.
