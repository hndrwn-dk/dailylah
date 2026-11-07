"""scripts/push_data.sh against local git repos: only allowed data files reach main."""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "push_data.sh"
REMOTE = "git@github.com:hndrwn-dk/dailylah.git"
# The allowed paths the workflows pass (data.yml, where-to-live.yml).
DATA = ["web/data/*.json", "backend/data/*.json"]
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
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": f"url.{bare}.insteadOf",
        "GIT_CONFIG_VALUE_0": REMOTE,
    }
    return seed, work, bare, env, script_env


def make_patch(seed: Path, env: dict, tmp: Path, change) -> Path:
    change(seed)
    git(seed, "add", "-A", env=env)
    patch = tmp / "data.patch"
    patch.write_text(git(seed, "diff", "--cached", "--binary", "--full-index", env=env))
    git(seed, "reset", "--quiet", "--hard", env=env)
    return patch


def run_script(work: Path, env: dict, patch: Path, allowed: list[str], options=()):
    return subprocess.run(  # noqa: S603 - the script under test
        ["bash", str(SCRIPT), *options, str(patch), "Update data", *allowed],  # noqa: S607
        cwd=work,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def main_head(bare: Path, env: dict) -> str:
    return git(bare, "rev-parse", "main", env=env).strip()


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
    assert main_head(bare, env) != before
    assert git(bare, "show", "main:web/data/other.json", env=env) == NEW


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
    pushed = git(bare, "ls-tree", "--name-only", "main", "web/where-to-live-towns/", env=env)
    assert len(pushed.split()) == len(towns) + 1
    for rel in ("web/where-to-live-towns/index.html", "web/sitemap.xml"):
        assert git(bare, "show", f"main:{rel}", env=env) == (ROOT / rel).read_text(), rel


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
    files = git(bare, "ls-tree", "-r", "--name-only", "main", env=env).split()
    assert "web/where-to-live-towns/a.html" in files
    assert "web/where-to-live-towns/evil.js" not in files
    assert git(bare, "show", "main:web/data/other.json", env=env) == '{"v": "old"}\n'


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
