"""Turn a `flutter test --file-reporter json:…` file into one GitHub annotation listing
every failed test and the first line of its error, so failures are readable on the commit."""
import json
import sys

names, errors, failed = {}, {}, []
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
        errors.setdefault(e["testID"], msg[:200])
    elif kind == "testDone" and e.get("result") != "success" and not e.get("hidden"):
        failed.append(e["testID"])

lines = [f"{names.get(t, t)} :: {errors.get(t, '')}" for t in failed]
print(f"{len(lines)} tests failed", file=sys.stderr)
if lines:
    body = "%0A".join(x.replace("%", "%25").replace("\r", "").replace("\n", " ") for x in lines[:300])
    print(f"::error title={len(lines)} tests failed::{body}")
