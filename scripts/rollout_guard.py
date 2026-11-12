#!/usr/bin/env python3
"""Raise, or halt, the staged production rollout on Google Play without a person.

Used by .github/workflows/rollout-guard.yml, daily (docs/QA.md "Production release
(automatic)"). For the release that is in progress on production:

  health WORSE              halt it and open a GitHub issue (label release-halted)
  held long enough, and     raise it one step: 20% -> 50% -> 100% (100 completes it)
  health OK or UNKNOWN
  anything else             nothing: not held long enough, halted, completed, no release

A halted release is never resumed or raised here, whoever halted it.

Time at a fraction: Google Play does not say when a release reached a fraction or left
review, so the guard keeps its own log, one GitHub issue per versionCode (label
release-rollout) with a marker for each state it saw. Only markers written by
github-actions[bot] count, and the time is the one GitHub gave the issue or comment, so
nobody without write access can move the clock.

Health: Android vitals from the Play Developer Reporting API (v1beta1), user-perceived crash
rate and user-perceived ANR rate per versionCode and day since the rollout began, for the
new versionCode and the one production had before it.

Python standard library only (and scripts/play_promote.py next to this file, which uses the
runner's openssl): the job that holds the production Play key installs nothing from pip.
"""

from __future__ import annotations

import argparse
import importlib.util
import math
import os
import re
import sys
import urllib.parse
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from pathlib import Path


def _load_promote():
    """scripts/play_promote.py by its path: `python3 -I` leaves this folder off sys.path."""
    path = Path(__file__).resolve().with_name("play_promote.py")
    spec = importlib.util.spec_from_file_location("play_promote", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pp = _load_promote()

REPORTING = "https://playdeveloperreporting.googleapis.com/v1beta1/apps"
REPORTING_SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting"
GITHUB_API = "https://api.github.com"
BOT = "github-actions[bot]"
TRACK_LABEL = "release-rollout"
HALT_LABEL = "release-halted"
STEPS = (20, 50, 100)  # the fractions the guard raises to, in percent
# DAILY vitals exist only for calendar days in this time zone (Google's API reference).
VITALS_ZONE = "America/Los_Angeles"
MAX_PAGES = 20
# The daily run does not start at the same minute every day. Without this, a hold of 48 hours
# would be 47.9 hours at the run two days later and the step would wait a third day.
SCHEDULE_SLACK_HOURS = 1.0

OK, WORSE, UNKNOWN = "OK", "WORSE", "UNKNOWN"


@dataclass(frozen=True)
class Config:
    """Repository variables (docs/QA.md "Production release (automatic)")."""

    hold_hours: float = 48.0  # ROLLOUT_HOLD_HOURS
    min_user_days: float = 500.0  # ROLLOUT_MIN_USER_DAYS
    worse_factor: float = 1.5  # ROLLOUT_WORSE_FACTOR
    crash_bad: float = 1.09  # ROLLOUT_CRASH_BAD_PERCENT, Google's bad behaviour threshold
    anr_bad: float = 0.47  # ROLLOUT_ANR_BAD_PERCENT, Google's bad behaviour threshold


_VARIABLES = (
    # variable, field, lowest, highest
    ("ROLLOUT_HOLD_HOURS", "hold_hours", 0.0, 720.0),
    ("ROLLOUT_MIN_USER_DAYS", "min_user_days", 1.0, 1e9),
    ("ROLLOUT_WORSE_FACTOR", "worse_factor", 1.0, 100.0),
    ("ROLLOUT_CRASH_BAD_PERCENT", "crash_bad", 0.01, 100.0),
    ("ROLLOUT_ANR_BAD_PERCENT", "anr_bad", 0.01, 100.0),
)


def read_config(env) -> Config:
    """An unset or empty variable is its default; one that is not a number in range is an error."""
    values = {}
    for name, key, low, high in _VARIABLES:
        raw = str(env.get(name) or "").strip()
        if not raw:
            continue
        try:
            value = float(raw)
        except ValueError:
            value = math.nan
        if not low <= value <= high:  # also false for nan
            raise pp.PromoteError(
                f"Repository variable {name} must be a number from {low:g} to {high:g}."
            )
        values[key] = value
    return Config(**values)


# --- Android vitals (Play Developer Reporting API) --------------------------------------


@dataclass(frozen=True)
class Sample:
    """One versionCode over the days asked for."""

    rate: float | None  # percent of daily users, weighted by each day's users
    user_days: float  # daily distinct users, summed over the days
    days: int


def weigh(rows: list[tuple[float, float]]) -> Sample:
    """(rate in percent, distinct users) per day -> one user-weighted rate."""
    users = sum(u for _, u in rows)
    if users <= 0:
        return Sample(None, 0.0, len(rows))
    return Sample(sum(r * u for r, u in rows) / users, users, len(rows))


def _day(value) -> date:
    """A google.type.DateTime as a calendar day."""
    try:
        return date(int(value["year"]), int(value["month"]), int(value["day"]))
    except (KeyError, TypeError, ValueError):
        raise pp.PromoteError("The Reporting API gave a date this script cannot read.") from None


def _stamp(day: date) -> dict:
    return {"year": day.year, "month": day.month, "day": day.day, "timeZone": {"id": VITALS_ZONE}}


class VitalsApi:
    """The two calls per metric set this script needs."""

    def __init__(self, token: str, package: str = pp.PACKAGE, opener=pp._open):
        self._token = token
        self._base = f"{REPORTING}/{urllib.parse.quote(package, safe='')}"
        self._opener = opener

    def _call(self, method: str, path: str, body=None) -> dict:
        answer = pp.call(
            method, self._base + path, token=self._token, body=body, opener=self._opener
        )
        if not isinstance(answer, dict):
            raise pp.PromoteError(f"{method} {path}: the answer is not a JSON object.")
        return answer

    def latest_day_end(self, metric_set: str) -> date | None:
        """The day after the last day with DAILY data (an exclusive end), or None."""
        info = self._call("GET", f"/{metric_set}").get("freshnessInfo") or {}
        for freshness in info.get("freshnesses") or []:
            if freshness.get("aggregationPeriod") == "DAILY" and freshness.get("latestEndTime"):
                return _day(freshness["latestEndTime"])
        return None

    def daily(
        self, metric_set: str, metric: str, version_code: int, start: date, end: date
    ) -> list[tuple[float, float]]:
        """(rate in percent, distinct users) for each day in [start, end) with data."""
        body = {
            "timelineSpec": {
                "aggregationPeriod": "DAILY",
                "startTime": _stamp(start),
                "endTime": _stamp(end),
            },
            "dimensions": ["versionCode"],
            "metrics": [metric, "distinctUsers"],
            "filter": f"versionCode = {int(version_code)}",
            "pageSize": 1000,
        }
        rows: list[tuple[float, float]] = []
        for _ in range(MAX_PAGES):
            answer = self._call("POST", f"/{metric_set}:query", body=body)
            for row in answer.get("rows") or []:
                parsed = _row(row, metric, int(version_code))
                if parsed is not None:
                    rows.append(parsed)
            token = answer.get("nextPageToken")
            if not token:
                return rows
            body = {**body, "pageToken": token}
        raise pp.PromoteError(f"The Reporting API gave more than {MAX_PAGES} pages for one query.")


def _row(row: dict, metric: str, version_code: int) -> tuple[float, float] | None:
    """One day of one versionCode; None for a row of another versionCode or without users."""
    try:
        for dimension in row.get("dimensions") or []:
            if dimension.get("dimension") == "versionCode":
                value = dimension.get("int64Value") or dimension.get("stringValue")
                if int(value) != version_code:
                    return None
        values = {
            m["metric"]: float((m.get("decimalValue") or {}).get("value") or 0)
            for m in row.get("metrics") or []
        }
        rate, users = values[metric], values["distinctUsers"]
    except (AttributeError, KeyError, TypeError, ValueError):
        raise pp.PromoteError("The Reporting API gave a row this script cannot read.") from None
    # The API gives a rate as a share of users from 0 to 1 (0.0109 is 1.09%). Anything else
    # means this reading is wrong: stop instead of deciding on a number of the wrong size.
    if not (0 <= rate <= 1 and math.isfinite(users) and users >= 0):
        raise pp.PromoteError(
            f"The Reporting API gave {metric} = {rate:g} with {users:g} users: not a share "
            "of users from 0 to 1."
        )
    return (rate * 100, users) if users > 0 else None


# (title, metric set, metric, Config field with the bad behaviour threshold)
METRICS = (
    ("User-perceived crash rate", "crashRateMetricSet", "userPerceivedCrashRate", "crash_bad"),
    ("User-perceived ANR rate", "anrRateMetricSet", "userPerceivedAnrRate", "anr_bad"),
)


def judge(new: Sample, old: Sample | None, bad: float, cfg: Config) -> str:
    """WORSE needs enough users, a rate above Google's threshold and clearly above the old one."""
    if new.rate is None or new.user_days < cfg.min_user_days:
        return UNKNOWN
    if new.rate <= bad:
        return OK
    # No usable figure for the previous version: above the threshold is enough.
    if old is None or old.rate is None or old.user_days < cfg.min_user_days:
        return WORSE
    return WORSE if new.rate > old.rate * cfg.worse_factor else OK


def _figure(sample: Sample | None) -> str:
    if sample is None or sample.rate is None:
        return "no data"
    return f"{sample.rate:.2f}% over {sample.user_days:,.0f} user-days ({sample.days} days)"


@dataclass
class Health:
    verdict: str
    lines: list[str] = field(default_factory=list)


def health(vitals, new_code: int, old_code: int | None, since: datetime, cfg: Config) -> Health:
    """Compare the new versionCode with the previous one over the days since `since`."""
    # A day in VITALS_ZONE starts 7 or 8 hours after the UTC day: one day earlier covers it.
    start = (since.astimezone(UTC) - timedelta(days=1)).date()
    verdicts, lines = [], []
    for title, metric_set, metric, bad_key in METRICS:
        bad = getattr(cfg, bad_key)
        end = vitals.latest_day_end(metric_set)
        if end is None or end <= start:
            upto = "no daily data" if end is None else f"data only up to {end - timedelta(days=1)}"
            verdicts.append(UNKNOWN)
            lines.append(f"{title}: {UNKNOWN}, {upto} (asked from {start}).")
            continue
        new = weigh(vitals.daily(metric_set, metric, new_code, start, end))
        old = None
        if old_code is not None:
            old = weigh(vitals.daily(metric_set, metric, old_code, start, end))
        verdict = judge(new, old, bad, cfg)
        verdicts.append(verdict)
        lines.append(
            f"{title}: {verdict}. New {new_code}: {_figure(new)}; previous "
            f"{old_code if old_code is not None else 'none'}: {_figure(old)}; bad from {bad:g}%, "
            f"days {start} to {end - timedelta(days=1)}."
        )
    if WORSE in verdicts:
        return Health(WORSE, lines)
    return Health(OK if OK in verdicts else UNKNOWN, lines)


# --- The guard's log: one GitHub issue per versionCode ----------------------------------


class GitHub:
    """The issue calls this script needs, with the job's own token (issues: write)."""

    def __init__(self, token: str, repo: str, opener=pp._open):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
            raise pp.PromoteError("GITHUB_REPOSITORY is not owner/name.")
        self._token = token
        self._base = f"{GITHUB_API}/repos/{repo}"
        self.owner = repo.split("/")[0]
        self._opener = opener

    def _call(self, method: str, path: str, body=None):
        return pp.call(method, self._base + path, token=self._token, body=body, opener=self._opener)

    def _pages(self, path: str) -> list[dict]:
        items: list[dict] = []
        for page in range(1, MAX_PAGES + 1):
            batch = self._call("GET", f"{path}per_page=100&page={page}")
            if not isinstance(batch, list):
                raise pp.PromoteError(f"GET {path}: GitHub gave no list.")
            items += batch
            if len(batch) < 100:
                return items
        raise pp.PromoteError(f"GET {path}: more than {MAX_PAGES} pages.")

    def issues(self, label: str) -> list[dict]:
        """Issues with `label`, newest first (pull requests left out)."""
        query = urllib.parse.urlencode(
            {"labels": label, "state": "all", "sort": "created", "direction": "desc"}
        )
        return [i for i in self._pages(f"/issues?{query}&") if "pull_request" not in i]

    def comments(self, number: int) -> list[dict]:
        return self._pages(f"/issues/{int(number)}/comments?")

    def ensure_label(self, name: str) -> None:
        """Create the label if it is not there: the guard finds its log by this label."""
        try:
            self._call("POST", "/labels", body={"name": name})
        except pp.PromoteError as e:
            if "HTTP 422" not in str(e):  # 422: the label already exists
                raise

    def create_issue(self, title: str, body: str, labels: list[str], assign: bool = False) -> int:
        for label in labels:
            self.ensure_label(label)
        issue = {"title": title, "body": body, "labels": labels}
        if assign:
            issue["assignees"] = [self.owner]
        answer = self._call("POST", "/issues", body=issue)
        number = answer.get("number") if isinstance(answer, dict) else None
        if not number:
            raise pp.PromoteError("GitHub opened no issue.")
        got = {str(label.get("name")) for label in answer.get("labels") or []}
        if not set(labels) <= got:
            # GitHub drops labels it may not set. Without its label the log is never found again.
            raise pp.PromoteError(
                f"GitHub opened issue {number} without the label {', '.join(labels)}."
            )
        return int(number)

    def comment(self, number: int, body: str) -> None:
        self._call("POST", f"/issues/{int(number)}/comments", body={"body": body})

    def close(self, number: int) -> None:
        self._call("PATCH", f"/issues/{int(number)}", body={"state": "closed"})


MARK = re.compile(
    r"<!-- rollout-guard code=(\d+) status=(inProgress|halted|completed|gone) "
    r"percent=(\d+(?:\.\d+)?) -->"
)


def marker(code: int, status: str, percent: float) -> str:
    return f"<!-- rollout-guard code={int(code)} status={status} percent={percent:g} -->"


def _by_bot(item: dict) -> bool:
    return ((item.get("user") or {}).get("login")) == BOT


def _time(item: dict) -> datetime:
    try:
        return datetime.fromisoformat(str(item["created_at"]).replace("Z", "+00:00"))
    except (KeyError, ValueError):
        raise pp.PromoteError("GitHub gave an issue or comment without a creation time.") from None


def _marks(item: dict, code: int | None = None) -> list[tuple[datetime, str, float]]:
    """The states written in one issue or comment, when it is the bot's (and of `code`)."""
    if not _by_bot(item):
        return []
    return [
        (_time(item), m[2], float(m[3]))
        for m in MARK.finditer(str(item.get("body") or ""))
        if code is None or int(m[1]) == code
    ]


@dataclass
class Log:
    """What the guard saw of one versionCode, oldest first."""

    number: int | None = None
    is_open: bool = False
    entries: list[tuple[datetime, str, float]] = field(default_factory=list)

    def since(self, status: str, percent: float) -> datetime | None:
        """When the newest entry was written, if it is this very state; else None."""
        if not self.entries:
            return None
        at, last_status, last_percent = self.entries[-1]
        same = last_status == status and abs(last_percent - percent) < 1e-6
        return at if same else None

    @property
    def first(self) -> datetime | None:
        return self.entries[0][0] if self.entries else None


def _code_of(issue: dict) -> int | None:
    """The versionCode a tracking issue is about: the first marker the bot put in its body."""
    if not _by_bot(issue):
        return None
    found = MARK.search(str(issue.get("body") or ""))
    return int(found[1]) if found else None


def read_log(gh, code: int) -> Log:
    for issue in gh.issues(TRACK_LABEL):  # newest first
        if _code_of(issue) != code:
            continue
        entries = _marks(issue, code)
        for comment in gh.comments(issue["number"]):
            entries += _marks(comment, code)
        entries.sort(key=lambda e: e[0])
        return Log(int(issue["number"]), issue.get("state") == "open", entries)
    return Log()


def record(gh, log: Log, release: dict, status: str, percent: float, note: str, now: datetime):
    """Add a state to the log of this release (a new issue the first time)."""
    code = pp.codes(release)[0]
    text = f"{note}\n\n{marker(code, status, percent)}"
    if log.number is None:
        name = pp._cell(release.get("name") or "no name")
        intro = (
            "The rollout guard (`.github/workflows/rollout-guard.yml`) keeps its clock here: "
            "one comment each time it sees this release in a new state. Leave the issue open; "
            "the guard closes it when the release is complete (docs/QA.md, Production release "
            "(automatic))."
        )
        title = f"Production rollout: {name} ({code})"
        log.number = gh.create_issue(title, f"{intro}\n\n{text}", [TRACK_LABEL])
        log.is_open = True
    else:
        gh.comment(log.number, text)
    log.entries.append((now, status, percent))


def close_finished(gh, production: list[dict], out: list[str], dry_run: bool) -> None:
    """Close the logs of releases that are no longer staged (completed or replaced)."""
    staged = {
        c for r in production if r.get("status") in ("inProgress", "halted") for c in pp.codes(r)
    }
    done = {c for r in production if r.get("status") == "completed" for c in pp.codes(r)}
    for issue in gh.issues(TRACK_LABEL):
        code = _code_of(issue)
        if issue.get("state") != "open" or code is None or code in staged:
            continue
        number = int(issue["number"])
        how = "is complete (100%)" if code in done else "is no longer on production"
        if dry_run:
            out.append(f"- Dry run: would close the log of {code}, issue {number} ({how}).")
            continue
        status = "completed" if code in done else "gone"
        gh.comment(number, f"versionCode {code} {how}.\n\n{marker(code, status, 100)}")
        gh.close(number)
        out.append(f"- Closed the log of {code}, issue {number}: it {how}.")


# --- The decision -----------------------------------------------------------------------


def read_production(play) -> list[dict]:
    edit = play.create_edit()
    try:
        return play.get_track(edit, "production")
    finally:
        try:
            play.delete_edit(edit)
        except pp.PromoteError:
            pass  # an edit that was only read changes nothing and expires by itself


def next_step(percent: float) -> int:
    return next(step for step in STEPS if step > percent + 1e-6)


def _utc(at: datetime) -> str:
    return at.astimezone(UTC).strftime("%Y-%m-%d %H:%M UTC")


def _after_commit(action, what: str) -> None:
    """Run a GitHub write that follows a Google Play commit: its failure is not 'no change'."""
    try:
        action()
    except pp.PromoteError as e:
        raise pp.CommitError(f"Google Play was changed, but {what} failed: {e}") from None


def guard(
    play, vitals, gh, *, cfg: Config, now: datetime, dry_run: bool = False, out=None
) -> list[str]:
    """One pass. Returns the summary lines; `out` gets them as they are made."""
    out = [] if out is None else out
    out += ["## Rollout guard" + (" (dry run)" if dry_run else ""), ""]
    production = read_production(play)
    out += ["### Before", "", *pp.table("production", production), "", "### Decision", ""]
    unchanged = ["", "### After", "", "Nothing was changed on Google Play (state as read above)."]
    staged = pp._only(production, "inProgress")
    halted = pp._only(production, "halted")

    if staged is None and halted is None:
        out.append("- **Nothing to do:** no staged rollout is in progress on production.")
        close_finished(gh, production, out, dry_run)
        out += unchanged
        return out

    release = staged or halted
    if staged is not None and halted is not None or len(pp.codes(release)) != 1:
        raise pp.PromoteError(
            f"Production holds more than one staged versionCode ({pp._state(production)}); "
            "fix it in Play Console."
        )
    code = pp.codes(release)[0]
    percent = pp.percent_of(release)
    if not percent or percent >= 100:
        raise pp.PromoteError(f"The staged release has no fraction ({pp.describe(release)}).")
    log = read_log(gh, code)
    where = f"issue {log.number}" if log.number else "no log yet"

    if staged is None:
        out.append(
            f"- **Nothing to do:** {pp.describe(release)} is halted. The guard never resumes or "
            "raises a halted release. Resume it by hand (Actions > promote > resume), or ship "
            "the fix as a new version."
        )
        if log.since("halted", percent) is None and not dry_run:
            record(gh, log, release, "halted", percent, f"Seen halted at {percent:g}%.", now)
        out += unchanged
        return out

    since = log.since("inProgress", percent)
    if since is None:
        since = now
        if dry_run:
            out.append(
                f"- First sight of {code} at {percent:g}% ({where}). Dry run: the clock is "
                "not started."
            )
        else:
            note = f"Seen in progress at {percent:g}%: the hold of {cfg.hold_hours:g} h starts."
            record(gh, log, release, "inProgress", percent, note, now)
            out.append(f"- First sight of {code} at {percent:g}%: the clock starts now.")
    held = max(0.0, (now - since).total_seconds() / 3600)
    out.append(
        f"- Time at {percent:g}%: {held:.1f} h of {cfg.hold_hours:g} h "
        f"(since {_utc(since)}, issue {log.number or 'not opened'})."
    )

    before = [c for r in production if r.get("status") == "completed" for c in pp.codes(r)]
    previous = max((c for c in before if c != code), default=None)
    state = health(vitals, code, previous, log.first or now, cfg)
    if state.verdict == UNKNOWN:
        out.append("- Health: **UNKNOWN, no vitals data**; this run goes by time only.")
    else:
        out.append(f"- Health: **{state.verdict}**.")
    out += [f"  - {line}" for line in state.lines]

    if state.verdict == WORSE:
        out += [f"- **Halt** {code} at {percent:g}%: its health is worse.", ""]
        pp.run(play, "halt", dry_run=dry_run, out=out)
        if dry_run:
            out += ["", f"Dry run: no `{HALT_LABEL}` issue was opened."]
            return out
        body = "\n".join(
            [
                f"The rollout guard halted the staged production release at {_utc(now)}.",
                "",
                f"- versionCode: {code} ({pp._cell(release.get('name') or 'no name')})",
                f"- Fraction when halted: {percent:g}%",
                f"- Previous production versionCode: {previous or 'none'}",
                *[f"- {line}" for line in state.lines],
                "",
                "No new users get this version; users who have it keep it. The guard will not "
                "resume or raise it. Look at Play Console > Android vitals, then either ship a "
                "fix as a new version (it replaces this release) or, if the numbers were wrong, "
                "Actions > promote > Run workflow > `resume`.",
            ]
        )

        def report():
            number = gh.create_issue(
                f"Release halted: {code} at {percent:g}%", body, [HALT_LABEL], assign=True
            )
            out.extend(["", f"Opened issue {number} (`{HALT_LABEL}`)."])
            record(
                gh, log, release, "halted", percent, f"Halted by the guard at {percent:g}%.", now
            )

        _after_commit(report, f"opening the {HALT_LABEL} issue")
        return out

    left = cfg.hold_hours - SCHEDULE_SLACK_HOURS - held
    if left > 0:
        out.append(
            f"- **Wait:** about {left:.1f} h more at {percent:g}% before the next step "
            f"(a run up to {SCHEDULE_SLACK_HOURS:g} h early counts)."
        )
        out += unchanged
        return out

    target = next_step(percent)
    why = "no vitals data, by time only" if state.verdict == UNKNOWN else "health OK"
    out += [f"- **Raise** {code} from {percent:g}% to {target}% ({why}).", ""]
    pp.run(play, "rollout", percent=target, dry_run=dry_run, out=out)
    if dry_run:
        return out

    def note():
        if target >= 100:
            record(gh, log, release, "completed", 100, f"Raised to 100% ({why}): complete.", now)
            gh.close(log.number)
        else:
            text = f"Raised from {percent:g}% to {target}% ({why}); the hold starts again."
            record(gh, log, release, "inProgress", target, text, now)

    _after_commit(note, "writing the guard's log")
    return out


# --- Run ------------------------------------------------------------------------------

GUARD_OFF = (
    "Repository variable AUTO_PROMOTE is not `on`: the rollout guard read and changed nothing. "
    "Only a dry run works while it is off."
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    out: list[str] = []
    code = 0
    try:
        if not args.dry_run and not pp.auto_promote_on():
            # The kill switch: nothing is read from Google Play, not even the key.
            out += ["## Rollout guard", "", GUARD_OFF]
            print(f"::notice title=rollout guard::{GUARD_OFF}")
            return pp._finish(out, 0)
        cfg = read_config(os.environ)
        account = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
        if not account:
            raise pp.PromoteError(
                "Secret PLAY_SERVICE_ACCOUNT_JSON is not set in this environment."
            )
        github_token = os.environ.get("GITHUB_TOKEN", "")
        if not github_token:
            raise pp.PromoteError("GITHUB_TOKEN is not set: the guard keeps its log in an issue.")
        for warning in pp.check_account(
            account, os.environ.get("PLAY_TESTING_ACCOUNT", ""), args.dry_run
        ):
            print(f"::warning title=rollout guard::{warning}")
            out += [f"**Warning:** {warning}", ""]
        gh = GitHub(github_token, os.environ.get("GITHUB_REPOSITORY", ""))
        token = pp.access_token(account, scope=f"{pp.SCOPE} {REPORTING_SCOPE}")
        guard(
            pp.PlayApi(token),
            VitalsApi(token),
            gh,
            cfg=cfg,
            now=datetime.now(UTC),
            dry_run=args.dry_run,
            out=out,
        )
    except pp.PromoteError as e:
        message = " ".join(str(e).split())
        out += ["", f"**Failed:** {message}"]
        if not isinstance(e, pp.CommitError):
            out += ["", "Nothing was changed on Google Play by this run."]
        print(f"::error title=rollout guard::{message}")
        code = 1
    return pp._finish(out, code)


if __name__ == "__main__":
    sys.exit(main())
