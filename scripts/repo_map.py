"""Write docs/REPO_MAP.md and the AGENTS.md copies of every CLAUDE.md (agent docs).

Usage:
  python3 scripts/repo_map.py           # rewrite docs/REPO_MAP.md and every AGENTS.md
  python3 scripts/repo_map.py --check   # exit 1 when either is out of date (CI, docs workflow)

AGENTS.md (read by Cursor, Codex and other agents) is the CLAUDE.md in the same folder with
" (Cursor, Codex, etc.)" added to the first line. Edit CLAUDE.md, never AGENTS.md.

The map lists every Dart file in app/lib with its public top-level classes, enums, mixins,
extensions, typedefs and functions, every Riverpod provider (`final xProvider = ...` at top
level), and every backend endpoint (FastAPI decorators in backend/app). It reads the source
with regular expressions (Dart) and `ast` (Python), needs no Flutter or packages, and has no
dates or line counts, so it only changes when the structure changes.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_LIB = ROOT / "app" / "lib"
BACKEND_APP = ROOT / "backend" / "app"
OUT = ROOT / "docs" / "REPO_MAP.md"
AGENT_DOC_DIRS = [ROOT, ROOT / "app", ROOT / "backend"]
AGENTS_SUFFIX = " (Cursor, Codex, etc.)"

TYPE_RE = re.compile(
    r"^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*"
    r"(class|enum|mixin|extension|typedef)\s+([A-Za-z]\w*)"
)
PROVIDER_RE = re.compile(r"^final\s+([A-Za-z]\w*Provider)\s*=\s*([A-Za-z][\w.]*)?")
# A top-level function or getter: a return type, then a public name, then `(` or ` get`.
FUNC_RE = re.compile(
    r"^(?!(?:import|export|part|library|class|enum|mixin|extension|typedef|const|final|var|"
    r"late|abstract|sealed|base|interface|static|external|return|if|for|while|switch)\b)"
    r"[A-Za-z][\w<>?,\[\]. ]*?\s+(?:get\s+)?([a-z]\w*)\s*(?:<[^>()]*>)?\s*(?:\(|=>|\{)"
)
ROUTE_METHODS = {"get", "post", "put", "patch", "delete"}


def dart_symbols(text: str) -> tuple[list[str], list[str], list[tuple[str, str]]]:
    """Public types, public functions and providers declared at the top level of a file."""
    types: list[str] = []
    funcs: list[str] = []
    providers: list[tuple[str, str]] = []
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if not line or line[0] in " \t}/@)":
            continue  # only column-0 declarations are top level
        if m := TYPE_RE.match(line):
            kind, name = m.groups()
            if not name.startswith("_"):
                types.append(f"{name} ({kind})" if kind != "class" else name)
            continue
        if m := PROVIDER_RE.match(line):
            name, kind = m.groups()
            if not kind:  # `final xProvider =` with the value on the next line
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                kind = re.match(r"[A-Za-z][\w.]*", nxt).group(0) if nxt else "?"
            providers.append((name, kind))
            continue
        if m := FUNC_RE.match(line):
            name = m.group(1)
            if name not in funcs:
                funcs.append(name)
    return types, funcs, providers


def endpoints() -> list[tuple[str, str, str, str]]:
    """(method, path, handler, file) for every FastAPI route decorator in backend/app."""
    found = []
    for path in sorted(BACKEND_APP.rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for dec in node.decorator_list:
                if not (isinstance(dec, ast.Call) and isinstance(dec.func, ast.Attribute)):
                    continue
                if dec.func.attr not in ROUTE_METHODS or not dec.args:
                    continue
                arg = dec.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    rel = path.relative_to(ROOT).as_posix()
                    found.append((dec.func.attr.upper(), arg.value, node.name, rel))
    return sorted(found, key=lambda e: (e[1], e[0]))


def build() -> str:
    out = [
        "# Repo map",
        "",
        "Made by `scripts/repo_map.py`; do not edit by hand. Run `python3 scripts/repo_map.py`",
        "after adding, moving, renaming or removing a file, a public class or function, a provider",
        "or an endpoint. CI (`docs` workflow) fails when this file is out of date. What each",
        "feature does and why: `app/CLAUDE.md` (Feature map) and `backend/CLAUDE.md`.",
        "",
    ]
    all_providers: list[tuple[str, str, str]] = []
    files = sorted(APP_LIB.rglob("*.dart"))
    out += [f"## App: `app/lib` ({len(files)} files)", ""]
    for path in files:
        rel = path.relative_to(ROOT / "app").as_posix()
        text = path.read_text(encoding="utf-8")
        types, funcs, providers = dart_symbols(text)
        all_providers += [(n, k, rel) for n, k in providers]
        out.append(f"### `{rel}`")
        if types:
            out.append(f"- Types: {', '.join(f'`{t}`' for t in types)}")
        if funcs:
            out.append(f"- Functions: {', '.join(f'`{f}`' for f in funcs)}")
        if providers:
            out.append(f"- Providers: {len(providers)} (listed below)")
        if not (types or funcs or providers):
            out.append("- No public top-level declarations.")
        out.append("")

    out += [f"## Riverpod providers ({len(all_providers)})", "", "| Provider | Kind | File |"]
    out.append("| --- | --- | --- |")
    out += [f"| `{n}` | `{k}` | `{f}` |" for n, k, f in all_providers]
    out.append("")

    eps = endpoints()
    out += [f"## Backend endpoints ({len(eps)})", "", "| Method | Path | Handler | File |"]
    out.append("| --- | --- | --- | --- |")
    out += [f"| {m} | `{p}` | `{h}` | `{f}` |" for m, p, h, f in eps]
    out.append("")
    return "\n".join(out)


def agents_text(claude: str) -> str:
    """AGENTS.md for a CLAUDE.md: the same text, with the agents named in the title."""
    first, _, rest = claude.partition("\n")
    return first + AGENTS_SUFFIX + "\n" + rest


def outputs() -> dict[Path, str]:
    files = {OUT: build()}
    for folder in AGENT_DOC_DIRS:
        files[folder / "AGENTS.md"] = agents_text(
            (folder / "CLAUDE.md").read_text(encoding="utf-8")
        )
    return files


def main() -> int:
    files = outputs()
    if "--check" in sys.argv[1:]:
        stale = [
            p
            for p, text in files.items()
            if not p.exists() or p.read_text(encoding="utf-8") != text
        ]
        for p in stale:
            rel = p.relative_to(ROOT).as_posix()
            print(f"::error file={rel}::{rel} is out of date. Run: python3 scripts/repo_map.py")
        if stale:
            return 1
        print("docs/REPO_MAP.md and every AGENTS.md are up to date.")
        return 0
    for p, text in files.items():
        p.write_text(text, encoding="utf-8")
        print(f"Wrote {p.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
