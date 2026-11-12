"""scripts/push_data.sh and web/build.sh against local git repos and tarballs.

Most tests run with the published data on the data branch (web/data-source.txt says `data`),
the state after the switch; `source_main` puts main back to how it is today."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "push_data.sh"
REMOTE = "git@github.com:hndrwn-dk/dailylah.git"
PUBLIC = "https://github.com/hndrwn-dk/dailylah.git"  # what --baseline reads, without a key
# The allowed paths the workflows pass (data.yml, where-to-live.yml).
DATA = ["web/data/*.json", "backend/data/geocode.json", "backend/data/build_report.json"]
WHERE_TO_LIVE = ["web/data/where-to-live.json", "backend/data/where_to_live_routes.json"]
# The town pages and sitemap come only from main's own generator, run by the push job.
PAGES = "cd backend && python3 -E -s -m app.where_to_live_pages ../web"
GENERATED = ["--generated", "web/where-to-live-towns/*.html", "--generated", "web/sitemap.xml"]
NEW = '{"v": "new"}\n'

pytestmark = pytest.mark.skipif(
    shutil.which("git") is None or shutil.which("bash") is None, reason="needs git and bash"
)


def git(cwd: Path, *args: str, env: dict | None = None) -> str:
    return subprocess.run(  # noqa: S603 - fixed git command in a temporary test repo
        ["git", *args],  # noqa: S607 - git from PATH
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


@pytest.fixture
def repos(tmp_path: Path):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "SSH_", "DATA_PUSH"))}
    env |= {
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@example.com",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@example.com",
    }
    bare = tmp_path / "origin.git"
    git(tmp_path, "init", "--quiet", "--bare", "-b", "main", str(bare), env=env)
    seed = tmp_path / "seed"
    git(tmp_path, "init", "--quiet", "-b", "main", str(seed), env=env)
    for rel in [
        "web/data/where-to-live.json",
        "web/data/other.json",
        "backend/data/where_to_live_routes.json",
        ".github/workflows/x.yml",
        "web/data/run.sh",
        "web/data/school_holidays.json",
    ]:
        (seed / rel).parent.mkdir(parents=True, exist_ok=True)
        (seed / rel).write_text('{"v": "old"}\n' if rel.endswith(".json") else "old\n")
    (seed / "web/data-source.txt").write_text("data\n")
    # main's generator for the town pages, as the push job runs it.
    for rel in ("backend/app/__init__.py", "backend/app/where_to_live_pages.py"):
        (seed / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / rel, seed / rel)
    git(seed, "add", ".", env=env)
    git(seed, "commit", "--quiet", "-m", "seed", env=env)
    git(seed, "push", "--quiet", str(bare), "main", env=env)
    work = tmp_path / "work"
    git(tmp_path, "clone", "--quiet", str(bare), str(work), env=env)
    script_env = env | {
        "GITHUB_REPOSITORY": "hndrwn-dk/dailylah",
        "DATA_PUSH_SSH_KEY": "dummy",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": f"url.{bare}.insteadOf",
        "GIT_CONFIG_VALUE_0": REMOTE,
        "GIT_CONFIG_KEY_1": f"url.{bare}.insteadOf",
        "GIT_CONFIG_VALUE_1": PUBLIC,
    }
    # The deploy hook is set and curl is a recorder, so no test calls anyone.
    script_env, _ = fake_curl(tmp_path, script_env | {"VERCEL_DEPLOY_HOOK": HOOK})
    return seed, work, bare, env, script_env


def make_patch(seed: Path, env: dict, tmp: Path, change) -> Path:
    change(seed)
    git(seed, "add", "-A", env=env)
    patch = tmp / "data.patch"
    patch.write_text(git(seed, "diff", "--cached", "--binary", "--full-index", env=env))
    git(seed, "reset", "--quiet", "--hard", env=env)
    return patch


def run_baseline(repo: Path, env: dict):
    return subprocess.run(  # noqa: S603 - the script under test
        ["bash", str(SCRIPT), "--baseline"],  # noqa: S607
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def run_script(work: Path, env: dict, patch: Path, allowed: list[str], options=()):
    return subprocess.run(  # noqa: S603 - the script under test
        ["bash", str(SCRIPT), *options, str(patch), "Update data", *allowed],  # noqa: S607
        cwd=work,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def main_head(bare: Path, env: dict) -> tuple[str, str]:
    """The commits of main and of the data branch ("" while there is none)."""
    refs = git(bare, "for-each-ref", "--format=%(refname:short) %(objectname)", env=env)
    found = dict(line.split() for line in refs.splitlines())
    return found["main"], found.get("data", "")


def data_files(bare: Path, env: dict) -> list[str]:
    return git(bare, "ls-tree", "-r", "--name-only", "data", env=env).split()


def write(rel: str, text: str = NEW):
    def change(repo: Path):
        (repo / rel).parent.mkdir(parents=True, exist_ok=True)
        (repo / rel).write_text(text)

    return change


def test_allowed_data_change_is_pushed(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    main, data = main_head(bare, env)
    assert main == before[0] and data  # main is never pushed to; the data branch is new
    assert git(bare, "show", "data:web/data/other.json", env=env) == NEW
    assert "Pushed to data" in result.stdout
    # The branch holds the data files only: no code, no workflow, nothing else of main.
    assert data_files(bare, env) == [
        "backend/data/where_to_live_routes.json",
        "web/data/other.json",
        "web/data/school_holidays.json",
        "web/data/where-to-live.json",
    ]
    assert git(bare, "rev-list", "--count", "data", env=env).strip() == "1"


def test_a_second_update_goes_on_top_of_the_data_branch(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    assert run_script(work, script_env, patch, DATA).returncode == 0
    first = main_head(bare, env)[1]
    # The next build starts from the published data, not from main's copy.
    assert run_baseline(seed, script_env).returncode == 0
    assert (seed / "web/data/other.json").read_text() == NEW
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", '{"v": 3}\n'))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert result.returncode == 0, result.stdout + result.stderr
    assert git(bare, "rev-parse", "data^", env=env).strip() == first
    assert git(bare, "show", "data:web/data/other.json", env=env) == NEW
    assert git(bare, "show", "data:web/data/where-to-live.json", env=env) == '{"v": 3}\n'
    # The same patch again: nothing to push.
    again = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert again.returncode == 0 and "Nothing left to push" in again.stdout
    assert git(bare, "rev-list", "--count", "data", env=env).strip() == "2"


def push_to_data(tmp: Path, bare: Path, env: dict, files: dict[str, str], mode: int = 0o644):
    """Puts a commit on the data branch directly, as a holder of the deploy key could."""
    side = tmp / "side"
    shutil.rmtree(side, ignore_errors=True)
    git(tmp, "init", "--quiet", "-b", "data", str(side), env=env)
    for rel, text in files.items():
        (side / rel).parent.mkdir(parents=True, exist_ok=True)
        (side / rel).write_text(text)
        (side / rel).chmod(mode)
    git(side, "add", ".", env=env)
    git(side, "commit", "--quiet", "-m", "direct", env=env)
    git(side, "push", "--quiet", "--force", str(bare), "data", env=env)


@pytest.mark.parametrize(
    "rel",
    [
        "backend/app/where_to_live_pages.py",  # the generator the push job runs
        "scripts/push_data.sh",
        ".github/workflows/data.yml",
        "web/index.html",
        "web/data/evil.js",
        "backend/data/where_to_live_points.json",  # written by hand, belongs to main
    ],
)
def test_a_data_branch_with_anything_but_data_is_refused(repos, tmp_path, rel):
    seed, work, bare, env, script_env = repos
    push_to_data(tmp_path, bare, env, {"web/data/other.json": NEW, rel: "x\n"})
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode != 0 and f"may not: {rel}" in result.stdout
    assert main_head(bare, env) == before
    # The build job refuses it too, before it builds anything on top.
    result = run_baseline(seed, script_env)
    assert result.returncode != 0 and f"may not: {rel}" in result.stdout
    assert (ROOT / rel).exists() or not (seed / rel).exists() or (seed / rel).read_text() != "x\n"


def test_an_executable_file_on_the_data_branch_is_refused(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    push_to_data(tmp_path, bare, env, {"web/data/other.json": NEW}, mode=0o755)
    result = run_baseline(seed, script_env)
    assert result.returncode != 0 and "100755" in result.stdout


def test_baseline_lays_the_data_branch_over_the_checkout(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    # No data branch yet: the build starts from main's copy.
    result = run_baseline(seed, script_env)
    assert result.returncode == 0 and "No data branch yet" in result.stdout
    assert (seed / "web/data/other.json").read_text() == '{"v": "old"}\n'
    # With one: its files replace main's copies, and a bundle it dropped is gone.
    push_to_data(tmp_path, bare, env, {"web/data/other.json": NEW, "web/data/extra.json": NEW})
    result = run_baseline(seed, script_env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (seed / "web/data/other.json").read_text() == NEW
    assert (seed / "web/data/extra.json").read_text() == NEW
    assert not (seed / "web/data/where-to-live.json").exists()
    # Code and files outside the data paths are main's.
    assert (seed / ".github/workflows/x.yml").read_text() == "old\n"
    assert (seed / "web/data/run.sh").exists()
    # The patch of a build is a diff against that baseline.
    assert git(seed, "status", "--porcelain", env=env) == ""
    patch = make_patch(seed, env, tmp_path, write("web/data/extra.json", '{"v": 2}\n'))
    assert patch.read_text().count("diff --git") == 1
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert git(bare, "show", "data:web/data/extra.json", env=env) == '{"v": 2}\n'
    assert "web/data/where-to-live.json" not in data_files(bare, env)


def fake_curl(tmp: Path, env: dict, code: int = 0) -> tuple[dict, Path]:
    """A `curl` first on PATH that records its arguments instead of calling anyone."""
    bin_dir, log = tmp / "bin", tmp / "curl.log"
    bin_dir.mkdir(exist_ok=True)
    (bin_dir / "curl").write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{log}"\nexit {code}\n')
    (bin_dir / "curl").chmod(0o755)
    return env | {"PATH": f"{bin_dir}{os.pathsep}{env['PATH']}"}, log


HOOK = "https://api.vercel.com/v1/integrations/deploy/prj_x/SECRETHOOK"


def test_the_site_is_redeployed_after_a_push_and_only_then(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    hooked, log = fake_curl(tmp_path, script_env)
    log.unlink(missing_ok=True)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, hooked, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Asked Vercel to deploy the site." in result.stdout
    assert log.read_text().split()[-1] == HOOK and "-X POST" in log.read_text()
    assert "SECRETHOOK" not in result.stdout + result.stderr
    # A refused patch: no deploy.
    log.unlink()
    bad = make_patch(seed, env, tmp_path, write("web/data/evil.js"))
    assert run_script(work, hooked, bad, DATA).returncode != 0 and not log.exists()


def no_hook(script_env: dict) -> dict:
    return {k: v for k, v in script_env.items() if k != "VERCEL_DEPLOY_HOOK"}


def commit_on_main(seed: Path, bare: Path, env: dict, files: dict[str, str], message="edit"):
    """A merged pull request: a commit on top of the newest main."""
    git(seed, "fetch", "--quiet", str(bare), "refs/heads/main", env=env)
    git(seed, "reset", "--quiet", "--hard", "FETCH_HEAD", env=env)
    for rel, text in files.items():
        (seed / rel).parent.mkdir(parents=True, exist_ok=True)
        (seed / rel).write_text(text)
    git(seed, "add", "-A", env=env)
    git(seed, "commit", "--quiet", "-m", message, env=env)
    git(seed, "push", "--quiet", str(bare), "HEAD:main", env=env)


def source_main(seed: Path, bare: Path, env: dict):
    """main as it is before the switch: the data is published from main."""
    commit_on_main(seed, bare, env, {"web/data-source.txt": "main\n"})


def test_with_source_main_the_update_goes_to_main_as_before_and_the_branch_gets_a_copy(
    repos, tmp_path
):
    seed, work, bare, env, script_env = repos
    source_main(seed, bare, env)
    before = main_head(bare, env)[0]
    assert "Baseline: main" in run_baseline(seed, script_env).stdout
    assert git(seed, "rev-parse", "HEAD", env=env).strip() == before  # no local baseline commit
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    # No deploy hook is needed: Vercel deploys on the push to main.
    hookless, log = fake_curl(tmp_path, no_hook(script_env))
    log.unlink(missing_ok=True)
    result = run_script(work, hookless, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Pushed to main" in result.stdout and "::warning" not in result.stdout
    assert not log.exists()
    main, data_tip = main_head(bare, env)
    # One commit on top of main: the update and the generated pages, nothing else.
    assert git(bare, "rev-parse", "main^", env=env).strip() == before
    changed = git(bare, "diff", "--name-only", before, "main", env=env).split()
    assert "web/data/where-to-live.json" in changed and "web/sitemap.xml" in changed
    assert all(
        c.startswith(("web/data/", "web/where-to-live-towns/", "web/sitemap")) for c in changed
    )
    # The data branch holds the same data files, and only those.
    assert data_tip and "web/data-source.txt" not in data_files(bare, env)
    for rel in data_files(bare, env):
        assert git(bare, "show", f"main:{rel}", env=env) == git(
            bare, "show", f"data:{rel}", env=env
        ), rel
    # The same patch again: nothing to push anywhere.
    again = run_script(work, hookless, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert again.returncode == 0 and "Nothing left to push" in again.stdout
    assert main_head(bare, env) == (main, data_tip)
    # A pull request changes a data file on main; a run with nothing to push (or with `-`)
    # still brings the copy up to date, so the switch never starts from an older branch.
    for year, arg in ((2027, patch), (2028, Path("-"))):
        text = f'{{"y": {year}}}\n'
        commit_on_main(seed, bare, env, {"web/data/school_holidays.json": text})
        result = run_script(work, hookless, arg, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
        assert result.returncode == 0, result.stdout + result.stderr
        assert git(bare, "show", "data:web/data/school_holidays.json", env=env) == text


def test_with_source_main_what_is_on_the_data_branch_is_never_read(repos, tmp_path):
    """Before the switch anyone with a write token could push to `data`: it must not reach main."""
    seed, work, bare, env, script_env = repos
    source_main(seed, bare, env)
    push_to_data(
        tmp_path,
        bare,
        env,
        {
            "web/data/other.json": '{"v": "planted"}\n',
            "web/where-to-live-towns/planted.html": "<p>planted</p>\n",
            "backend/app/where_to_live_pages.py": "raise SystemExit('planted')\n",
        },
    )
    assert "Baseline: main" in run_baseline(seed, script_env).stdout
    assert (seed / "web/data/other.json").read_text() == '{"v": "old"}\n'
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    result = run_script(
        work, no_hook(script_env), patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED]
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert git(bare, "show", "main:web/data/other.json", env=env) == '{"v": "old"}\n'
    files = git(bare, "ls-tree", "-r", "--name-only", "main", env=env).split()
    assert "web/where-to-live-towns/planted.html" not in files
    # And the branch is main's data again, with nothing planted left.
    assert git(bare, "show", "data:web/data/other.json", env=env) == '{"v": "old"}\n'
    assert "web/where-to-live-towns/planted.html" not in data_files(bare, env)
    assert "backend/app/where_to_live_pages.py" not in data_files(bare, env)


def test_with_source_main_a_data_branch_that_refuses_the_copy_only_warns(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    source_main(seed, bare, env)
    hook = bare / "hooks" / "update"
    hook.write_text('#!/bin/sh\n[ "$1" != refs/heads/data ]\n')
    hook.chmod(0o755)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, no_hook(script_env), patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Pushed to main" in result.stdout
    assert "::warning::The copy on the data branch was not updated" in result.stdout
    assert git(bare, "show", "main:web/data/other.json", env=env) == NEW


def test_with_source_data_and_no_hook_nothing_is_pushed(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, no_hook(script_env), patch, DATA)
    assert result.returncode != 0 and "VERCEL_DEPLOY_HOOK is not set" in result.stdout
    assert main_head(bare, env) == before


def test_with_source_data_main_is_never_pushed_to(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    # main refuses direct pushes, as its ruleset does once the bypass is gone.
    hook = bare / "hooks" / "update"
    hook.write_text('#!/bin/sh\n[ "$1" != refs/heads/main ]\n')
    hook.chmod(0o755)
    before = main_head(bare, env)[0]
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    assert main_head(bare, env)[0] == before and "Pushed to data" in result.stdout


def test_an_unknown_data_source_stops_everything(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    commit_on_main(seed, bare, env, {"web/data-source.txt": "elsewhere\n"})
    before = main_head(bare, env)
    result = run_baseline(seed, script_env)
    assert result.returncode != 0 and "must say main or data" in result.stderr
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    assert run_script(work, script_env, patch, DATA).returncode != 0
    assert main_head(bare, env) == before


@pytest.mark.parametrize("name", ["main", "data"])
def test_a_tag_named_like_a_branch_is_not_taken_for_it(repos, tmp_path, name):
    seed, work, bare, env, script_env = repos
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    assert run_script(work, script_env, patch, DATA).returncode == 0
    # A tag `main` / `data` on a commit with a planted generator and planted data.
    side = tmp_path / "tagged"
    git(tmp_path, "clone", "--quiet", str(bare), str(side), env=env)
    (side / "backend/app/where_to_live_pages.py").write_text("raise SystemExit('planted')\n")
    (side / "web/data/other.json").write_text('{"v": "planted"}\n')
    git(side, "commit", "--quiet", "-am", "planted", env=env)
    git(side, "tag", name, env=env)
    git(side, "push", "--quiet", str(bare), f"refs/tags/{name}", env=env)
    assert run_baseline(seed, script_env).returncode == 0
    assert (seed / "web/data/other.json").read_text() == NEW
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr  # main's own generator ran
    assert git(bare, "show", "refs/heads/data:web/data/other.json", env=env) == NEW
    files = git(bare, "ls-tree", "-r", "--name-only", "refs/heads/data", env=env).split()
    assert "web/where-to-live-towns/index.html" in files


def test_a_file_kept_by_hand_on_main_wins_over_the_data_branch(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    assert run_script(work, script_env, patch, DATA).returncode == 0
    assert git(bare, "show", "data:web/data/school_holidays.json", env=env) == '{"v": "old"}\n'
    # A pull request adds next year's school holidays on main.
    commit_on_main(seed, bare, env, {"web/data/school_holidays.json": '{"y": 2027}\n'})
    assert run_baseline(seed, script_env).returncode == 0
    assert (seed / "web/data/school_holidays.json").read_text() == '{"y": 2027}\n'
    assert (seed / "web/data/other.json").read_text() == NEW  # the rest is the branch's
    # The next update carries it to the data branch, whatever else it changes.
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json", '{"v": 3}\n'))
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert git(bare, "show", "data:web/data/school_holidays.json", env=env) == '{"y": 2027}\n'


def test_a_generator_change_on_main_makes_the_published_pages_again(repos, tmp_path):
    """where-to-live.yml runs the push job with `-` (no patch) after such a merge."""
    seed, work, bare, env, script_env = repos
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    assert run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    first = main_head(bare, env)[1]
    gen = (
        "mkdir -p web/where-to-live-towns && echo '<p>v2</p>' > web/where-to-live-towns/index.html"
    )
    hooked, log = fake_curl(tmp_path, script_env)
    log.unlink(missing_ok=True)
    result = run_script(work, hooked, Path("-"), WHERE_TO_LIVE, ["--generate", gen, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    assert git(bare, "show", "data:web/where-to-live-towns/index.html", env=env) == "<p>v2</p>\n"
    assert git(bare, "rev-parse", "data^", env=env).strip() == first and log.exists()
    # With the data published from main there is nothing to do: the pull request has the pages.
    source_main(seed, bare, env)
    before = main_head(bare, env)[0]
    result = run_script(work, hooked, Path("-"), WHERE_TO_LIVE, ["--generate", gen, *GENERATED])
    assert result.returncode == 0 and "Nothing to do" in result.stdout
    assert main_head(bare, env)[0] == before


def test_a_run_again_after_a_failed_deploy_only_starts_the_deployment(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    failing, _ = fake_curl(tmp_path, script_env, code=22)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    assert run_script(work, failing, patch, DATA).returncode != 0
    tip = main_head(bare, env)[1]
    working, log = fake_curl(tmp_path, script_env)
    log.unlink(missing_ok=True)
    result = run_script(work, working, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Nothing left to push" in result.stdout and "Asked Vercel to deploy" in result.stdout
    assert log.exists() and main_head(bare, env)[1] == tip


def test_where_to_live_change_is_pushed(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert result.returncode == 0, result.stdout + result.stderr
    assert main_head(bare, env) != before


def test_workflow_change_is_refused(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)

    def change(repo: Path):
        write("web/data/other.json")(repo)
        write(".github/workflows/x.yml")(repo)

    patch = make_patch(seed, env, tmp_path, change)
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode != 0
    assert ".github/workflows/x.yml" in result.stdout
    assert main_head(bare, env) == before
    # Nothing was written outside the allowed paths either.
    assert (work / ".github/workflows/x.yml").read_text() == "old\n"


def test_symlink_is_refused(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(
        seed, env, tmp_path, lambda r: (r / "web/data/link.json").symlink_to("../../.github")
    )
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode != 0
    assert main_head(bare, env) == before


def test_mode_change_is_refused(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, lambda r: (r / "web/data/run.sh").chmod(0o755))
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode != 0
    assert main_head(bare, env) == before


def test_where_to_live_refuses_other_data_file(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert result.returncode != 0
    assert main_head(bare, env) == before


def test_data_refuses_other_file_types_and_subfolders(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    for rel in ("web/data/evil.js", "web/data/page.html", "web/data/sub/x.json"):
        patch = make_patch(seed, env, tmp_path, write(rel))
        result = run_script(work, script_env, patch, DATA)
        assert result.returncode != 0, rel
        assert rel in result.stdout, rel
        assert main_head(bare, env) == before, rel
        git(seed, "reset", "--quiet", "--hard", env=env)
        git(seed, "clean", "--quiet", "-fd", env=env)


def test_where_to_live_refuses_town_pages_and_sitemap_in_the_patch(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    for rel in (
        "web/where-to-live-towns/punggol.html",
        "web/where-to-live-towns/index.html",
        "web/sitemap.xml",
    ):
        patch = make_patch(seed, env, tmp_path, write(rel, "<p>page</p>\n"))
        result = run_script(
            work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED]
        )
        assert result.returncode != 0, rel
        assert rel in result.stdout, rel
        assert main_head(bare, env) == before, rel
        assert not (work / rel).exists(), rel
        git(seed, "reset", "--quiet", "--hard", env=env)
        git(seed, "clean", "--quiet", "-fd", env=env)


@pytest.mark.parametrize("text", ["<script>x()</script>\n", '"text"\n', "1\n", ""])
def test_json_that_is_not_an_object_or_array_is_refused(repos, tmp_path, text):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", text))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode != 0
    assert "web/data/where-to-live.json" in result.stdout
    assert main_head(bare, env) == before


def test_where_to_live_generates_town_pages_on_push(repos, tmp_path):
    """The push job writes the pages with main's generator from the pushed JSON."""
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    assert main_head(bare, env) != before
    towns = json.loads(data)["towns"]
    pushed = git(bare, "ls-tree", "--name-only", "data", "web/where-to-live-towns/", env=env)
    assert len(pushed.split()) == len(towns) + 1
    for rel in ("web/where-to-live-towns/index.html", "web/sitemap.xml"):
        assert git(bare, "show", f"data:{rel}", env=env) == (ROOT / rel).read_text(), rel


def test_generated_files_outside_the_generated_paths_are_not_pushed(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    gen = (
        "mkdir -p web/where-to-live-towns && echo '<p>a</p>' > web/where-to-live-towns/a.html"
        " && echo x > web/where-to-live-towns/evil.js && echo x > web/data/other.json"
        " && echo '<urlset/>' > web/sitemap.xml"
    )
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", gen, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    files = data_files(bare, env)
    assert "web/where-to-live-towns/a.html" in files
    assert "web/where-to-live-towns/evil.js" not in files
    assert git(bare, "show", "data:web/data/other.json", env=env) == '{"v": "old"}\n'


@pytest.mark.parametrize("workflow", ["data.yml", "where-to-live.yml"])
def test_the_data_workflows_keep_the_key_in_the_push_job(workflow):
    text = (ROOT / ".github" / "workflows" / workflow).read_text()
    jobs = yaml.safe_load(text)["jobs"]
    build = [s.get("run", s.get("uses", "")) for s in jobs["build"]["steps"]]
    # The build starts from the published data, before pip or the build's own code runs.
    baseline = build.index("bash scripts/push_data.sh --baseline")
    assert baseline < next(i for i, step in enumerate(build) if "pip install" in step)
    assert "secrets." not in json.dumps(jobs["build"]["steps"][baseline])
    assert jobs["build"]["permissions"] == {"contents": "read"}
    push = jobs["push"]
    assert push["environment"] == "data-push" and push["permissions"] == {"contents": "read"}
    (step,) = [s for s in push["steps"] if "secrets." in json.dumps(s)]
    assert {"DATA_PUSH_SSH_KEY", "VERCEL_DEPLOY_HOOK", "PATCH"} <= set(step["env"])
    assert "scripts/push_data.sh" in step["run"] and "backend/data/*.json" not in step["run"]
    assert "contents: write" not in text


def test_the_script_pushes_to_main_only_while_main_says_so():
    script = SCRIPT.read_text()
    # One place pushes to main, inside the branch for source `main`; everything is fetched and
    # pushed by full ref name.
    assert script.count(":refs/heads/main") == 1
    main_branch = script[script.index('if [ "$source" = main ]; then', script.index("for try")) :]
    data_branch = main_branch[main_branch.index("elif overlay_data") :]
    assert ":refs/heads/main" in main_branch and ":refs/heads/main" not in data_branch
    assert 'fetch --quiet --depth 1 "$remote" refs/heads/main' in script
    assert 'fetch --quiet --depth 1 "$remote" main' not in script
    assert '"$remote" "$DATA_BRANCH"' not in script
    # The repository itself still publishes from main: switching is a pull request of its own.
    assert (ROOT / "web/data-source.txt").read_text() == "main\n"
    assert (ROOT / "web/data/school_holidays.json").exists()
    assert "HAND_KEPT=(web/data/school_holidays.json)" in script
    triggers = yaml.safe_load((ROOT / ".github/workflows/where-to-live.yml").read_text())[True]
    assert "backend/app/where_to_live_pages.py" in triggers["push"]["paths"]
    triggers = yaml.safe_load((ROOT / ".github/workflows/data.yml").read_text())[True]
    assert "web/data/school_holidays.json" in triggers["push"]["paths"]


def make_tarball(tmp: Path, files: dict[str, str], links: dict[str, str] | None = None) -> Path:
    """A tarball like GitHub's for a branch: one top folder, then the tree."""
    top = tmp / "tar" / "dailylah-data"
    shutil.rmtree(top.parent, ignore_errors=True)
    for rel, text in files.items():
        (top / rel).parent.mkdir(parents=True, exist_ok=True)
        (top / rel).write_text(text)
    for rel, target in (links or {}).items():
        (top / rel).parent.mkdir(parents=True, exist_ok=True)
        (top / rel).symlink_to(target)
    out = tmp / "data.tgz"
    subprocess.run(  # noqa: S603 - fixed tar command on test files
        ["tar", "-czf", str(out), "-C", str(top.parent), top.name],  # noqa: S607
        check=True,
    )
    return out


def run_build(site: Path, tarball: Path):
    return subprocess.run(  # noqa: S603 - the script under test
        ["bash", str(ROOT / "web" / "build.sh")],  # noqa: S607
        cwd=site,
        env=os.environ | {"DATA_TARBALL": str(tarball)},
        capture_output=True,
        text=True,
        timeout=60,
    )


@pytest.fixture
def site(tmp_path: Path) -> Path:
    """A small copy of web/ as Vercel has it when the build step runs."""
    root = tmp_path / "site"
    for rel, text in {
        "index.html": "main page\n",
        "data-source.txt": "data\n",
        "vercel.json": "{}\n",
        "shared/app.js": "main script\n",
        "data/manifest.json": '{"version": 1}\n',
        "data/dropped.json": "{}\n",
        "where-to-live-towns/old-town.html": "old\n",
        "sitemap.xml": "<old/>\n",
    }.items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text)
    return root


def test_the_site_build_takes_the_data_from_the_data_branch(site, tmp_path):
    tarball = make_tarball(
        tmp_path,
        {
            "web/data/manifest.json": '{"version": 2}\n',
            "web/data/bus_stops.json": "[]\n",
            "web/where-to-live-towns/punggol.html": "<p>new</p>\n",
            "web/sitemap.xml": (ROOT / "web/sitemap.xml").read_text(),
            "backend/data/geocode.json": "{}\n",
        },
    )
    result = run_build(site, tarball)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (site / "data/manifest.json").read_text() == '{"version": 2}\n'
    assert sorted(p.name for p in (site / "data").iterdir()) == ["bus_stops.json", "manifest.json"]
    assert [p.name for p in (site / "where-to-live-towns").iterdir()] == ["punggol.html"]
    assert (site / "sitemap.xml").read_text() == (ROOT / "web/sitemap.xml").read_text()
    assert not (site / "geocode.json").exists() and not (site / "backend").exists()


def test_the_site_build_takes_nothing_but_data_files(site, tmp_path):
    """Whoever can write the data branch must not get a page or a script onto the site."""
    tarball = make_tarball(
        tmp_path,
        {
            "web/data/manifest.json": '{"version": 2}\n',
            "web/data/evil.js": "x\n",
            "web/data/page.html": "x\n",
            "web/data/sub/deep.json": "{}\n",
            "web/index.html": "replaced\n",
            "web/vercel.json": '{"headers": []}\n',
            "web/shared/app.js": "replaced\n",
            "web/where-to-live-towns/evil.js": "x\n",
            "web/where-to-live/index.html": "replaced\n",
            "web/build.sh": "echo replaced\n",
        },
        links={"web/data/link.json": "/etc/passwd", "web/sitemap.xml": "/etc/passwd"},
    )
    result = run_build(site, tarball)
    assert result.returncode == 0, result.stdout + result.stderr
    assert sorted(p.name for p in (site / "data").iterdir()) == ["manifest.json"]
    assert (site / "index.html").read_text() == "main page\n"
    assert (site / "vercel.json").read_text() == "{}\n"
    assert (site / "shared/app.js").read_text() == "main script\n"
    assert (site / "sitemap.xml").read_text() == "<old/>\n"  # a link is not taken
    assert not (site / "where-to-live").exists() and not (site / "build.sh").exists()
    # No town pages on the branch: main's stay.
    assert [p.name for p in (site / "where-to-live-towns").iterdir()] == ["old-town.html"]


def test_the_site_build_does_nothing_while_the_data_is_published_from_main(site, tmp_path):
    tarball = make_tarball(tmp_path, {"web/data/manifest.json": '{"version": 2}\n'})
    for word in ("main\n", None):
        if word is None:
            (site / "data-source.txt").unlink()
        else:
            (site / "data-source.txt").write_text(word)
        result = run_build(site, tarball)
        assert result.returncode == 0 and "Data source: main" in result.stdout
        assert (site / "data/manifest.json").read_text() == '{"version": 1}\n'
    (site / "data-source.txt").write_text("somewhere\n")
    assert run_build(site, tarball).returncode != 0


@pytest.mark.parametrize(
    "sitemap",
    [
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n<url><loc>https://dailylah.sg/</loc></url>\n'
        '<script xmlns="http://www.w3.org/1999/xhtml">alert(1)</script>\n</urlset>\n',
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n<url><loc>https://evil.example/</loc></url>\n</urlset>\n',
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE x [<!ENTITY e "x">]>\n<urlset '
        'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n<url><loc>https://dailylah.sg/&e;'
        "</loc></url>\n</urlset>\n",
        "<html><body>page</body></html>\n",
        # A tag spread over several lines (grep works line by line).
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n  <url><loc>https://dailylah.sg/</loc></url>\n<script\n xmlns="http://'
        'www.w3.org/1999/xhtml"\n>alert(1)</script\n>\n</urlset>\n',
        # A comment and a stylesheet instruction.
        '<?xml version="1.0" encoding="UTF-8"?>\n<?xml-stylesheet href="//evil.example/x.xsl"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n</urlset>\n',
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n  <url><loc>https://dailylah.sg/</loc></url><!--\n-->\n</urlset>\n',
        # A self-closing tag over three lines, with no closing tag to give it away.
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n<script\nxmlns="http://www.w3.org/1999/xhtml" src="https://evil.example/'
        'x.js"\n/>\n</urlset>\n',
        # A big file with the bad line near the top (a check that stops reading early must
        # still refuse it), and one whose first page is on another site.
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n<script xmlns="http://www.w3.org/1999/xhtml">alert(1)</script>\n'
        + "  <url><loc>https://dailylah.sg/where-to-live/a-town</loc></url>\n" * 6000
        + "</urlset>\n",
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/'
        'sitemap/0.9">\n  <url><loc>https://evil.example/</loc></url>\n'
        + "  <url><loc>https://dailylah.sg/where-to-live/a-town</loc></url>\n" * 6000
        + "</urlset>\n",
    ],
)
def test_the_site_build_takes_only_a_plain_sitemap(site, tmp_path, sitemap):
    files = {"web/data/manifest.json": '{"version": 2}\n', "web/sitemap.xml": sitemap}
    result = run_build(site, make_tarball(tmp_path, files))
    assert result.returncode == 0, result.stdout + result.stderr
    assert "not a plain list of dailylah.sg URLs" in result.stdout
    assert (site / "sitemap.xml").read_text() == "<old/>\n"
    # The real sitemap passes.
    files["web/sitemap.xml"] = (ROOT / "web/sitemap.xml").read_text()
    result = run_build(site, make_tarball(tmp_path, files))
    assert result.returncode == 0 and "sitemap.xml from the data branch" in result.stdout


def test_the_site_build_refuses_linked_folders(site, tmp_path):
    for links in ({"web/data": "/etc"}, {"web": "/etc"}):
        result = run_build(site, make_tarball(tmp_path, {"x.txt": "x\n"}, links))
        assert result.returncode != 0
        assert (site / "data/manifest.json").read_text() == '{"version": 1}\n'
    tarball = make_tarball(
        tmp_path,
        {"web/data/manifest.json": '{"version": 2}\n'},
        {"web/where-to-live-towns": "/etc"},
    )
    assert run_build(site, tarball).returncode == 0
    assert [p.name for p in (site / "where-to-live-towns").iterdir()] == ["old-town.html"]


def test_the_site_build_fails_on_a_data_branch_without_a_manifest(site, tmp_path):
    for files, links in (
        ({"web/data/bus_stops.json": "[]\n"}, None),
        ({"web/index.html": "x\n"}, {"web/data/manifest.json": "/etc/passwd"}),
    ):
        result = run_build(site, make_tarball(tmp_path, files, links))
        assert result.returncode != 0 and "no web/data/manifest.json" in result.stdout
        # Nothing was replaced: Vercel keeps the previous deployment.
        assert (site / "data/manifest.json").read_text() == '{"version": 1}\n'
        assert (site / "data/dropped.json").exists()


def test_vercel_runs_the_build_step_and_ships_it():
    config = json.loads((ROOT / "web/vercel.json").read_text())
    assert config["buildCommand"] == "bash build.sh"
    # With a build command Vercel wants an output folder: the site itself, as before.
    assert config["outputDirectory"] == "."
    ignored = (ROOT / "web/.vercelignore").read_text().split()
    assert "build.sh" not in ignored and "data/" not in ignored
    script = (ROOT / "web/build.sh").read_text()
    assert "codeload.github.com/hndrwn-dk/dailylah/tar.gz/refs/heads/data" in script
    assert "-type f" in script
    # A missing data branch is a failed build (the last deployment stays up), not old data.
    assert "404" not in script


def test_the_sitemap_is_served_so_that_it_can_never_run_script():
    config = json.loads((ROOT / "web/vercel.json").read_text())
    headers = next(h["headers"] for h in config["headers"] if h["source"] == "/sitemap.xml")
    assert {"key": "X-Content-Type-Options", "value": "nosniff"} in headers
    csp = next(h["value"] for h in headers if h["key"] == "Content-Security-Policy")
    assert csp.startswith("default-src 'none'")


def test_a_branch_whose_name_only_ends_like_the_data_branch_is_not_it(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    # No data branch yet, but a branch named refs/heads/data (full name refs/heads/refs/heads/data).
    side = tmp_path / "lookalike"
    git(tmp_path, "clone", "--quiet", str(bare), str(side), env=env)
    (side / "web/data/other.json").write_text('{"v": "planted"}\n')
    git(side, "commit", "--quiet", "-am", "planted", env=env)
    git(side, "push", "--quiet", str(bare), "HEAD:refs/heads/refs/heads/data", env=env)
    before = main_head(bare, env)[0]
    lookalike = git(bare, "rev-parse", "refs/heads/refs/heads/data", env=env)
    result = run_baseline(seed, script_env)
    assert result.returncode != 0 and "only ends in refs/heads/data" in result.stdout
    assert (seed / "web/data/other.json").read_text() == '{"v": "old"}\n'
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert result.returncode != 0 and "only ends in refs/heads/data" in result.stdout
    # Nothing was pushed anywhere, not to the look-alike either.
    assert main_head(bare, env) == (before, "")
    assert git(bare, "rev-parse", "refs/heads/refs/heads/data", env=env) == lookalike
    # With the real branch there, the look-alike is simply not it.
    git(bare, "update-ref", "-d", "refs/heads/refs/heads/data", env=env)
    assert run_script(work, script_env, patch, WHERE_TO_LIVE).returncode == 0
    git(side, "push", "--quiet", str(bare), "HEAD:refs/heads/refs/heads/data", env=env)
    assert run_baseline(seed, script_env).returncode == 0
    assert (seed / "web/data/where-to-live.json").read_text() == NEW
    assert (seed / "web/data/other.json").read_text() == '{"v": "old"}\n'


def test_vercel_serves_data_bundles_with_nosniff():
    """A JSON bundle must never run as a script on the site (CSP script-src 'self')."""
    config = json.loads((ROOT / "web/vercel.json").read_text())
    headers = next(h["headers"] for h in config["headers"] if h["source"] == "/data/(.*)")
    assert {"key": "X-Content-Type-Options", "value": "nosniff"} in headers


def test_where_to_live_refuses_scripts_next_to_town_pages(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)
    patch = make_patch(seed, env, tmp_path, write("web/where-to-live-towns/evil.js"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE)
    assert result.returncode != 0
    assert main_head(bare, env) == before


def test_generate_command_never_sees_the_key(repos, tmp_path):
    """Neither the environment nor the key file is there while the --generate command runs."""
    seed, work, bare, env, script_env = repos
    gen = (
        "mkdir -p web/where-to-live-towns"
        ' && key=$(printf %s "$GIT_SSH_COMMAND" | sed -n "s/.* -i \\([^ ]*\\) .*/\\1/p")'
        ' && { [ -n "$key" ] && [ ! -e "$key" ] && echo gone || echo there; }'
        "    > web/where-to-live-towns/file.html"
        ' && echo "env:${DATA_PUSH_SSH_KEY:-unset}" > web/where-to-live-towns/env.html'
        " && echo '<urlset/>' > web/sitemap.xml"
    )
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", gen, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr  # the key is back for the push
    show = lambda rel: git(bare, "show", f"data:web/where-to-live-towns/{rel}", env=env)  # noqa: E731
    assert show("file.html") == "gone\n"
    assert show("env.html") == "env:unset\n"


def test_a_generated_path_the_generator_did_not_write_is_skipped(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    gen = "mkdir -p web/where-to-live-towns && echo '<p>a</p>' > web/where-to-live-towns/a.html"
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json"))
    # web/sitemap.xml is neither on main nor written: git add must not fail on it.
    result = run_script(work, script_env, patch, WHERE_TO_LIVE, ["--generate", gen, *GENERATED])
    assert result.returncode == 0, result.stdout + result.stderr
    files = data_files(bare, env)
    assert "web/where-to-live-towns/a.html" in files
    assert "web/sitemap.xml" not in files


@pytest.mark.parametrize(
    ("workflow", "ref"),
    [
        ("data.yml", "${{ github.ref == 'refs/heads/main' && 'main' || github.sha }}"),
        ("where-to-live.yml", "main"),
    ],
)
def test_build_job_checks_out_the_newest_main(workflow, ref):
    """A queued run must not build its patch on data an earlier run already replaced (data #61).

    The push job keeps the queued commit: the push_data.sh that holds the key is the reviewed one
    the run was started with."""
    jobs = yaml.safe_load((ROOT / ".github" / "workflows" / workflow).read_text())["jobs"]

    def checkout(job: str) -> dict:
        steps = jobs[job]["steps"]
        return next(s.get("with", {}) for s in steps if "actions/checkout@" in s.get("uses", ""))

    assert checkout("build") == {"ref": ref, "persist-credentials": False}
    assert "ref" not in checkout("push")
