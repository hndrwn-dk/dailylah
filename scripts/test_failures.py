"""Turn a `flutter test --file-reporter json:…` file into one GitHub annotation listing
every failed test and the first line of its error, so failures are readable on the commit."""
import json
import re
import sys

names, errors, failed, details = {}, {}, [], {}
for line in open(sys.argv[1], encoding="utf-8"):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    kind = e.get("type")
    if kind == "testStart":
        names[e["test"]["id"]] = e["test"]["name"]
    elif kind == "error":
        msg = next((x.strip() for x in str(e.get("error", "")).splitlines() if x.strip()), "")
        if not msg.startswith("Test failed. See exception logs above"):
            errors.setdefault(e["testID"], msg[:200])
    elif kind == "print":
        # Framework errors (layout overflow…) are printed, not reported as "error" events.
        text = str(e.get("message", ""))
        what = re.search(r"(A Render\w+ overflowed by [^\n]+|Exception: [^\n]+)", text)
        where = re.findall(r"(lib/[\w/]+\.dart:\d+)", text)
        if what:
            found = what.group(1).strip() + (f" @ {where[0]}" if where else "")
            seen = details.setdefault(e["testID"], [])
            if found not in seen:
                seen.append(found)
    elif kind == "testDone" and e.get("result") != "success" and not e.get("hidden"):
        failed.append(e["testID"])

lines = [
    f"{names.get(t, t)} :: " + (" | ".join(details.get(t, [])[:3]) or errors.get(t, ""))
    for t in failed
]
print(f"{len(lines)} tests failed", file=sys.stderr)
if lines:
    body = "%0A".join(x.replace("%", "%25").replace("\r", "").replace("\n", " ") for x in lines[:300])
    print(f"::error title={len(lines)} tests failed::{body}")
