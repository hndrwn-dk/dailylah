"""scripts/play_promote.py with a fake Google Play: what goes to production, and what is refused."""

import base64
import copy
import importlib.util
import io
import json
import shutil
import subprocess
import urllib.error
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("play_promote", ROOT / "scripts" / "play_promote.py")
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)

NOTES = [{"language": "en-US", "text": "What is new in 2.4.0."}]


def rel(code: int, name: str, status: str = "completed", fraction: float | None = None) -> dict:
    release = {"name": name, "versionCodes": [str(code)], "status": status}
    if fraction is not None:
        release["userFraction"] = fraction
    return release


class FakePlay:
    """Tracks in memory. An edit changes them only when it is committed, like Google Play."""

    def __init__(self, alpha: list[dict], production: list[dict]):
        self.tracks = {"alpha": alpha, "production": production}
        self.calls: list[tuple] = []
        self.pending: dict[str, dict] = {}
        self.fail_commit = False
        self.lose_commit = False

    def create_edit(self) -> str:
        edit = f"edit{len(self.pending) + 1}"
        self.pending[edit] = {}
        self.calls.append(("create", edit))
        return edit

    def get_track(self, edit: str, track: str) -> list[dict]:
        self.calls.append(("get", edit, track))
        return copy.deepcopy(self.pending[edit].get(track, self.tracks[track]))

    def update_track(self, edit: str, track: str, releases: list[dict]) -> None:
        self.calls.append(("update", edit, track, copy.deepcopy(releases)))
        self.pending[edit][track] = copy.deepcopy(releases)

    def validate_edit(self, edit: str) -> None:
        self.calls.append(("validate", edit))

    def commit_edit(self, edit: str) -> None:
        self.calls.append(("commit", edit))
        if self.fail_commit:
            raise pp.PromoteError(
                "POST /edits/x:commit: HTTP 403: The caller does not have permission"
            )
        if self.lose_commit:
            return
        for track, releases in self.pending.pop(edit).items():
            # A staged release keeps the last full release next to it for everyone else.
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


def play(production: list[dict] | None = None, alpha: list[dict] | None = None) -> FakePlay:
    return FakePlay(
        alpha if alpha is not None else [rel(745, "2.4.0")],
        production if production is not None else [rel(738, "738 (2.3.0)")],
    )


def promote(api: FakePlay, percent: int = 20, version: str = "2.4.0", **kw) -> list[str]:
    return pp.run(api, "promote", version=version, percent=percent, notes=NOTES, **kw)


# --- promote ---------------------------------------------------------------------------


def test_promote_puts_the_alpha_version_code_on_production_at_the_fraction():
    api = play()
    out = "\n".join(promote(api, 20))
    (update,) = api.did("update")
    assert update[2] == "production"
    assert update[3] == [
        {
            "name": "2.4.0",
            "versionCodes": ["745"],
            "releaseNotes": NOTES,
            "status": "inProgress",
            "userFraction": 0.2,
        }
    ]
    assert len(api.did("commit")) == 1 and not api.did("validate")
    assert api.tracks["production"][0]["versionCodes"] == ["745"]
    assert api.tracks["production"][1] == rel(738, "738 (2.3.0)")  # still there for the other 80%
    assert api.tracks["alpha"] == [rel(745, "2.4.0")]  # alpha is only read
    # Before and after, with versionCode, name, status and fraction.
    assert "### Before" in out and "### After (committed)" in out
    assert "| alpha | 745 | 2.4.0 | completed | 100% |" in out
    assert "| production | 738 | 738 (2.3.0) | completed | 100% |" in out
    assert "| production | 745 | 2.4.0 | inProgress | 20% |" in out
    assert not api.pending  # no edit left open


def test_promote_at_100_is_completed_without_a_fraction():
    api = play()
    promote(api, 100)
    (release,) = api.did("update")[0][3]
    assert release["status"] == "completed" and "userFraction" not in release
    assert api.tracks["production"] == [release]


def test_promote_accepts_the_play_console_release_name():
    api = play(alpha=[rel(745, "745 (2.4.0)")])
    promote(api)
    assert api.did("update")[0][3][0]["versionCodes"] == ["745"]


def test_promote_refuses_a_version_that_is_not_on_alpha():
    api = play(alpha=[rel(730, "2.2.0")])
    with pytest.raises(pp.PromoteError, match=r"2\.4\.0 is not on closed testing.*730 \(2\.2\.0"):
        promote(api)
    assert not api.did("update") and not api.did("commit")
    assert api.did("delete") and not api.pending
    assert api.tracks["production"] == [rel(738, "738 (2.3.0)")]


def test_promote_does_not_match_a_longer_or_other_name():
    api = play(alpha=[rel(745, "12.4.0"), rel(746, "2.4.0-rc"), rel(747, "745 (2.4.0)")])
    with pytest.raises(pp.PromoteError, match="not on closed testing"):
        promote(api)


def test_promote_refuses_a_version_code_older_than_production():
    api = play(alpha=[rel(700, "2.4.0")])
    with pytest.raises(pp.PromoteError, match="700 .*is older than production.*738"):
        promote(api)
    assert not api.did("update") and not api.did("commit")


def test_promote_compares_with_a_staged_production_release_too():
    api = play(
        production=[rel(750, "2.5.0", "inProgress", 0.1), rel(738, "2.3.0")],
        alpha=[rel(745, "2.4.0")],
    )
    with pytest.raises(pp.PromoteError, match="older than production"):
        promote(api)


def test_promote_refuses_what_production_already_has():
    api = play(production=[rel(745, "2.4.0", "inProgress", 0.2), rel(738, "2.3.0")])
    with pytest.raises(pp.PromoteError, match="already on production.*rollout, halt or resume"):
        promote(api)
    assert not api.did("update")


def test_promote_refuses_an_alpha_draft_and_two_alpha_releases_of_one_version():
    with pytest.raises(pp.PromoteError, match="is draft, not completed"):
        promote(play(alpha=[rel(745, "2.4.0", "draft")]))
    with pytest.raises(pp.PromoteError, match="2 releases named 2.4.0"):
        promote(play(alpha=[rel(745, "2.4.0"), rel(746, "746 (2.4.0)")]))


def test_promote_over_an_unfinished_rollout_says_so():
    api = play(production=[rel(740, "2.3.1", "halted", 0.1), rel(738, "2.3.0")])
    out = "\n".join(promote(api, 10))
    assert "replaces the unfinished staged release 740 (2.3.1, halted at 10%)" in out
    assert [r["versionCodes"] for r in api.tracks["production"]] == [["745"], ["738"]]


def test_promote_to_an_empty_production_track():
    api = play(production=[])
    out = "\n".join(promote(api, 50))
    assert "| production | – | – | no release | – |" in out
    assert api.tracks["production"][0]["userFraction"] == 0.5


# --- rollout, halt, resume -------------------------------------------------------------

STAGED = [rel(745, "2.4.0", "inProgress", 0.2), rel(738, "2.3.0")]


def test_rollout_raises_the_fraction_and_keeps_the_release_as_it_was():
    staged = copy.deepcopy(STAGED)
    staged[0]["releaseNotes"] = NOTES
    api = play(production=staged)
    out = "\n".join(pp.run(api, "rollout", percent=50))
    assert api.did("update")[0][3] == [
        {
            "name": "2.4.0",
            "versionCodes": ["745"],
            "releaseNotes": NOTES,
            "status": "inProgress",
            "userFraction": 0.5,
        }
    ]
    assert "from 20% to 50%" in out
    assert "| production | 745 | 2.4.0 | inProgress | 50% |" in out
    assert not [c for c in api.calls if c[0] == "get" and c[2] == "alpha"]


def test_rollout_to_100_completes_the_release():
    api = play(production=copy.deepcopy(STAGED))
    pp.run(api, "rollout", percent=100)
    assert api.tracks["production"] == [rel(745, "2.4.0")]


@pytest.mark.parametrize("percent", [10, 20])
def test_rollout_never_lowers_or_repeats_the_fraction(percent):
    api = play(production=copy.deepcopy(STAGED))
    with pytest.raises(pp.PromoteError, match="already at 20%"):
        pp.run(api, "rollout", percent=percent)
    assert not api.did("update")


def test_rollout_needs_a_release_in_progress():
    with pytest.raises(pp.PromoteError, match="No staged rollout is in progress"):
        pp.run(play(), "rollout", percent=50)
    halted = play(production=[rel(745, "2.4.0", "halted", 0.2), rel(738, "2.3.0")])
    with pytest.raises(pp.PromoteError, match="Run action resume first"):
        pp.run(halted, "rollout", percent=50)


def test_halt_then_resume_keep_the_fraction():
    api = play(production=copy.deepcopy(STAGED))
    out = "\n".join(pp.run(api, "halt"))
    assert api.tracks["production"][0] == rel(745, "2.4.0", "halted", 0.2)
    assert "| production | 745 | 2.4.0 | halted | 20% |" in out
    out = "\n".join(pp.run(api, "resume", percent=100))  # the percent input is not used
    assert api.tracks["production"][0] == rel(745, "2.4.0", "inProgress", 0.2)
    assert "Resume 745 (2.4.0, halted at 20%) at 20%" in out


def test_halt_and_resume_refuse_when_there_is_nothing_to_do():
    with pytest.raises(pp.PromoteError, match="nothing to halt"):
        pp.run(play(), "halt")
    with pytest.raises(pp.PromoteError, match="nothing to resume"):
        pp.run(play(production=copy.deepcopy(STAGED)), "resume")
    with pytest.raises(pp.PromoteError, match="nothing to halt"):
        pp.run(play(production=[rel(745, "2.4.0", "halted", 0.2)]), "halt")


def test_two_staged_releases_are_refused():
    api = play(production=[rel(745, "2.4.0", "inProgress", 0.2), rel(744, "x", "inProgress", 0.1)])
    with pytest.raises(pp.PromoteError, match="2 releases with status inProgress"):
        pp.run(api, "halt")


# --- dry run and failures --------------------------------------------------------------


def test_dry_run_validates_and_commits_nothing():
    api = play()
    out = "\n".join(promote(api, 20, dry_run=True))
    assert api.did("update") and api.did("validate") and not api.did("commit")
    assert api.did("delete") and not api.pending
    assert api.tracks["production"] == [rel(738, "738 (2.3.0)")]
    assert "(dry run)" in out and "### After (planned, not committed)" in out
    assert "| production | 745 | 2.4.0 | inProgress | 20% |" in out
    assert "Nothing changed for users" in out


def test_dry_run_still_refuses():
    api = play(alpha=[])
    out: list[str] = []
    with pytest.raises(pp.PromoteError, match="not on closed testing"):
        promote(api, dry_run=True, out=out)
    assert "| production | 738 | 738 (2.3.0) | completed | 100% |" in out  # state is shown first
    assert not api.did("update") and not api.did("validate")


def test_a_failed_commit_is_reported_as_one():
    api = play()
    api.fail_commit = True
    with pytest.raises(pp.CommitError, match="commit did not go through.*permission"):
        promote(api)
    assert not api.did("delete")  # an edit whose commit was sent is left alone


def test_a_commit_that_changed_nothing_fails():
    api = play()
    api.lose_commit = True
    with pytest.raises(pp.CommitError, match="does not show the planned release"):
        promote(api)


def test_a_failed_read_back_never_says_nothing_changed():
    api = play()
    create = api.create_edit

    def create_once():
        if api.did("commit"):
            raise pp.PromoteError("POST /edits: HTTP 503: backend error")
        return create()

    api.create_edit = create_once
    with pytest.raises(pp.CommitError, match="committed, but reading it back failed"):
        promote(api)
    assert api.tracks["production"][0]["versionCodes"] == ["745"]


def test_a_cut_connection_is_a_clean_error():
    def cut(request):
        raise ConnectionResetError("reset by peer")

    with pytest.raises(pp.PromoteError, match="ConnectionResetError"):
        pp.PlayApi("tok", opener=cut).create_edit()

    def closed(request):
        raise pp.http.client.RemoteDisconnected("closed")

    with pytest.raises(pp.PromoteError, match="RemoteDisconnected"):
        pp.PlayApi("tok", opener=closed).commit_edit("e1")


def test_release_notes_are_checked(tmp_path):
    notes = tmp_path / "whatsnew-en-US"
    notes.write_text("  New things.\n", encoding="utf-8")
    assert pp.read_notes(notes) == [{"language": "en-US", "text": "New things."}]
    notes.write_text("x" * 501, encoding="utf-8")
    with pytest.raises(pp.PromoteError, match="501 characters"):
        pp.read_notes(notes)
    notes.write_text("\n", encoding="utf-8")
    with pytest.raises(pp.PromoteError, match="empty"):
        pp.read_notes(notes)
    with pytest.raises(pp.PromoteError, match="No readable release notes"):
        pp.read_notes(tmp_path / "missing")


def test_a_release_name_cannot_break_the_summary_table():
    row = pp.table("production", [rel(1, "x | y\n<b>[link](http://e)")])[2]
    assert row.count("|") == 6 and "<" not in row and "[" not in row


# --- HTTP and the token request --------------------------------------------------------


class FakeHttp:
    def __init__(self, answers: list):
        self.answers = answers
        self.requests: list = []

    def __call__(self, request):
        self.requests.append(request)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return io.BytesIO(json.dumps(answer).encode())


def test_play_api_calls_the_edit_endpoints_with_the_token():
    http = FakeHttp([{"id": "e1"}, {"track": "production"}, {}, {}, {}, {}])
    api = pp.PlayApi("tok", opener=http)
    edit = api.create_edit()
    assert api.get_track(edit, "production") == []  # a track with no release has no list
    api.update_track(edit, "production", [rel(745, "2.4.0")])
    api.validate_edit(edit)
    api.commit_edit(edit)
    api.delete_edit(edit)
    base = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/"
        "com.tursinalabs.dailylah/edits"
    )
    assert [(r.get_method(), r.full_url) for r in http.requests] == [
        ("POST", base),
        ("GET", f"{base}/e1/tracks/production"),
        ("PUT", f"{base}/e1/tracks/production"),
        ("POST", f"{base}/e1:validate"),
        ("POST", f"{base}/e1:commit"),
        ("DELETE", f"{base}/e1"),
    ]
    assert all(r.get_header("Authorization") == "Bearer tok" for r in http.requests)
    assert json.loads(http.requests[2].data) == {
        "track": "production",
        "releases": [rel(745, "2.4.0")],
    }


def test_an_api_error_shows_googles_message_and_no_token():
    body = json.dumps({"error": {"code": 403, "message": "The caller does not have permission"}})
    error = urllib.error.HTTPError("https://x", 403, "Forbidden", {}, io.BytesIO(body.encode()))
    api = pp.PlayApi("secret-token", opener=FakeHttp([error]))
    with pytest.raises(pp.PromoteError) as e:
        api.create_edit()
    assert "HTTP 403: The caller does not have permission" in str(e.value)
    assert "secret-token" not in str(e.value)


def test_plain_http_is_refused():
    with pytest.raises(pp.PromoteError, match="non-HTTPS"):
        pp.call("GET", "http://androidpublisher.googleapis.com/x", token="t")


def test_redirects_are_not_followed():
    assert pp._NoRedirect().redirect_request(None, None, 302, "Found", {}, "https://e/") is None


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


@pytest.mark.skipif(shutil.which("openssl") is None, reason="needs openssl")
def test_the_token_request_is_signed_for_google_only(tmp_path):
    key = tmp_path / "key.pem"
    pub = tmp_path / "pub.pem"
    for cmd in (
        ["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"]
        + ["-out", str(key)],
        ["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(pub)],
    ):
        subprocess.run(cmd, check=True, capture_output=True)  # noqa: S603 - fixed test command
    account = {
        "type": "service_account",
        "client_email": "ci@example.iam.gserviceaccount.com",
        "private_key": key.read_text(),
        "private_key_id": "kid1",
        "token_uri": "https://evil.example/token",  # ignored: the audience is fixed
    }
    form = pp.token_request(json.dumps(account), now=1_800_000_000)
    assert form["grant_type"] == "urn:ietf:params:oauth:grant-type:jwt-bearer"
    header, claims, signature = form["assertion"].split(".")
    assert json.loads(_unb64(header)) == {"alg": "RS256", "typ": "JWT", "kid": "kid1"}
    assert json.loads(_unb64(claims)) == {
        "iss": "ci@example.iam.gserviceaccount.com",
        "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": 1_800_000_000,
        "exp": 1_800_000_600,
    }
    (tmp_path / "sig").write_bytes(_unb64(signature))
    (tmp_path / "msg").write_text(f"{header}.{claims}")
    verify = ["openssl", "dgst", "-sha256", "-verify", str(pub), "-signature"]
    verify += [str(tmp_path / "sig"), str(tmp_path / "msg")]
    subprocess.run(verify, check=True, capture_output=True)  # noqa: S603 - fixed test command


@pytest.mark.parametrize(
    "secret", ["", "not json", "[]", '{"type": "authorized_user"}', '{"type": "service_account"}']
)
def test_a_bad_key_file_is_named_without_its_content(secret):
    with pytest.raises(pp.PromoteError) as e:
        pp.token_request(secret)
    assert "not a service account key file" in str(e.value)
    assert secret == "" or secret not in str(e.value)


def test_the_production_key_must_not_be_the_testing_account():
    key = json.dumps({"type": "service_account", "client_email": "Testing@p.iam.example"})
    with pytest.raises(pp.PromoteError, match="belongs to the testing service account"):
        pp.check_account(key, " testing@p.iam.example ")
    assert pp.check_account(key, "other@p.iam.example") == []
    (warning,) = pp.check_account(key, "", dry_run=True)
    assert "PLAY_TESTING_ACCOUNT is not set" in warning
    with pytest.raises(pp.PromoteError, match="Only a dry run works without it"):
        pp.check_account(key, "")


def test_a_release_name_cannot_start_a_line_or_add_markdown():
    api = play(alpha=[rel(745, "2.4.0\n::error::x [a](http://e)")])
    with pytest.raises(pp.PromoteError) as e:
        promote(api, version="2.9.9")
    assert "\n" not in str(e.value) and "::" not in str(e.value) and "[" not in str(e.value)


def test_a_key_openssl_cannot_read_gives_no_key_material_in_the_error():
    account = {"type": "service_account", "client_email": "a@b", "private_key": "PRIVATE-STUFF"}
    with pytest.raises(pp.PromoteError) as e:
        pp.token_request(json.dumps(account))
    assert "PRIVATE-STUFF" not in str(e.value)


# --- main: arguments, summary file, exit code ------------------------------------------


@pytest.fixture
def cli(tmp_path, monkeypatch, capsys):
    notes = tmp_path / "whatsnew-en-US"
    notes.write_text("What is new in 2.4.0.\n", encoding="utf-8")
    summary = tmp_path / "summary.md"
    api = play()
    monkeypatch.setenv("PLAY_SERVICE_ACCOUNT_JSON", '{"k": "SECRET-KEY-TEXT"}')
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    monkeypatch.setenv("PLAY_TESTING_ACCOUNT", "testing@p.iam.example")
    monkeypatch.setattr(pp, "access_token", lambda account: "tok")
    monkeypatch.setattr(pp, "PlayApi", lambda token: api)

    def go(*args: str) -> tuple[int, str, str]:
        code = pp.main([*args, "--notes", str(notes)])
        text = summary.read_text(encoding="utf-8") if summary.exists() else ""
        return code, text, capsys.readouterr().out

    go.api = api
    return go


def test_main_promotes_and_writes_the_step_summary(cli):
    code, summary, printed = cli("--action", "promote", "--version", "v2.4.0", "--rollout", "20")
    assert code == 0
    assert "## Google Play production: promote" in summary
    assert "| production | 745 | 2.4.0 | inProgress | 20% |" in summary
    assert summary.strip() in printed and "SECRET-KEY-TEXT" not in printed + summary
    assert cli.api.did("commit")


def test_main_dry_run_commits_nothing(cli):
    code, summary, _ = cli("--version", "2.4.0", "--dry-run")
    assert code == 0 and "(dry run)" in summary and not cli.api.did("commit")


def test_main_fails_clearly(cli):
    code, summary, printed = cli("--version", "2.9.9")
    assert code == 1
    assert "**Failed:** Version 2.9.9 is not on closed testing" in summary
    assert "Nothing was changed on Google Play." in summary
    assert "::error title=promote::Version 2.9.9 is not on closed testing" in printed
    assert "### Before" in summary  # the state it read is still shown


def test_main_does_not_say_nothing_changed_after_a_failed_commit(cli):
    cli.api.fail_commit = True
    code, summary, _ = cli("--version", "2.4.0")
    assert code == 1 and "commit did not go through" in summary
    assert "Nothing was changed" not in summary


@pytest.mark.parametrize("version", ["", "2.4", "latest", "2.4.0; rm -rf /", "v2.4.0.1"])
def test_main_refuses_a_version_that_is_not_a_version(cli, version):
    code, summary, _ = cli("--version", version)
    assert code == 1 and "Version must look like 2.4.0" in summary
    assert not cli.api.calls


def test_main_refuses_the_testing_accounts_key(cli, monkeypatch):
    monkeypatch.setenv(
        "PLAY_SERVICE_ACCOUNT_JSON", '{"type": "service_account", "client_email": "t@x"}'
    )
    monkeypatch.setenv("PLAY_TESTING_ACCOUNT", "t@x")
    code, summary, _ = cli("--version", "2.4.0")
    assert code == 1 and "testing service account" in summary and not cli.api.calls


def test_main_without_the_testing_account_only_does_a_dry_run(cli, monkeypatch):
    monkeypatch.delenv("PLAY_TESTING_ACCOUNT")
    code, summary, printed = cli("--version", "2.4.0", "--dry-run")
    assert code == 0 and "**Warning:** Repository variable PLAY_TESTING_ACCOUNT" in summary
    assert "::warning title=promote::" in printed
    code, summary, _ = cli("--version", "2.4.0")
    assert code == 1 and "Only a dry run works without it" in summary
    assert not cli.api.did("commit")


def test_main_needs_the_secret(cli, monkeypatch):
    monkeypatch.delenv("PLAY_SERVICE_ACCOUNT_JSON")
    code, summary, _ = cli("--action", "halt")
    assert code == 1 and "PLAY_SERVICE_ACCOUNT_JSON is not set" in summary


# --- auto promote (the `promote` job of app.yml) -----------------------------------------


def test_auto_promote_with_the_switch_on_promotes_at_20(cli, monkeypatch):
    monkeypatch.setenv("AUTO_PROMOTE", "on")
    code, summary, _ = cli(
        "--auto", "--action", "promote", "--version", "v2.4.0", "--rollout", "20"
    )
    assert code == 0 and cli.api.did("commit")
    assert "| production | 745 | 2.4.0 | inProgress | 20% |" in summary
    assert cli.api.tracks["production"][0]["userFraction"] == 0.2


@pytest.mark.parametrize("value", [None, "", "off", "ON", "1", "true"])
def test_auto_promote_does_nothing_unless_the_switch_is_on(cli, monkeypatch, value):
    monkeypatch.delenv("AUTO_PROMOTE", raising=False)
    if value is not None:
        monkeypatch.setenv("AUTO_PROMOTE", value)
    # Without the key too: with the switch off the secret is not even read.
    monkeypatch.delenv("PLAY_SERVICE_ACCOUNT_JSON")
    code, summary, printed = cli("--auto", "--version", "2.4.0")
    assert code == 0 and not cli.api.calls
    assert "AUTO_PROMOTE is not `on`: nothing was read or changed" in summary
    assert "::notice title=promote::" in printed


def test_a_manual_run_does_not_need_the_switch(cli, monkeypatch):
    monkeypatch.delenv("AUTO_PROMOTE", raising=False)
    code, _, _ = cli("--version", "2.4.0")
    assert code == 0 and cli.api.did("commit")


@pytest.mark.parametrize(
    ("alpha", "production", "why"),
    [
        ([rel(730, "2.2.0")], None, "is not on closed testing"),
        ([rel(745, "2.4.0", "draft")], None, "not completed"),
        ([rel(745, "2.4.0")], [rel(750, "2.5.0")], "older than production"),
        ([rel(745, "2.4.0")], [rel(745, "2.4.0", "inProgress", 0.5)], "already on production"),
    ],
)
def test_auto_promote_keeps_every_refusal(cli, monkeypatch, alpha, production, why):
    monkeypatch.setenv("AUTO_PROMOTE", "on")
    cli.api.tracks["alpha"] = alpha
    if production is not None:
        cli.api.tracks["production"] = production
    before = copy.deepcopy(cli.api.tracks)
    code, summary, _ = cli("--auto", "--version", "2.4.0")
    assert code == 1 and why in summary and "Nothing was changed on Google Play." in summary
    assert not cli.api.did("commit") and cli.api.tracks == before


def test_auto_promote_ships_only_the_version_code_this_run_built(cli, monkeypatch):
    monkeypatch.setenv("AUTO_PROMOTE", "on")
    code, summary, _ = cli("--auto", "--version", "2.4.0", "--code", "744")
    assert code == 1 and "holds versionCode 745, not 744" in summary
    assert not cli.api.did("update") and not cli.api.did("commit")
    code, _, _ = cli("--auto", "--version", "2.4.0", "--code", "745")
    assert code == 0 and cli.api.did("commit")


def test_the_token_can_ask_for_another_scope():
    form = pp.token_request(
        json.dumps({"type": "service_account", "client_email": "a@b", "private_key": "k"}),
        now=1,
        signer=lambda message, key: b"sig",
        scope="one two",
    )
    assert json.loads(_unb64(form["assertion"].split(".")[1]))["scope"] == "one two"


def test_an_error_body_that_cannot_be_read_is_still_a_clean_error():
    class Broken(io.BytesIO):
        def read(self, *args):
            raise OSError("cut")

    error = urllib.error.HTTPError("https://x", 502, "Bad Gateway", {}, Broken())
    with pytest.raises(pp.PromoteError, match="HTTP 502: no details"):
        pp.call("GET", "https://x/y", opener=FakeHttp([error]))


# --- the workflows that run it ---------------------------------------------------------


def test_app_yml_promotes_only_a_tagged_alpha_release_pushed_to_main_with_the_switch_on():
    text = (ROOT / ".github" / "workflows" / "app.yml").read_text(encoding="utf-8")
    workflow = yaml.safe_load(text)
    assert "pull_request_target" not in workflow[True] and "workflow_run" not in workflow[True]
    jobs = workflow["jobs"]
    job = jobs["promote"]
    assert job["needs"] == ["analyze", "play", "release-tag"]
    condition = " ".join(job["if"].split())
    for must in (
        "!failure() && !cancelled()",
        "github.event_name == 'push'",  # never a pull request or a manual run
        "github.ref == 'refs/heads/main'",
        "vars.AUTO_PROMOTE == 'on'",  # the kill switch; unset is off
        "needs.analyze.outputs.track == 'alpha'",  # PLAY_PUSH_TRACK
        "needs.play.result == 'success'",
        "needs.release-tag.result == 'success'",
        "needs.release-tag.outputs.released == 'yes'",
    ):
        assert must in condition
    assert "||" not in condition  # every condition must hold
    assert job["environment"] == "play-production"
    assert job["permissions"] == {"contents": "read", "pull-requests": "read"}
    assert job["concurrency"] == {"group": "play-promote", "cancel-in-progress": False}
    (merged, checkout, run) = job["steps"]
    # First of all, and before the key is read: the commit is a merged pull request's.
    assert "commits/$GITHUB_SHA/pulls" in merged["run"] and "exit 1" in merged["run"]
    assert ".merge_commit_sha == $sha" in merged["run"] and '.base.ref == "main"' in merged["run"]
    assert "secrets." not in json.dumps(merged) and "${{" not in merged["run"]
    assert checkout["uses"].startswith("actions/checkout@") and len(checkout["uses"]) == 57
    assert checkout["with"]["persist-credentials"] is False
    assert checkout["with"]["sparse-checkout"].split() == [
        "scripts/play_promote.py",
        "docs/store/whatsnew/whatsnew-en-US",
    ]
    command = " ".join(run["run"].replace("\\\n", " ").split())
    assert "python3 -I scripts/play_promote.py --auto --action promote" in command
    assert '--version "$TAG" --code "$GITHUB_RUN_NUMBER" --rollout 20' in command
    assert "pip" not in run["run"]
    assert run["env"]["TAG"] == "${{ needs.release-tag.outputs.tag }}"
    assert run["env"]["AUTO_PROMOTE"] == "${{ vars.AUTO_PROMOTE }}"
    assert "${{" not in run["run"]  # values reach the shell through env only
    # The production key: this job only. `play` hands its key to a third-party upload action,
    # so it stays in environment `play` and no track of this workflow is production.
    holders = [n for n, j in jobs.items() if "play-production" in json.dumps(j.get("environment"))]
    assert holders == ["promote"] and jobs["play"]["environment"] == "play"
    options = workflow[True]["workflow_dispatch"]["inputs"]["play_track"]["options"]
    assert options == ["none", "manual", "internal", "alpha", "beta"]
    assert "|production)" not in text
    third_party = [
        s["uses"]
        for j in jobs.values()
        for s in j.get("steps", [])
        if "upload-google-play" in s.get("uses", "")
    ]
    assert len(third_party) == 1 and "upload-google-play" in json.dumps(jobs["play"]["steps"])
    assert jobs["release-tag"]["outputs"]["released"] == "${{ steps.tag.outputs.released }}"
    assert "promote" in jobs["result"]["needs"]  # a failed promote makes the run red


def test_the_workflow_keeps_the_play_key_in_the_approved_environment():
    text = (ROOT / ".github" / "workflows" / "promote.yml").read_text(encoding="utf-8")
    workflow = yaml.safe_load(text)
    assert list(workflow[True]) == ["workflow_dispatch"]  # YAML reads `on` as True
    assert workflow["permissions"] == {}
    (job,) = workflow["jobs"].values()
    assert job["environment"] == "play-production"
    assert job["permissions"] == {"contents": "read"}
    with_secret = [s for s in job["steps"] if "secrets." in json.dumps(s)]
    assert len(with_secret) == 1 and "play_promote.py" in with_secret[0]["run"]
    assert text.count("secrets.") == 1
    uses = [s["uses"] for s in job["steps"] if "uses" in s]
    assert all(u.startswith("actions/checkout@") and len(u.split("@")[1]) == 40 for u in uses)
    inputs = workflow[True]["workflow_dispatch"]["inputs"]
    assert (
        inputs["action"]["options"] == list(pp.ACTIONS) and inputs["action"]["default"] == "promote"
    )
    assert inputs["rollout"]["options"] == [str(p) for p in pp.PERCENTS]
    assert inputs["rollout"]["default"] == "20"
    assert inputs["dry_run"]["default"] is False
