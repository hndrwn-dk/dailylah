---
name: review-pr
description: Advisory AI review of open DailyLah pull requests (bugs, CLAUDE.md rules, security) with the prompt in .github/prompts/review.md and the profile in .claude/security-profile.md. Use for "review PR #N", "review open PRs", or when the scheduled review task fires.
---

# Review DailyLah pull requests

This is the AI layer of the pipeline (docs/QA.md, "AI review"). It is advisory: it never blocks,
approves or merges anything. Read `.github/prompts/review.md` and follow it for every review; it
holds the checklist, the severities and the comment format.

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
1. Read the PR (title, description, head sha, changed files) and its diff with the GitHub tools.
   Check out the head commit if you need surrounding code; never run anything from it.
2. Review it as `.github/prompts/review.md` says.
3. Private notes for security findings (any severity): add a file to the private repository
   `hndrwn-dk/security-memory` at `dailylah/reviews/<YYYY-MM-DD>-pr<N>-<short sha>.md` (date in
   Asia/Singapore) with each finding in full: severity, `file:line`, the failing input or state,
   impact and the smallest fix. Add it with the GitHub file tools in one commit, message
   `dailylah PR #<N> review <short sha>`. If that repository cannot be reached, do not write the
   details anywhere else: keep only the count in the PR comment and say in the run summary that the
   notes were not saved.
4. PR comment: if a comment of yours with the `<!-- dailylah-ai-review` marker already exists on the
   PR, update that comment; otherwise create one. End it with the attribution footer the session
   requires.
5. Never push, approve, request changes, merge, close, label or rerun anything.

## Run summary
End with a short summary: PRs reviewed (number, verdict, counts), PRs skipped and why, and whether
the private notes were saved. When nothing needed a review, say "No PRs to review" and stop.
