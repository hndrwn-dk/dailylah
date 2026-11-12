"""scripts/push_data.sh against local git repos: only allowed data files reach the data branch."""

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
    ]:
        (seed / rel).parent.mkdir(parents=True, exist_ok=True)
        (seed / rel).write_text('{"v": "old"}\n' if rel.endswith(".json") else "old\n")
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
    # The deploy hook is set (the state after the move) and curl is a recorder, so no test
    # calls anyone. Tests of the time before the hook remove VERCEL_DEPLOY_HOOK.
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
    assert result.returncode == 0 and "no data branch yet" in result.stdout
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
    # Nothing new to push: no deploy.
    log.unlink()
    assert run_script(work, hooked, patch, DATA).returncode == 0 and not log.exists()
    # A refused patch: no deploy.
    bad = make_patch(seed, env, tmp_path, write("web/data/evil.js"))
    assert run_script(work, hooked, bad, DATA).returncode != 0 and not log.exists()


def no_hook(script_env: dict) -> dict:
    return {k: v for k, v in script_env.items() if k != "VERCEL_DEPLOY_HOOK"}


def test_before_the_hook_is_set_main_gets_the_update_too(repos, tmp_path):
    """Moving over: without a deploy hook only a push to main publishes the data."""
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)[0]
    data = (ROOT / "web/data/where-to-live.json").read_text()
    patch = make_patch(seed, env, tmp_path, write("web/data/where-to-live.json", data))
    result = run_script(
        work, no_hook(script_env), patch, WHERE_TO_LIVE, ["--generate", PAGES, *GENERATED]
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "::warning::VERCEL_DEPLOY_HOOK is not set: also pushing to main" in result.stdout
    main, data_tip = main_head(bare, env)
    # One commit on top of main, with main's code untouched and the same data as the branch.
    assert git(bare, "rev-parse", "main^", env=env).strip() == before
    changed = git(bare, "diff", "--name-only", before, "main", env=env).split()
    assert "web/data/where-to-live.json" in changed and "web/sitemap.xml" in changed
    assert all(
        c.startswith(("web/data/", "web/where-to-live-towns/", "web/sitemap")) for c in changed
    )
    for rel in ("web/data/where-to-live.json", "web/where-to-live-towns/index.html"):
        on_main = git(bare, "show", f"main:{rel}", env=env)
        assert on_main == git(bare, "show", f"data:{rel}", env=env), rel
    # The next day the hook is set: main is left alone.
    assert run_baseline(seed, script_env).returncode == 0
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert main_head(bare, env)[0] == main and main_head(bare, env)[1] != data_tip


def test_without_a_hook_and_without_the_bypass_the_run_fails_and_says_why(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    # main refuses direct pushes, as its ruleset does once the bypass is gone.
    hook = bare / "hooks" / "update"
    hook.write_text('#!/bin/sh\n[ "$1" != refs/heads/main ]\n')
    hook.chmod(0o755)
    before = main_head(bare, env)[0]
    patch = make_patch(seed, env, tmp_path, write("web/data/other.json"))
    result = run_script(work, no_hook(script_env), patch, DATA)
    assert (
        result.returncode != 0
        and "main refused the push and no deploy hook is set" in result.stdout
    )
    assert main_head(bare, env)[0] == before
    # With the hook the same setup works: nothing is pushed to main.
    patch = make_patch(seed, env, tmp_path, write("web/data/second.json"))
    result = run_script(work, script_env, patch, DATA)
    assert result.returncode == 0, result.stdout + result.stderr
    assert main_head(bare, env)[0] == before


def test_a_failed_or_wrong_hook_fails(repos, tmp_path):
    seed, work, bare, env, script_env = repos
    before = main_head(bare, env)[0]
    failing, _ = fake_curl(tmp_path, script_env, code=22)
    patch = make_patch(seed, env, tmp_path, write("web/data/second.json"))
    result = run_script(work, failing, patch, DATA)
    assert result.returncode != 0 and "did not take the deploy hook" in result.stdout
    assert "web/data/second.json" in data_files(bare, env)  # pushed all the same, and said so
    elsewhere, log = fake_curl(
        tmp_path, script_env | {"VERCEL_DEPLOY_HOOK": "https://evil.example/x"}
    )
    log.unlink(missing_ok=True)
    patch = make_patch(seed, env, tmp_path, write("web/data/third.json"))
    result = run_script(work, elsewhere, patch, DATA)
    assert result.returncode != 0 and "not a Vercel deploy hook URL" in result.stdout
    assert not log.exists() and "web/data/third.json" not in data_files(bare, env)
    assert main_head(bare, env)[0] == before


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
def test_the_data_workflows_never_push_to_main(workflow):
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
    assert set(step["env"]) == {"DATA_PUSH_SSH_KEY", "VERCEL_DEPLOY_HOOK", "PATCH"}
    assert "scripts/push_data.sh" in step["run"] and "backend/data/*.json" not in step["run"]
    script = SCRIPT.read_text()
    assert "HEAD:main" not in script and ':refs/heads/$DATA_BRANCH"' in script
    assert "contents: write" not in text


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
            "web/sitemap.xml": "<new/>\n",
            "backend/data/geocode.json": "{}\n",
        },
    )
    result = run_build(site, tarball)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (site / "data/manifest.json").read_text() == '{"version": 2}\n'
    assert sorted(p.name for p in (site / "data").iterdir()) == ["bus_stops.json", "manifest.json"]
    assert [p.name for p in (site / "where-to-live-towns").iterdir()] == ["punggol.html"]
    assert (site / "sitemap.xml").read_text() == "<new/>\n"
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
    ignored = (ROOT / "web/.vercelignore").read_text().split()
    assert "build.sh" not in ignored and "data/" not in ignored
    script = (ROOT / "web/build.sh").read_text()
    assert "codeload.github.com/hndrwn-dk/dailylah/tar.gz/refs/heads/data" in script
    assert "-type f" in script


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
