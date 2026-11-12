"""scripts/rollout_guard.py with a fake Google Play, a fake Reporting API and fake GitHub issues."""

import copy
import importlib.util
import io
import json
import sys
import urllib.error
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "rollout_guard", ROOT / "scripts" / "rollout_guard.py"
)
rg = importlib.util.module_from_spec(spec)
sys.modules["rollout_guard"] = rg  # dataclasses look their module up by name
spec.loader.exec_module(rg)
pp = rg.pp  # the guard's own copy of play_promote: its errors are the ones raised here

NOW = datetime(2026, 11, 20, 2, 17, tzinfo=UTC)
BOT = {"login": "github-actions[bot]"}


def rel(code: int, name: str, status: str = "completed", fraction: float | None = None) -> dict:
    release = {"name": name, "versionCodes": [str(code)], "status": status}
    if fraction is not None:
        release["userFraction"] = fraction
    return release


class FakePlay:
    """The production track in memory; an edit changes it only when committed."""

    def __init__(self, production: list[dict]):
        self.tracks = {"production": production, "alpha": []}
        self.calls: list[tuple] = []
        self.pending: dict[str, dict] = {}
        self.fail_read = False

    def create_edit(self) -> str:
        edit = f"edit{len(self.calls) + 1}"
        self.pending[edit] = {}
        self.calls.append(("create", edit))
        return edit

    def get_track(self, edit: str, track: str) -> list[dict]:
        self.calls.append(("get", edit, track))
        if self.fail_read:
            raise pp.PromoteError("GET /edits/x/tracks/production: HTTP 503: backend error")
        return copy.deepcopy(self.pending[edit].get(track, self.tracks[track]))

    def update_track(self, edit: str, track: str, releases: list[dict]) -> None:
        self.calls.append(("update", edit, track, copy.deepcopy(releases)))
        self.pending[edit][track] = copy.deepcopy(releases)

    def validate_edit(self, edit: str) -> None:
        self.calls.append(("validate", edit))

    def commit_edit(self, edit: str) -> None:
        self.calls.append(("commit", edit))
        for track, releases in self.pending.pop(edit).items():
            staged = any(r["status"] in ("inProgress", "halted") for r in releases)
            kept = [
                r
                for r in self.tracks[track]
                if staged and r["status"] == "completed" and r not in releases
            ]
            self.tracks[track] = releases + kept

    def delete_edit(self, edit: str) -> None:
        self.calls.append(("delete", edit))
        self.pending.pop(edit, None)

    def did(self, what: str) -> list[tuple]:
        return [c for c in self.calls if c[0] == what]


class FakeVitals:
    """Daily (rate in percent, users) per (metric set, versionCode); nothing = no data."""

    def __init__(self, data: dict | None = None, end: date | None = date(2026, 11, 20)):
        self.data = data or {}
        self.end = end
        self.fail = False
        self.asked: list[tuple] = []

    def latest_day_end(self, metric_set: str) -> date | None:
        if self.fail:
            raise pp.PromoteError("GET /v1beta1/apps/x/crashRateMetricSet: HTTP 403: no access")
        return self.end

    def daily(self, metric_set, metric, version_code, start, end):
        self.asked.append((metric_set, metric, version_code, start, end))
        return list(self.data.get((metric_set, version_code), []))


class FakeGitHub:
    owner = "hndrwn-dk"

    def __init__(self):
        self.items: list[dict] = []  # issues
        self.notes: dict[int, list[dict]] = {}
        self.writes: list[tuple] = []
        self.clock = NOW
        self.fail_writes = False
        self.locked: list[int] = []

    def add_issue(self, body, label=rg.TRACK_LABEL, user=BOT, at=NOW, state="open") -> int:
        number = len(self.items) + 1
        self.items.append(
            {
                "number": number,
                "body": body,
                "labels": [{"name": label}],
                "user": user,
                "created_at": at.isoformat().replace("+00:00", "Z"),
                "state": state,
            }
        )
        self.notes[number] = []
        return number

    def add_comment(self, number, body, user=BOT, at=NOW) -> None:
        self.notes[number].append(
            {"body": body, "user": user, "created_at": at.isoformat().replace("+00:00", "Z")}
        )

    def issues(self, label: str) -> list[dict]:
        found = [i for i in self.items if {"name": label} in i["labels"]]
        return sorted(found, key=lambda i: i["number"], reverse=True)

    def comments(self, number: int) -> list[dict]:
        return list(self.notes[number])

    def _write(self, *what) -> None:
        if self.fail_writes:
            raise pp.PromoteError("POST /repos/o/r/issues: HTTP 403: Resource not accessible")
        self.writes.append(what)

    def create_issue(self, title, body, labels, assign=False) -> int:
        self._write("issue", title, body, labels, assign)
        number = self.add_issue(body, label=labels[0], at=self.clock)
        self.items[-1]["title"] = title
        return number

    def comment(self, number: int, body: str) -> None:
        self._write("comment", number, body)
        self.add_comment(number, body, at=self.clock)

    def close(self, number: int) -> None:
        self._write("close", number)
        self.items[number - 1]["state"] = "closed"

    def lock(self, number: int) -> None:
        self.locked.append(number)


def staged(fraction: float = 0.2, status: str = "inProgress") -> FakePlay:
    return FakePlay([rel(745, "2.4.0", status, fraction), rel(738, "738 (2.3.0)")])


def seen(gh: FakeGitHub, percent: float, hours_ago: float, status="inProgress", code=745) -> int:
    """The guard's log of `code`: first seen in this state `hours_ago` hours before NOW."""
    return gh.add_issue(
        f"log\n\n{rg.marker(code, status, percent)}", at=NOW - timedelta(hours=hours_ago)
    )


def go(play, vitals=None, gh=None, cfg=None, **kw) -> str:
    out = rg.guard(
        play,
        vitals or FakeVitals(),
        gh if gh is not None else FakeGitHub(),
        cfg=cfg or rg.Config(),
        now=NOW,
        **kw,
    )
    return "\n".join(out)


CRASH, ANR = "crashRateMetricSet", "anrRateMetricSet"


def vitals(new_crash=None, old_crash=None, new_anr=None, old_anr=None) -> FakeVitals:
    """Three days of 1,000 users each at the given rates (percent); None = no data."""
    data = {}
    for key, rate in (
        ((CRASH, 745), new_crash),
        ((CRASH, 738), old_crash),
        ((ANR, 745), new_anr),
        ((ANR, 738), old_anr),
    ):
        if rate is not None:
            data[key] = [(rate, 1000.0)] * 3
    return FakeVitals(data)


# --- time at a fraction ------------------------------------------------------------------


def test_first_sight_starts_the_clock_and_waits():
    play, gh = staged(0.2), FakeGitHub()
    out = go(play, gh=gh)
    (issue,) = [w for w in gh.writes if w[0] == "issue"]
    assert issue[1] == "Production rollout: 2.4.0 (745)" and issue[3] == ["release-rollout"]
    assert rg.marker(745, "inProgress", 20) in issue[2] and issue[4] is False
    assert "the clock starts now" in out and "**Wait:** about 47.0 h more at 20%" in out
    assert gh.locked == [1]  # strangers cannot comment on the log
    assert not play.did("update") and not play.did("commit")
    assert "Nothing was changed on Google Play" in out


def test_hold_not_reached_waits():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 46)
    out = go(play, gh=gh)
    assert "Time at 20%: 46.0 h of 48 h" in out and "**Wait:** about 1.0 h more" in out
    assert not play.did("commit") and not gh.writes


def test_a_daily_run_that_starts_a_few_minutes_early_still_counts_as_two_days():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 47.9)  # first seen by the run two days ago, which started 6 minutes later
    out = go(play, gh=gh)
    assert "Time at 20%: 47.9 h of 48 h" in out and "**Raise** 745 from 20% to 50%" in out
    assert len(play.did("commit")) == 1


def test_hold_reached_and_health_ok_raises_20_to_50():
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 49)
    out = go(play, vitals(new_crash=0.4, old_crash=0.5, new_anr=0.1, old_anr=0.1), gh)
    (update,) = play.did("update")
    assert update[3] == [
        {"name": "2.4.0", "versionCodes": ["745"], "status": "inProgress", "userFraction": 0.5}
    ]
    assert len(play.did("commit")) == 1
    assert "**Raise** 745 from 20% to 50% (health OK)" in out and "Health: **OK**" in out
    assert (
        "### After (committed)" in out and "| production | 745 | 2.4.0 | inProgress | 50% |" in out
    )
    # The log gets the new state, so the hold starts again at 50%.
    assert gh.writes == [
        ("comment", number, gh.notes[number][0]["body"]),
    ]
    assert rg.marker(745, "inProgress", 50) in gh.notes[number][0]["body"]


def test_hold_reached_at_50_completes_the_release_and_closes_the_log():
    play, gh = staged(0.5), FakeGitHub()
    number = seen(gh, 20, 100)
    gh.add_comment(number, rg.marker(745, "inProgress", 50), at=NOW - timedelta(hours=48))
    out = go(play, vitals(new_crash=0.4, old_crash=0.5), gh)
    (release,) = play.did("update")[0][3]
    assert release["status"] == "completed" and "userFraction" not in release
    assert play.tracks["production"] == [release]
    assert "from 50% to 100%" in out and "| production | 745 | 2.4.0 | completed | 100% |" in out
    assert gh.items[number - 1]["state"] == "closed"
    assert rg.marker(745, "completed", 100) in gh.notes[number][-1]["body"]


def test_unknown_health_raises_on_time_only_and_says_so():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 48)
    out = go(play, gh=gh)  # no vitals rows at all
    assert "Health: **UNKNOWN, no vitals data**; this run goes by time only." in out
    assert "**Raise** 745 from 20% to 50% (no vitals data, by time only)" in out
    assert len(play.did("commit")) == 1


def test_too_few_users_is_unknown_not_worse():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 48)
    few = FakeVitals({(CRASH, 745): [(9.0, 100.0)], (CRASH, 738): [(0.3, 5000.0)]})
    out = go(play, few, gh)
    assert "UNKNOWN, no vitals data" in out and "9.00% over 100 user-days" in out
    assert play.tracks["production"][0]["userFraction"] == 0.5  # raised by time


def test_a_clock_started_by_someone_else_does_not_count():
    play, gh = staged(0.2), FakeGitHub()
    gh.add_issue(
        rg.marker(745, "inProgress", 20), user={"login": "mallory"}, at=NOW - timedelta(days=9)
    )
    number = seen(gh, 20, 10)
    gh.add_comment(
        number,
        rg.marker(745, "inProgress", 20),
        user={"login": "mallory"},
        at=NOW - timedelta(days=9),
    )
    out = go(play, gh=gh)
    assert "Time at 20%: 10.0 h of 48 h" in out and not play.did("commit")


def test_a_fraction_changed_by_hand_starts_the_hold_again():
    play, gh = staged(0.5), FakeGitHub()
    number = seen(gh, 20, 100)  # the owner raised it to 50% with Actions > promote
    out = go(play, gh=gh)
    assert "First sight of 745 at 50%" in out and "**Wait:**" in out
    assert rg.marker(745, "inProgress", 50) in gh.notes[number][0]["body"]
    assert not play.did("commit")


def test_other_fractions_step_up_the_same_ladder():
    assert [rg.next_step(p) for p in (10, 20, 35, 50, 99.5)] == [20, 50, 50, 100, 100]


# --- health ------------------------------------------------------------------------------


def test_worse_health_halts_and_opens_an_issue_even_before_the_hold():
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 5)
    out = go(play, vitals(new_crash=2.4, old_crash=0.5, new_anr=0.1, old_anr=0.1), gh)
    (update,) = play.did("update")
    assert update[3][0]["status"] == "halted" and update[3][0]["userFraction"] == 0.2
    assert len(play.did("commit")) == 1
    assert "**Halt** 745 at 20%" in out and "| production | 745 | 2.4.0 | halted | 20% |" in out
    (issue,) = [w for w in gh.writes if w[0] == "issue"]
    _, title, body, labels, assign = issue
    assert title == "Release halted: 745 at 20%" and labels == ["release-halted"] and assign
    assert "versionCode: 745 (2.4.0)" in body and "Fraction when halted: 20%" in body
    assert "halted the staged production release at 2026-11-20 02:17 UTC" in body
    assert "User-perceived crash rate: WORSE. New 745: 2.40% over 3,000 user-days" in body
    assert "previous 738: 0.50% over 3,000 user-days" in body and "bad from 1.09%" in body
    assert rg.marker(745, "halted", 20) in gh.notes[number][-1]["body"]
    assert "After a resume the guard judges only the days from then on" in body


def test_worse_anr_alone_halts():
    play, gh = staged(0.5), FakeGitHub()
    seen(gh, 50, 5)
    go(play, vitals(new_crash=0.2, old_crash=0.2, new_anr=0.9, old_anr=0.2), gh)
    assert play.tracks["production"][0]["status"] == "halted"


@pytest.mark.parametrize(
    ("new", "old"),
    [
        (1.0, 0.1),  # ten times the old rate, but under Google's threshold
        (1.3, 1.0),  # over the threshold, but the old version was as bad (not 1.5 times)
    ],
)
def test_not_worse_without_both_the_margin_and_the_threshold(new, old):
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 5)
    out = go(play, vitals(new_crash=new, old_crash=old), gh)
    assert "Health: **OK**" in out and not play.did("commit")


def test_over_the_threshold_with_no_figure_for_the_old_version_is_worse():
    cfg = rg.Config()
    assert rg.judge(rg.Sample(2.0, 900, 3), None, 1.09, cfg) == rg.WORSE
    assert rg.judge(rg.Sample(2.0, 900, 3), rg.Sample(0.1, 50, 3), 1.09, cfg) == rg.WORSE
    assert rg.judge(rg.Sample(None, 0, 0), None, 1.09, cfg) == rg.UNKNOWN


def test_the_rate_is_weighted_by_each_days_users():
    sample = rg.weigh([(1.0, 100.0), (3.0, 300.0)])
    assert sample.rate == pytest.approx(2.5) and sample.user_days == 400 and sample.days == 2
    assert rg.weigh([]).rate is None


def test_health_asks_from_the_day_before_the_rollout_began_for_both_versions():
    play, gh, fake = staged(0.5), FakeGitHub(), vitals(new_crash=0.2, old_crash=0.2)
    number = seen(gh, 20, 100)  # first seen 15 Nov 22:17 UTC
    gh.add_comment(number, rg.marker(745, "inProgress", 50), at=NOW - timedelta(hours=20))
    go(play, fake, gh)
    assert (CRASH, "userPerceivedCrashRate", 745, date(2026, 11, 14), date(2026, 11, 20)) in (
        fake.asked
    )
    assert (ANR, "userPerceivedAnrRate", 738, date(2026, 11, 14), date(2026, 11, 20)) in fake.asked


def test_vitals_that_end_before_the_rollout_are_unknown():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 48)
    fake = vitals(new_crash=9.0, old_crash=0.1)
    fake.end = date(2026, 11, 17)  # the rollout was first seen on 18 Nov
    out = go(play, fake, gh)
    assert "UNKNOWN, data only up to 2026-11-16" in out and not fake.asked


def test_a_reporting_api_error_fails_and_changes_nothing():
    play, gh, fake = staged(0.2), FakeGitHub(), FakeVitals()
    seen(gh, 20, 100)  # the hold is long over: without the error it would raise
    fake.fail = True
    with pytest.raises(pp.PromoteError, match="HTTP 403"):
        go(play, fake, gh)
    assert not play.did("update") and not play.did("commit") and not gh.writes
    assert play.tracks["production"][0]["userFraction"] == 0.2


def test_a_google_play_error_fails_and_changes_nothing():
    play = staged(0.2)
    play.fail_read = True
    with pytest.raises(pp.PromoteError, match="HTTP 503"):
        go(play)
    assert not play.did("update") and not play.did("commit")
    assert play.did("delete")  # the edit it opened is thrown away


def test_a_github_error_before_the_decision_fails_and_changes_nothing():
    play, gh = staged(0.2), FakeGitHub()
    gh.fail_writes = True  # the first sight cannot be written down
    with pytest.raises(pp.PromoteError, match="HTTP 403"):
        go(play, gh=gh)
    assert not play.did("commit")


def test_a_github_error_after_a_raise_never_says_nothing_changed():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 49)
    gh.fail_writes = True
    with pytest.raises(pp.CommitError, match="Google Play was changed, but writing the guard"):
        go(play, gh=gh)
    assert play.tracks["production"][0]["userFraction"] == 0.5


def test_resumed_after_a_guard_halt_the_old_days_are_not_judged_again():
    play, gh, fake = staged(0.2), FakeGitHub(), vitals(new_crash=5.0, old_crash=0.2)
    number = seen(gh, 20, 200)
    gh.add_comment(number, rg.marker(745, "halted", 20), at=NOW - timedelta(hours=100))
    out = go(play, fake, gh)  # the owner resumed it: first sight again, on 20 Nov
    assert "First sight of 745 at 20%" in out and "**Halt**" not in out
    # Only whole days after the resume count, and vitals do not reach them yet.
    assert "UNKNOWN, data only up to 2026-11-19 (asked from 2026-11-21)" in out
    assert not fake.asked and not play.did("commit")
    # Two days later the hold is over, but vitals still do not cover a day since the resume:
    # no raise without them.
    out = "\n".join(rg.guard(play, fake, gh, cfg=rg.Config(), now=NOW + timedelta(hours=48)))
    assert "the next step waits for a whole day of vitals" in out and not play.did("commit")
    # Three days later vitals cover 21 and 22 Nov: still worse, so it is halted again.
    fake.end = date(2026, 11, 23)
    later = NOW + timedelta(hours=72)
    out = "\n".join(rg.guard(play, fake, gh, cfg=rg.Config(), now=later))
    assert "**Halt** 745 at 20%" in out
    assert {(a[3], a[4]) for a in fake.asked} == {(date(2026, 11, 21), date(2026, 11, 23))}


def test_a_halt_whose_issue_could_not_be_opened_gets_it_at_the_next_run():
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 5)

    def fail_the_issue(title, body, labels, assign=False):
        raise pp.PromoteError("POST /repos/o/r/issues: HTTP 502: no details")

    opener, gh.create_issue = gh.create_issue, fail_the_issue
    with pytest.raises(pp.CommitError, match="Google Play was changed, but opening the"):
        go(play, vitals(new_crash=2.4, old_crash=0.5), gh)
    assert play.tracks["production"][0]["status"] == "halted"
    # The reason was written down before the halt, and the halt right after it.
    noted = gh.notes[number][-2]["body"]
    assert rg.marker(745, "halting", 20) in noted and "2.40% over 3,000 user-days" in noted
    assert rg.marker(745, "halted", 20) in gh.notes[number][-1]["body"]
    gh.create_issue = opener
    out = go(play, gh=gh)  # the next day
    (issue,) = [w for w in gh.writes if w[0] == "issue"]
    assert issue[1] == "Release halted: 745 at 20%" and issue[3] == ["release-halted"] and issue[4]
    assert f"issue {number}" in issue[2] and "Opened the missing issue" in out
    gh.writes.clear()
    go(play, gh=gh)  # and never a second one
    assert not gh.writes and len(play.did("commit")) == 1


def test_resumed_and_no_vitals_ever_is_not_stuck():
    play, gh, fake = staged(0.2), FakeGitHub(), FakeVitals(end=date(2026, 11, 1))
    number = seen(gh, 20, 300)
    gh.add_comment(number, rg.marker(745, "halted", 20), at=NOW - timedelta(hours=200))
    gh.add_comment(number, rg.marker(745, "inProgress", 20), at=NOW - timedelta(hours=120))
    out = go(play, fake, gh)  # five days after the resume was seen
    assert "**Raise** 745 from 20% to 50% (no vitals data, by time only)" in out


def test_a_halt_that_failed_on_google_play_keeps_the_hold_and_is_tried_again():
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 60)
    gh.add_comment(number, rg.marker(745, "halting", 20), at=NOW - timedelta(hours=24))
    # Still in progress and still worse: halted now, with one issue.
    out = go(play, vitals(new_crash=2.4, old_crash=0.5), gh)
    assert "First sight" not in out and "Time at 20%: 60.0 h" in out and "**Halt** 745" in out
    assert len([w for w in gh.writes if w[0] == "issue"]) == 1
    # Still in progress and the figures are fine again: the hold was not started again.
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 60)
    gh.add_comment(number, rg.marker(745, "halting", 20), at=NOW - timedelta(hours=24))
    out = go(play, vitals(new_crash=0.2, old_crash=0.5), gh)
    assert "**Raise** 745 from 20% to 50% (health OK)" in out


def test_a_halt_whose_issue_failed_and_was_resumed_is_not_halted_for_the_same_days():
    play, gh, fake = staged(0.2), FakeGitHub(), vitals(new_crash=2.4, old_crash=0.5)
    seen(gh, 20, 5)

    def fail_the_issue(title, body, labels, assign=False):
        raise pp.PromoteError("POST /repos/o/r/issues: HTTP 502: no details")

    gh.create_issue = fail_the_issue
    with pytest.raises(pp.CommitError):
        go(play, fake, gh)
    play.tracks["production"][0]["status"] = "inProgress"  # the owner resumes before the next run
    out = go(play, fake, gh)
    assert "First sight of 745 at 20%" in out and "**Halt**" not in out
    assert len(play.did("commit")) == 1


def test_a_halt_the_guard_gave_up_does_not_make_a_later_manual_halt_the_guards():
    play, gh = staged(0.2, "halted"), FakeGitHub()
    number = seen(gh, 20, 200)
    gh.add_comment(number, rg.marker(745, "halting", 20), at=NOW - timedelta(hours=72))
    # The halt failed, and the next run saw the release in progress with better figures.
    gh.add_comment(number, rg.marker(745, "inProgress", 50), at=NOW - timedelta(hours=40))
    out = go(play, gh=gh)
    assert "Opened the missing issue" not in out
    assert not [w for w in gh.writes if w[0] == "issue"]
    assert "Seen halted at 20%" in gh.notes[number][-1]["body"]


def test_a_missing_halt_issue_is_opened_however_late_the_next_run_is():
    play, gh = staged(0.2, "halted"), FakeGitHub()
    number = seen(gh, 20, 200)
    gh.add_comment(number, rg.marker(745, "halting", 20), at=NOW - timedelta(hours=30))
    gh.add_comment(number, rg.marker(745, "halted", 20), at=NOW - timedelta(hours=30))
    # An older issue of an earlier halt of this release does not count.
    gh.add_issue("old", label=rg.HALT_LABEL, at=NOW - timedelta(hours=90), state="closed")
    gh.items[-1]["title"] = "Release halted: 745 at 20%"
    out = go(play, gh=gh)
    assert "Opened the missing issue" in out
    assert len([w for w in gh.writes if w[0] == "issue"]) == 1


def test_a_halt_issue_that_exists_is_not_opened_twice():
    play, gh = staged(0.2, "halted"), FakeGitHub()
    number = seen(gh, 20, 30)
    gh.add_comment(number, rg.marker(745, "halting", 20), at=NOW - timedelta(hours=24))
    gh.add_issue("halted", label=rg.HALT_LABEL, at=NOW - timedelta(hours=24))
    gh.items[-1]["title"] = "Release halted: 745 at 20%"
    go(play, gh=gh)
    assert not [w for w in gh.writes if w[0] == "issue"]
    assert "Seen halted at 20%" in gh.notes[number][-1]["body"]


def test_a_dry_run_after_a_resume_shows_what_the_real_run_would_do():
    play, gh, fake = staged(0.2), FakeGitHub(), vitals(new_crash=5.0, old_crash=0.2)
    number = seen(gh, 20, 200)
    gh.add_comment(number, rg.marker(745, "halted", 20), at=NOW - timedelta(hours=100))
    out = go(play, fake, gh, dry_run=True)
    assert "**Halt**" not in out and "asked from 2026-11-21" in out and not gh.writes


def test_a_halt_goes_ahead_when_github_cannot_be_written(capsys):
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 5)
    gh.fail_writes = True
    # The release is halted all the same; the run fails because nothing could be noted.
    with pytest.raises(pp.CommitError, match="Google Play was changed"):
        go(play, vitals(new_crash=2.4, old_crash=0.5), gh)
    assert play.tracks["production"][0]["status"] == "halted"
    assert "::warning title=rollout guard::The log could not be written" in capsys.readouterr().out


def test_a_halted_release_without_a_fraction_is_left_alone_not_an_error():
    play, gh = FakePlay([rel(745, "2.4.0", "halted"), rel(738, "738 (2.3.0)")]), FakeGitHub()
    out = go(play, gh=gh)
    assert "The guard never resumes or raises a halted release" in out
    assert not play.did("update") and not play.did("commit")


def test_a_newer_version_gets_a_log_of_its_own_and_the_old_one_is_closed_when_done():
    gh = FakeGitHub()
    old = seen(gh, 50, 300, code=745)  # 2.4.0 was replaced at 50% by 2.4.1
    play = FakePlay([rel(790, "2.4.1", "inProgress", 0.2), rel(738, "738 (2.3.0)")])
    out = go(play, gh=gh)
    assert "First sight of 790 at 20%" in out and not play.did("commit")
    (issue,) = [w for w in gh.writes if w[0] == "issue"]
    assert issue[1] == "Production rollout: 2.4.1 (790)"
    assert rg.read_log(gh, 745).number == old and rg.read_log(gh, 790).number != old
    done = FakePlay([rel(790, "2.4.1")])
    out = go(done, gh=gh)
    assert (
        "Closed the log of 745" in out and "is no longer on production" in gh.notes[old][-1]["body"]
    )
    assert all(i["state"] == "closed" for i in gh.items)


# --- states the guard leaves alone ---------------------------------------------------------


def test_a_halted_release_is_never_resumed_or_raised():
    play, gh = staged(0.2, "halted"), FakeGitHub()
    number = seen(gh, 20, 500)  # long past the hold
    out = go(play, vitals(new_crash=0.1, old_crash=0.5), gh)
    assert "is halted. The guard never resumes or raises a halted release" in out
    assert not play.did("update") and not play.did("commit")
    assert play.tracks["production"][0]["status"] == "halted"
    assert rg.marker(745, "halted", 20) in gh.notes[number][0]["body"]
    gh.writes.clear()
    go(play, gh=gh)  # the next day: still nothing, and no second note
    assert not gh.writes and not play.did("commit")


def test_resumed_by_hand_the_hold_starts_again():
    play, gh = staged(0.2), FakeGitHub()
    number = seen(gh, 20, 500)
    gh.add_comment(number, rg.marker(745, "halted", 20), at=NOW - timedelta(hours=30))
    out = go(play, gh=gh)
    assert "First sight of 745 at 20%" in out and "**Wait:** about 47.0 h more" in out
    assert not play.did("commit")


def test_completed_or_no_release_does_nothing_and_closes_old_logs():
    play, gh = FakePlay([rel(745, "2.4.0")]), FakeGitHub()
    number = seen(gh, 50, 100)
    out = go(play, gh=gh)
    assert "**Nothing to do:** no staged rollout" in out and not play.did("update")
    assert gh.items[number - 1]["state"] == "closed"
    assert "Closed the log of 745" in out and "is complete (100%)" in gh.notes[number][0]["body"]
    assert "Nothing to do" in go(FakePlay([]))


def test_two_staged_releases_are_refused():
    play = FakePlay([rel(745, "2.4.0", "inProgress", 0.2), rel(746, "2.4.1", "halted", 0.1)])
    with pytest.raises(pp.PromoteError, match="more than one staged versionCode"):
        go(play)


# --- dry run -------------------------------------------------------------------------------


def test_dry_run_commits_nothing_and_writes_nothing():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 49)
    out = go(play, gh=gh, dry_run=True)
    assert "## Rollout guard (dry run)" in out and "**Raise** 745 from 20% to 50%" in out
    assert play.did("validate") and not play.did("commit") and not gh.writes
    assert "Nothing changed for users" in out
    assert play.tracks["production"][0]["userFraction"] == 0.2


def test_dry_run_of_a_halt_and_of_a_first_sight_write_nothing():
    play, gh = staged(0.2), FakeGitHub()
    out = go(play, vitals(new_crash=5.0, old_crash=0.2), gh, dry_run=True)
    assert "Dry run: the clock is not started" in out and "**Halt** 745" in out
    assert "no `release-halted` issue was opened" in out
    assert not play.did("commit") and not gh.writes


# --- configuration -------------------------------------------------------------------------


def test_defaults_and_repository_variables():
    assert rg.read_config({}) == rg.Config(48.0, 500.0, 1.5, 1.09, 0.47)
    cfg = rg.read_config({"ROLLOUT_HOLD_HOURS": " 72 ", "ROLLOUT_CRASH_BAD_PERCENT": "2"})
    assert cfg.hold_hours == 72 and cfg.crash_bad == 2 and cfg.anr_bad == 0.47
    for bad in ("soon", "-1", "nan", "1e9"):
        with pytest.raises(pp.PromoteError, match="ROLLOUT_HOLD_HOURS must be a number"):
            rg.read_config({"ROLLOUT_HOLD_HOURS": bad})
    with pytest.raises(pp.PromoteError, match="ROLLOUT_WORSE_FACTOR"):
        rg.read_config({"ROLLOUT_WORSE_FACTOR": "0.5"})


def test_a_longer_hold_from_the_variable_waits():
    play, gh = staged(0.2), FakeGitHub()
    seen(gh, 20, 49)
    out = go(play, gh=gh, cfg=rg.read_config({"ROLLOUT_HOLD_HOURS": "72"}))
    assert "**Wait:** about 22.0 h more" in out and not play.did("commit")


# --- the HTTP side: Reporting API and GitHub -----------------------------------------------


class FakeHttp:
    def __init__(self, answers: list):
        self.answers = list(answers)
        self.requests: list = []

    def __call__(self, request):
        self.requests.append(request)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return io.BytesIO(json.dumps(answer).encode())


def metric_row(code, rate, users, day=18) -> dict:
    return {
        "aggregationPeriod": "DAILY",
        "startTime": {"year": 2026, "month": 11, "day": day},
        "dimensions": [{"dimension": "versionCode", "int64Value": str(code)}],
        "metrics": [
            {"metric": "userPerceivedCrashRate", "decimalValue": {"value": rate}},
            {"metric": "distinctUsers", "decimalValue": {"value": users}},
        ],
    }


def test_vitals_api_asks_daily_rows_per_version_code_and_reads_shares_as_percent():
    http = FakeHttp(
        [
            {"rows": [metric_row(745, "0.0125", "400")], "nextPageToken": "p2"},
            {"rows": [metric_row(745, "0.02", "600", 19), metric_row(738, "0.5", "9000")]},
        ]
    )
    api = rg.VitalsApi("tok", opener=http)
    rows = api.daily(
        "crashRateMetricSet", "userPerceivedCrashRate", 745, date(2026, 11, 17), date(2026, 11, 20)
    )
    assert rows == [(1.25, 400.0), (2.0, 600.0)]  # the row of 738 is not counted
    first, second = http.requests
    assert first.full_url == (
        "https://playdeveloperreporting.googleapis.com/v1beta1/apps/"
        "com.tursinalabs.dailylah/crashRateMetricSet:query"
    )
    assert first.get_method() == "POST" and first.get_header("Authorization") == "Bearer tok"
    body = json.loads(first.data)
    assert body == {
        "timelineSpec": {
            "aggregationPeriod": "DAILY",
            "startTime": {
                "year": 2026,
                "month": 11,
                "day": 17,
                "timeZone": {"id": "America/Los_Angeles"},
            },
            "endTime": {
                "year": 2026,
                "month": 11,
                "day": 20,
                "timeZone": {"id": "America/Los_Angeles"},
            },
        },
        "dimensions": ["versionCode"],
        "metrics": ["userPerceivedCrashRate", "distinctUsers"],
        "filter": "versionCode = 745",
        "pageSize": 1000,
    }
    assert json.loads(second.data)["pageToken"] == "p2"


def test_vitals_api_reads_the_freshness_of_daily_data():
    day = {"year": 2026, "month": 11, "day": 19, "timeZone": {"id": "America/Los_Angeles"}}
    http = FakeHttp(
        [
            {
                "freshnessInfo": {
                    "freshnesses": [
                        {"aggregationPeriod": "HOURLY", "latestEndTime": {"year": 2026}},
                        {"aggregationPeriod": "DAILY", "latestEndTime": day},
                    ]
                }
            },
            {"name": "apps/x/anrRateMetricSet"},
        ]
    )
    api = rg.VitalsApi("tok", opener=http)
    assert api.latest_day_end("crashRateMetricSet") == date(2026, 11, 19)
    assert api.latest_day_end("anrRateMetricSet") is None
    assert http.requests[0].get_method() == "GET"
    assert http.requests[0].full_url.endswith("/com.tursinalabs.dailylah/crashRateMetricSet")


@pytest.mark.parametrize("rate", ["1.2", "-0.1", "abc"])
def test_a_rate_that_is_not_a_share_of_users_is_an_error_not_a_decision(rate):
    api = rg.VitalsApi("tok", opener=FakeHttp([{"rows": [metric_row(745, rate, "400")]}]))
    with pytest.raises(pp.PromoteError, match="not a share of users|cannot read"):
        api.daily("crashRateMetricSet", "userPerceivedCrashRate", 745, date(2026, 11, 17), NOW)


def test_a_reporting_api_http_error_is_a_clean_error():
    error = urllib.error.HTTPError(
        "https://x", 403, "Forbidden", {}, io.BytesIO(b'{"error": {"message": "API not enabled"}}')
    )
    api = rg.VitalsApi("SECRET-TOKEN", opener=FakeHttp([error]))
    with pytest.raises(pp.PromoteError) as e:
        api.latest_day_end("crashRateMetricSet")
    assert "HTTP 403: API not enabled" in str(e.value) and "SECRET-TOKEN" not in str(e.value)


def test_github_calls_the_issue_endpoints_of_this_repository():
    opened = {"number": 9, "labels": [{"name": "release-halted"}]}
    http = FakeHttp([[{"number": 3}, {"number": 2, "pull_request": {}}], {}, opened, {}, {}])
    gh = rg.GitHub("ghs_tok", "hndrwn-dk/dailylah", opener=http)
    assert gh.issues("release-rollout") == [{"number": 3}]
    assert gh.create_issue("T", "B", ["release-halted"], assign=True) == 9
    gh.comment(9, "note")
    gh.close(9)
    listed, label, created, commented, closed = http.requests
    base = "https://api.github.com/repos/hndrwn-dk/dailylah"
    assert label.full_url == f"{base}/labels" and json.loads(label.data) == {
        "name": "release-halted"
    }
    assert listed.full_url == (
        f"{base}/issues?labels=release-rollout&state=all&sort=created&direction=desc"
        "&per_page=100&page=1"
    )
    assert listed.get_header("Authorization") == "Bearer ghs_tok"
    assert created.full_url == f"{base}/issues" and json.loads(created.data) == {
        "title": "T",
        "body": "B",
        "labels": ["release-halted"],
        "assignees": ["hndrwn-dk"],
    }
    assert commented.full_url == f"{base}/issues/9/comments"
    assert closed.get_method() == "PATCH" and json.loads(closed.data) == {"state": "closed"}
    with pytest.raises(pp.PromoteError, match="not owner/name"):
        rg.GitHub("t", "../../orgs/x")


def _http_error(code: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError("https://x", code, "x", {}, io.BytesIO(b"{}"))


def test_a_label_that_exists_is_fine_and_an_issue_without_its_label_is_an_error():
    opened = {"number": 4, "labels": [{"name": "release-rollout"}]}
    gh = rg.GitHub("t", "o/r", opener=FakeHttp([_http_error(422), opened]))
    assert gh.create_issue("T", "B", ["release-rollout"]) == 4
    # GitHub dropped the label: the guard could never find this log again.
    gh = rg.GitHub("t", "o/r", opener=FakeHttp([{}, {"number": 5, "labels": []}]))
    with pytest.raises(pp.PromoteError, match="issue 5 without the label release-rollout"):
        gh.create_issue("T", "B", ["release-rollout"])
    gh = rg.GitHub("t", "o/r", opener=FakeHttp([_http_error(403)]))
    with pytest.raises(pp.PromoteError, match="HTTP 403"):
        gh.create_issue("T", "B", ["release-rollout"])


def test_a_release_name_cannot_write_a_marker_or_markdown_into_the_log():
    play, gh = FakePlay([rel(745, "x <!-- rollout-guard code=1 -->\n# h", "inProgress", 0.2)]), None
    gh = FakeGitHub()
    go(play, gh=gh)
    (issue,) = [w for w in gh.writes if w[0] == "issue"]
    assert "<!--" not in issue[1] and "\n" not in issue[1]
    assert rg.MARK.findall(issue[2]) == [("745", "inProgress", "20")]


# --- main: kill switch, secrets, summary -----------------------------------------------------


@pytest.fixture
def cli(tmp_path, monkeypatch, capsys):
    summary = tmp_path / "summary.md"
    play, gh, fake = staged(0.2), FakeGitHub(), FakeVitals()
    # main() reads the real clock: first seen 49 hours before this test runs.
    gh.add_issue(rg.marker(745, "inProgress", 20), at=datetime.now(UTC) - timedelta(hours=49))
    monkeypatch.setenv("PLAY_SERVICE_ACCOUNT_JSON", '{"k": "SECRET-KEY-TEXT"}')
    monkeypatch.setenv("PLAY_TESTING_ACCOUNT", "testing@p.iam.example")
    monkeypatch.setenv("GITHUB_TOKEN", "ghs_SECRET")
    monkeypatch.setenv("GITHUB_REPOSITORY", "hndrwn-dk/dailylah")
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    monkeypatch.setenv("AUTO_ROLLOUT", "on")
    for name in [v[0] for v in rg._VARIABLES]:
        monkeypatch.delenv(name, raising=False)
    scopes: list[str] = []
    monkeypatch.setattr(pp, "access_token", lambda account, scope: scopes.append(scope) or "tok")
    monkeypatch.setattr(pp, "PlayApi", lambda token: play)
    monkeypatch.setattr(rg, "VitalsApi", lambda token: fake)
    monkeypatch.setattr(rg, "GitHub", lambda token, repo: gh)

    def run(*args: str) -> tuple[int, str, str]:
        code = rg.main(list(args))
        text = summary.read_text(encoding="utf-8") if summary.exists() else ""
        return code, text, capsys.readouterr().out

    run.play, run.gh, run.vitals, run.scopes = play, gh, fake, scopes
    return run


def test_main_raises_and_writes_the_summary(cli):
    code, summary, printed = cli()
    assert code == 0 and cli.play.did("commit")
    assert "## Rollout guard" in summary and "### Before" in summary
    assert "| production | 745 | 2.4.0 | inProgress | 20% |" in summary
    assert "UNKNOWN, no vitals data" in summary and "### After (committed)" in summary
    assert "| production | 745 | 2.4.0 | inProgress | 50% |" in summary
    assert "SECRET" not in printed + summary
    # One token for both Google APIs.
    assert cli.scopes == [
        "https://www.googleapis.com/auth/androidpublisher "
        "https://www.googleapis.com/auth/playdeveloperreporting"
    ]


@pytest.mark.parametrize("value", ["", "off", "ON", "true", "on "])
def test_main_does_nothing_while_auto_rollout_is_not_on(cli, monkeypatch, value):
    monkeypatch.setenv("AUTO_ROLLOUT", value)
    if value == "on ":  # surrounding spaces are forgiven, nothing else
        assert cli()[0] == 0 and cli.play.did("commit")
        return
    code, summary, _ = cli()
    assert code == 0 and "AUTO_ROLLOUT is not `on`" in summary
    assert not cli.play.calls and not cli.gh.writes and not cli.scopes


def test_the_promote_switch_does_not_start_the_guard(cli, monkeypatch):
    monkeypatch.delenv("AUTO_ROLLOUT")
    monkeypatch.setenv("AUTO_PROMOTE", "on")
    code, summary, _ = cli()
    assert code == 0 and "AUTO_ROLLOUT is not `on`" in summary and not cli.play.calls


def test_main_dry_run_works_while_auto_rollout_is_off(cli, monkeypatch):
    monkeypatch.delenv("AUTO_ROLLOUT")
    code, summary, _ = cli("--dry-run")
    assert code == 0 and "## Rollout guard (dry run)" in summary
    assert not cli.play.did("commit") and not cli.gh.writes


def test_main_fails_on_an_api_error_and_says_nothing_changed(cli):
    cli.vitals.fail = True
    code, summary, printed = cli()
    assert code == 1 and "**Failed:** GET /v1beta1/apps/x/crashRateMetricSet: HTTP 403" in summary
    assert "Nothing was changed on Google Play by this run." in summary
    assert "::error title=rollout guard::" in printed and not cli.play.did("commit")


def test_main_after_a_commit_does_not_say_nothing_changed(cli):
    cli.gh.fail_writes = True
    code, summary, _ = cli()
    assert code == 1 and "Google Play was changed, but" in summary
    assert "Nothing was changed" not in summary


def test_main_refuses_a_bad_variable_the_testing_key_and_missing_secrets(cli, monkeypatch):
    monkeypatch.setenv("ROLLOUT_HOLD_HOURS", "two days")
    code, summary, _ = cli()
    assert code == 1 and "ROLLOUT_HOLD_HOURS must be a number" in summary and not cli.play.calls
    monkeypatch.delenv("ROLLOUT_HOLD_HOURS")
    monkeypatch.delenv("GITHUB_TOKEN")
    assert cli()[0] == 1 and not cli.play.calls
    monkeypatch.setenv("GITHUB_TOKEN", "t")
    monkeypatch.setenv(
        "PLAY_SERVICE_ACCOUNT_JSON", '{"type": "service_account", "client_email": "t@x"}'
    )
    monkeypatch.setenv("PLAY_TESTING_ACCOUNT", "t@x")
    code, summary, _ = cli()
    assert code == 1 and "testing service account" in summary and not cli.play.calls


# --- the workflow that runs it ---------------------------------------------------------------


def test_the_guard_workflow_keeps_the_key_in_play_rollout_and_cannot_run_for_a_pr():
    text = (ROOT / ".github" / "workflows" / "rollout-guard.yml").read_text(encoding="utf-8")
    workflow = yaml.safe_load(text)
    triggers = workflow[True]  # YAML reads `on` as True
    assert sorted(triggers) == ["schedule", "workflow_dispatch"]
    assert list(triggers["workflow_dispatch"]["inputs"]) == ["dry_run"]
    assert triggers["workflow_dispatch"]["inputs"]["dry_run"]["default"] is False
    assert workflow["permissions"] == {}
    assert workflow["concurrency"] == {"group": "play-promote", "cancel-in-progress": False}
    (job,) = workflow["jobs"].values()
    # An environment of its own (no reviewer): the first 20% and the manual workflow keep theirs.
    assert job["environment"] == "play-rollout"
    assert job["permissions"] == {"contents": "read", "issues": "write"}
    # Its own switch: a scheduled run does not even start the job while AUTO_ROLLOUT is off.
    assert job["if"] == (
        "vars.AUTO_ROLLOUT == 'on' || (github.event_name == 'workflow_dispatch' && inputs.dry_run)"
    )
    others = {
        name: yaml.safe_load((ROOT / ".github" / "workflows" / name).read_text())
        for name in ("app.yml", "promote.yml")
    }
    assert "play-rollout" not in json.dumps(others) and "AUTO_ROLLOUT" not in json.dumps(others)
    assert "refs/heads/main" in job["steps"][0]["run"]
    # Four runs a day and a 6-hour hold unless the variable says otherwise: 100% within a day.
    assert triggers["schedule"] == [{"cron": "17 2,8,14,20 * * *"}]
    env = job["steps"][-1]["env"]
    assert env["ROLLOUT_HOLD_HOURS"] == "${{ vars.ROLLOUT_HOLD_HOURS || '6' }}"
    assert rg.read_config({"ROLLOUT_HOLD_HOURS": "6"}).hold_hours == 6.0
    with_secret = [s for s in job["steps"] if "secrets." in json.dumps(s)]
    assert len(with_secret) == 1 and "rollout_guard.py" in with_secret[0]["run"]
    assert text.count("secrets.") == 1 and text.count("github.token") == 1
    assert "github.token" in json.dumps(with_secret[0]["env"])
    assert with_secret[0]["env"]["AUTO_ROLLOUT"] == "${{ vars.AUTO_ROLLOUT }}"
    assert "AUTO_PROMOTE" not in text
    uses = [s["uses"] for s in job["steps"] if "uses" in s]
    assert all(u.startswith("actions/checkout@") and len(u.split("@")[1]) == 40 for u in uses)
    assert "pip" not in text
