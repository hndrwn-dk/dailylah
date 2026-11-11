#!/usr/bin/env python3
"""Move a tested release to Google Play production, or change its staged rollout.

Used by .github/workflows/promote.yml (docs/QA.md "Production release from the phone").
Nothing is built or uploaded here: `promote` takes the versionCode that closed testing
(`alpha`) already holds and puts it on `production` with the Play Developer API
(edits: tracks.update, then commit).

  promote   the alpha release of <version> goes to production at <rollout> percent
  rollout   raise the fraction of the staged production release (100 completes it)
  halt      stop the staged production release
  resume    continue a halted production release at the fraction it had

Python standard library only, plus the runner's `openssl` to sign the service account's
token request: the job that holds the production Play key installs nothing from pip.
The key is read from the environment variable PLAY_SERVICE_ACCOUNT_JSON and reaches
openssl through stdin; it is never written to disk or printed.
"""

from __future__ import annotations

import argparse
import base64
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PACKAGE = "com.tursinalabs.dailylah"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
# Fixed, not read from the key file: the signed token request goes to Google only.
TOKEN_URL = "https://oauth2.googleapis.com/token"  # noqa: S105 - a URL, not a secret
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
ACTIONS = ("promote", "rollout", "halt", "resume")
PERCENTS = (10, 20, 50, 100)
NOTES_MAX = 500  # Google Play's limit for release notes, per language
TIMEOUT = 30


class PromoteError(Exception):
    """A refusal or failure with a message that is safe to print (no secrets)."""


class CommitError(PromoteError):
    """Failed at or after the commit: production may have changed."""


# --- Google Play Developer API --------------------------------------------------------


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a redirect: the bearer token must not travel to another host."""

    def redirect_request(self, *args, **kwargs):
        return None


def _open(request: urllib.request.Request):
    opener = urllib.request.build_opener(_NoRedirect)
    return opener.open(request, timeout=TIMEOUT)


def _error_text(raw: bytes) -> str:
    """Google's own error message from a JSON error body, without the rest of the body."""
    try:
        err = json.loads(raw).get("error")
    except (ValueError, AttributeError):
        return "no details"
    if isinstance(err, dict):
        return str(err.get("message") or err.get("status") or "no details")
    return str(err or "no details")


def call(method: str, url: str, *, token: str = "", body=None, form=None, opener=_open) -> dict:
    """One HTTPS call. Errors name the method and path, never a header or the request body."""
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif form is not None:
        data = urllib.parse.urlencode(form).encode()
    elif method in ("POST", "PUT"):
        data = b""
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if not url.startswith("https://"):
        raise PromoteError("Refusing a non-HTTPS URL.")
    request = urllib.request.Request(url, data=data, method=method, headers=headers)  # noqa: S310
    where = f"{method} {urllib.parse.urlsplit(url).path}"
    try:
        with opener(request) as response:
            raw = response.read()
    except urllib.error.HTTPError as e:
        raise PromoteError(f"{where}: HTTP {e.code}: {_error_text(e.read())}") from None
    except (OSError, http.client.HTTPException) as e:
        # URLError and timeouts, and what urllib does not wrap: a reset or cut-off connection.
        reason = getattr(e, "reason", None) or e
        raise PromoteError(f"{where}: {type(e).__name__}: {reason}") from None
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except ValueError:
        raise PromoteError(f"{where}: the answer is not JSON.") from None


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def sign_rs256(message: bytes, private_key_pem: str) -> bytes:
    """RSA-SHA256 signature made by openssl. The key goes in through stdin only."""
    with tempfile.NamedTemporaryFile() as unsigned:  # the text to sign; not a secret
        unsigned.write(message)
        unsigned.flush()
        try:
            done = subprocess.run(  # noqa: S603 - fixed command, no shell
                ["openssl", "dgst", "-sha256", "-sign", "/dev/stdin", unsigned.name],  # noqa: S607
                input=private_key_pem.encode(),
                capture_output=True,
                check=False,
                timeout=TIMEOUT,
            )
        except (OSError, subprocess.SubprocessError):
            raise PromoteError("openssl could not be run to sign the token request.") from None
    if done.returncode != 0 or not done.stdout:
        # openssl's own output is not printed: keep anything about the key out of the log.
        raise PromoteError("openssl could not sign with the service account key.")
    return done.stdout


def check_account(account_json: str, testing_account: str, dry_run: bool = False) -> list[str]:
    """The production key must not be the key of the testing account. Returns warning lines.

    A setup guard, not the boundary: the boundary is that the testing account has no production
    right in Play Console. Without the variable only a dry run goes on, with a warning.

    The environment `play` (uploads to the testing tracks) asks nobody for approval. If the same
    service account were used here, that environment could release to production too. The
    repository variable PLAY_TESTING_ACCOUNT names the testing account's email, so this can check.
    """
    try:
        email = str(json.loads(account_json)["client_email"]).strip().lower()
    except (ValueError, KeyError, TypeError):
        email = ""  # token_request reports a bad key file
    testing = testing_account.strip().lower()
    if not testing:
        missing = (
            "Repository variable PLAY_TESTING_ACCOUNT is not set, so this run cannot check "
            "that the production key belongs to a service account of its own "
            "(docs/DEPLOY.md, Production releases from the phone)."
        )
        if not dry_run:
            raise PromoteError(f"{missing} Only a dry run works without it.")
        return [missing]
    if email and email == testing:
        raise PromoteError(
            "The key in environment play-production belongs to the testing service account "
            "(repository variable PLAY_TESTING_ACCOUNT). Production needs a service account of "
            "its own: docs/DEPLOY.md, Production releases from the phone."
        )
    return []


def token_request(account_json: str, now: int | None = None, signer=sign_rs256) -> dict:
    """The form to POST to TOKEN_URL: a signed, 10-minute request for the publisher scope."""
    try:
        account = json.loads(account_json)
        email = account["client_email"]
        key = account["private_key"]
        if account.get("type") != "service_account" or not email or not key:
            raise KeyError("type")
    except (ValueError, KeyError, TypeError):
        raise PromoteError(
            "Secret PLAY_SERVICE_ACCOUNT_JSON is not a service account key file "
            "(JSON with type, client_email and private_key)."
        ) from None
    issued = int(time.time()) if now is None else now
    header = {"alg": "RS256", "typ": "JWT"}
    if account.get("private_key_id"):
        header["kid"] = account["private_key_id"]
    claims = {
        "iss": email,
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": issued,
        "exp": issued + 600,
    }
    unsigned = ".".join(
        _b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, claims)
    )
    signature = signer(unsigned.encode(), key)
    return {
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": f"{unsigned}.{_b64url(signature)}",
    }


def access_token(account_json: str, opener=_open) -> str:
    answer = call("POST", TOKEN_URL, form=token_request(account_json), opener=opener)
    token = answer.get("access_token")
    if not token:
        raise PromoteError("Google gave no access token for the service account.")
    return token


class PlayApi:
    """The edit calls this script needs."""

    def __init__(self, token: str, package: str = PACKAGE, opener=_open):
        self._token = token
        self._base = f"{API}/{urllib.parse.quote(package, safe='')}/edits"
        self._opener = opener

    def _call(self, method: str, path: str = "", body=None) -> dict:
        return call(method, self._base + path, token=self._token, body=body, opener=self._opener)

    def create_edit(self) -> str:
        edit = self._call("POST").get("id")
        if not edit:
            raise PromoteError("Google Play opened no edit.")
        return str(edit)

    def get_track(self, edit: str, track: str) -> list[dict]:
        return list(self._call("GET", f"/{_seg(edit)}/tracks/{_seg(track)}").get("releases") or [])

    def update_track(self, edit: str, track: str, releases: list[dict]) -> None:
        body = {"track": track, "releases": releases}
        self._call("PUT", f"/{_seg(edit)}/tracks/{_seg(track)}", body=body)

    def validate_edit(self, edit: str) -> None:
        self._call("POST", f"/{_seg(edit)}:validate")

    def commit_edit(self, edit: str) -> None:
        self._call("POST", f"/{_seg(edit)}:commit")

    def delete_edit(self, edit: str) -> None:
        self._call("DELETE", f"/{_seg(edit)}")


def _seg(value: str) -> str:
    return urllib.parse.quote(str(value), safe="")


# --- Track state ----------------------------------------------------------------------


def codes(release: dict) -> list[int]:
    return [int(c) for c in release.get("versionCodes") or []]


def percent_of(release: dict) -> float | None:
    """Share of users a release reaches, in percent; None for a draft."""
    status = release.get("status")
    if status == "completed":
        return 100.0
    if status in ("inProgress", "halted") and release.get("userFraction") is not None:
        return round(float(release["userFraction"]) * 100, 4)
    return None


def describe(release: dict) -> str:
    share = percent_of(release)
    at = "" if share is None or release.get("status") == "completed" else f" at {share:g}%"
    code = ", ".join(str(c) for c in codes(release)) or "no versionCode"
    name = _cell(release.get("name") or "no name")
    return f"{code} ({name}, {_cell(release.get('status') or 'no status')}{at})"


def table(track: str, releases: list[dict]) -> list[str]:
    rows = [
        "| Track | versionCode | versionName | Status | Rollout |",
        "| --- | --- | --- | --- | --- |",
    ]
    for release in releases:
        share = percent_of(release)
        rows.append(
            "| {} | {} | {} | {} | {} |".format(
                track,
                ", ".join(str(c) for c in codes(release)) or "–",
                _cell(release.get("name") or "–"),
                _cell(release.get("status") or "–"),
                "–" if share is None else f"{share:g}%",
            )
        )
    if not releases:
        rows.append(f"| {track} | – | – | no release | – |")
    return rows


def _cell(text: str) -> str:
    """A value from Google Play as one plain Markdown table cell."""
    return re.sub(r"[^\w .()+-]", "?", str(text))[:60]


def _only(releases: list[dict], status: str) -> dict | None:
    found = [r for r in releases if r.get("status") == status]
    if len(found) > 1:
        raise PromoteError(
            f"Production has {len(found)} releases with status {status}; fix it in Play Console."
        )
    return found[0] if found else None


def _state(releases: list[dict]) -> str:
    return "; ".join(describe(r) for r in releases) or "no release"


def _staged(release: dict, status: str, percent: float) -> dict:
    """A copy of `release` with a new status and share of users (100 = completed)."""
    new = {k: v for k, v in release.items() if k != "userFraction"}
    if percent >= 100:
        new["status"] = "completed"
    else:
        new["status"] = status
        new["userFraction"] = percent / 100
    return new


# --- Plans: the releases to put on production, or a refusal -----------------------------


def read_notes(path: Path, language: str = "en-US") -> list[dict]:
    try:
        text = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        raise PromoteError(f"No readable release notes at {path.name}.") from None
    if not text:
        raise PromoteError("The release notes are empty.")
    if len(text) > NOTES_MAX:
        raise PromoteError(
            f"The release notes are {len(text)} characters; Google Play allows {NOTES_MAX}."
        )
    return [{"language": language, "text": text}]


def find_on_alpha(alpha: list[dict], version: str) -> dict:
    """The closed-testing release of versionName `version`.

    A release made through the API is named after its versionName ("2.4.0"); one made in
    Play Console is named "<versionCode> (<versionName>)". Both are accepted, nothing else.
    """
    matches = []
    for release in alpha:
        name = str(release.get("name") or "").strip()
        own = codes(release)
        if name == version or (len(own) == 1 and name == f"{own[0]} ({version})"):
            matches.append(release)
    if not matches:
        raise PromoteError(
            f"Version {version} is not on closed testing (alpha), which has: {_state(alpha)}. "
            "Promote only what testers have: release it to alpha first (a version bump on main "
            "with PLAY_PUSH_TRACK=alpha)."
        )
    if len(matches) > 1:
        raise PromoteError(
            f"Closed testing has {len(matches)} releases named {version}: {_state(matches)}. "
            "Clean this up in Play Console first."
        )
    release = matches[0]
    if len(codes(release)) != 1:
        raise PromoteError(f"The alpha release of {version} must hold exactly one versionCode.")
    if release.get("status") != "completed":
        raise PromoteError(
            f"The alpha release of {version} is {release.get('status')}, not completed: "
            f"{describe(release)}. Testers must have it before production does."
        )
    return release


def plan_promote(
    alpha: list[dict], production: list[dict], version: str, percent: int, notes: list[dict]
) -> tuple[list[dict], list[str]]:
    source = find_on_alpha(alpha, version)
    code = codes(source)[0]
    live = [c for release in production for c in codes(release)]
    if code in live:
        current = next(r for r in production if code in codes(r))
        raise PromoteError(
            f"versionCode {code} ({version}) is already on production: {describe(current)}. "
            "Use action rollout, halt or resume to change it."
        )
    if live and code < max(live):
        raise PromoteError(
            f"versionCode {code} ({version}) is older than production, which has "
            f"{_state(production)}. Google Play never goes back to a lower versionCode."
        )
    release = _staged(
        {"name": source.get("name") or version, "versionCodes": [str(code)], "releaseNotes": notes},
        "inProgress",
        percent,
    )
    plan = [f"Promote versionCode {code} ({version}) from alpha to production at {percent}%."]
    for old in production:
        if old.get("status") in ("inProgress", "halted"):
            plan.append(f"This replaces the unfinished staged release {describe(old)}.")
        elif old.get("status") == "draft":
            plan.append(f"This discards the production draft {describe(old)}.")
    if percent < 100:
        plan.append("Users outside the rollout keep the version they have.")
    return [release], plan


def plan_rollout(production: list[dict], percent: int) -> tuple[list[dict], list[str]]:
    release = _only(production, "inProgress")
    if release is None:
        halted = _only(production, "halted")
        hint = " Run action resume first." if halted else ""
        raise PromoteError(
            f"No staged rollout is in progress on production ({_state(production)}).{hint}"
        )
    now = percent_of(release) or 0.0
    if percent <= now:
        raise PromoteError(
            f"The staged release is already at {now:g}% ({describe(release)}); "
            f"rollout only raises it, and {percent}% is not higher. Use halt to stop it."
        )
    done = " (completed: every user gets it)" if percent >= 100 else ""
    return (
        [_staged(release, "inProgress", percent)],
        [f"Raise {describe(release)} from {now:g}% to {percent}%{done}."],
    )


def plan_halt(production: list[dict]) -> tuple[list[dict], list[str]]:
    release = _only(production, "inProgress")
    if release is None:
        raise PromoteError(
            f"No staged rollout is in progress on production ({_state(production)}); "
            "nothing to halt. A completed release cannot be halted here."
        )
    now = percent_of(release)
    if not now:
        raise PromoteError(f"The staged release has no fraction ({describe(release)}).")
    return (
        [_staged(release, "halted", now)],
        [
            f"Halt {describe(release)}: no new users get it. "
            "Users who already have it keep it; resume continues at the same fraction."
        ],
    )


def plan_resume(production: list[dict]) -> tuple[list[dict], list[str]]:
    release = _only(production, "halted")
    if release is None:
        raise PromoteError(
            f"No halted release on production ({_state(production)}); nothing to resume."
        )
    now = percent_of(release)
    if not now or now >= 100:
        raise PromoteError(
            f"The halted release has no staged fraction ({describe(release)}); "
            "resume it in Play Console."
        )
    return [_staged(release, "inProgress", now)], [f"Resume {describe(release)} at {now:g}%."]


# --- Run ------------------------------------------------------------------------------


def _same(wanted: dict, production: list[dict]) -> bool:
    for release in production:
        if codes(release) == codes(wanted):
            a, b = percent_of(release), percent_of(wanted)
            return (
                release.get("status") == wanted.get("status")
                and a is not None
                and b is not None
                and abs(a - b) < 1e-6
            )
    return False


def run(
    api,
    action: str,
    *,
    version: str = "",
    percent: int = 20,
    notes: list[dict] | None = None,
    dry_run: bool = False,
    out: list[str] | None = None,
) -> list[str]:
    """Read the tracks, plan, and (unless dry_run) commit. Returns the summary lines.

    `out` gets the same lines as they are made, so a caller still has them after an error.
    """
    out = [] if out is None else out
    title = f"Google Play production: {action}" + (" (dry run)" if dry_run else "")
    out += [f"## {title}", ""]
    edit = api.create_edit()
    committed = False
    try:
        production = api.get_track(edit, "production")
        out += ["### Before", ""]
        if action == "promote":
            alpha = api.get_track(edit, "alpha")
            out += table("alpha", alpha) + table("production", production)[2:]
            releases, plan = plan_promote(alpha, production, version, percent, notes or [])
        else:
            out += table("production", production)
            if action == "rollout":
                releases, plan = plan_rollout(production, percent)
            elif action == "halt":
                releases, plan = plan_halt(production)
            elif action == "resume":
                releases, plan = plan_resume(production)
            else:
                raise PromoteError(f"Unknown action {action}.")
        out += ["", "### Plan", ""] + [f"- {line}" for line in plan]
        api.update_track(edit, "production", releases)
        if dry_run:
            api.validate_edit(edit)
            out += [
                "",
                "### After (planned, not committed)",
                "",
                *table("production", releases),
                "",
                "Dry run: Google Play accepted the change in a scratch edit, and the edit was "
                "thrown away. Nothing changed for users.",
            ]
            return out
        try:
            api.commit_edit(edit)
        except PromoteError as e:
            raise CommitError(
                f"The commit did not go through: {e} If this was a timeout, run a dry run to "
                "see what production holds now."
            ) from None
        committed = True
    finally:
        if not committed:
            try:
                api.delete_edit(edit)
            except PromoteError:
                pass  # an uncommitted edit changes nothing and expires by itself
    # Read the track again in a fresh edit: the summary shows what Google Play now holds.
    check = None
    try:
        check = api.create_edit()
        after = api.get_track(check, "production")
    except PromoteError as e:
        raise CommitError(f"The edit was committed, but reading it back failed: {e}") from None
    finally:
        if check is not None:
            try:
                api.delete_edit(check)
            except PromoteError:
                pass
    out += ["", "### After (committed)", "", *table("production", after)]
    if not _same(releases[0], after):
        raise CommitError(
            "The edit was committed, but production does not show the planned release "
            f"({describe(releases[0])}). Check Play Console."
        )
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--action", choices=ACTIONS, default="promote")
    parser.add_argument("--version", default="", help="versionName to promote, e.g. 2.4.0")
    parser.add_argument("--rollout", type=int, choices=PERCENTS, default=20)
    parser.add_argument("--notes", type=Path, help="whatsnew-en-US of that version")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    out: list[str] = []
    code = 0
    try:
        notes = None
        version = args.version.removeprefix("v")
        if args.action == "promote":
            if not re.fullmatch(r"\d+\.\d+\.\d+", version):
                raise PromoteError(f"Version must look like 2.4.0, not '{args.version[:20]}'.")
            if args.notes is None:
                raise PromoteError("promote needs --notes (the whatsnew-en-US of that version).")
            notes = read_notes(args.notes)
        account = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
        if not account:
            raise PromoteError("Secret PLAY_SERVICE_ACCOUNT_JSON is not set in this environment.")
        for warning in check_account(
            account, os.environ.get("PLAY_TESTING_ACCOUNT", ""), args.dry_run
        ):
            print(f"::warning title=promote::{warning}")
            out += [f"**Warning:** {warning}", ""]
        api = PlayApi(access_token(account))
        run(
            api,
            args.action,
            version=version,
            percent=args.rollout,
            notes=notes,
            dry_run=args.dry_run,
            out=out,
        )
    except PromoteError as e:
        message = " ".join(str(e).split())
        out += ["", f"**Failed:** {message}"]
        if not isinstance(e, CommitError):
            out += ["", "Nothing was changed on Google Play."]
        print(f"::error title=promote::{message}")
        code = 1
    # One line stays one line: no value can start a line of its own (a workflow command).
    text = "\n".join(" ".join(line.split()) for line in out) + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
