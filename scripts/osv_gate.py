"""Turn osv-scanner JSON into GitHub annotations and a pass/fail (docs/QA.md, "Security scans").

Usage: python3 scripts/osv_gate.py osv.json

- High or Critical (CVSS >= 7.0): error, the job fails.
- Medium, Low or no score: warning only.
Vulnerabilities listed in osv-scanner.toml (the baseline, Low only, each with a reason) are
already left out by osv-scanner.
"""

import json
import os
import sys

HIGH = 7.0


def score(group: dict) -> float | None:
    try:
        return float(group.get("max_severity") or "")
    except ValueError:
        return None


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        report = json.load(f)
    failed = 0
    rows = []
    for result in report.get("results") or []:
        source = os.path.relpath(result.get("source", {}).get("path", "?"), os.getcwd())
        for pkg in result.get("packages") or []:
            info = pkg.get("package", {})
            name = f"{info.get('name')} {info.get('version')} ({info.get('ecosystem')})"
            summaries = {v["id"]: v.get("summary", "") for v in pkg.get("vulnerabilities") or []}
            for group in pkg.get("groups") or []:
                ids = group.get("ids") or []
                s = score(group)
                level = "error" if s is not None and s >= HIGH else "warning"
                failed += level == "error"
                summary = next((summaries[i] for i in ids if summaries.get(i)), "")
                label = "no score" if s is None else f"CVSS {s}"
                msg = f"{name}: {', '.join(ids)} ({label}) {summary}".strip()
                print(f"::{level} file={source},title=osv-scanner::{msg}")
                rows.append(f"| {level} | {name} | {', '.join(ids)} | {label} |")
    lines = [f"osv-scanner: {len(rows)} finding(s), {failed} High/Critical."]
    if rows:
        header = ["| Level | Package | Advisory | Severity |", "| --- | --- | --- | --- |"]
        lines += ["", *header, *rows]
    print("\n".join(lines))
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
