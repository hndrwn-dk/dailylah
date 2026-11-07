"""Data for the "Where to live?" page on dailylah.sg (docs/WHERE_TO_LIVE.md).

Run weekly by .github/workflows/where-to-live.yml:
    cd backend && python -m app.where_to_live ../web/data            # writes the files
    cd backend && python -m app.where_to_live ../web/data --dry-run  # prints only

Writes web/data/where-to-live.json: for each HDB town, the median rent and resale price per
flat type (HDB quarterly medians on data.gov.sg) and the public transport time to six office
areas (OneMap routing, a weekday at 08:30). Not part of the app's manifest.

Routes rarely change, so they are cached in backend/data/where_to_live_routes.json and only
asked again after ROUTE_MAX_AGE_DAYS; prices are read on every run. The output file is only
rewritten (with a new generated_at) when its data changed, so a quiet week makes no commit.
"""

import argparse
import asyncio
import json
import logging
import re
import sys
import time
from collections.abc import Awaitable, Callable
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import httpx

from .bundles import DataGov
from .config import get_settings
from .onemap import OneMap

log = logging.getLogger("dailylah.where_to_live")

RENT_MEDIANS = "d_23000a00c52996c55106084ed0339566"  # HDB median rent by town and flat type
RESALE_MEDIANS = "d_b51323a474ba789fb4cc3db58a3116d4"  # HDB median resale price, same split
ROUTE_URL = "https://www.onemap.gov.sg/api/public/routingsvc/route"

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
POINTS_FILE = DATA_DIR / "where_to_live_points.json"
ROUTE_CACHE_FILE = DATA_DIR / "where_to_live_routes.json"
OUT_NAME = "where-to-live.json"

SGT = ZoneInfo("Asia/Singapore")
DEPART_TIME = "08:30:00"
ROUTE_MAX_AGE_DAYS = 30
# A median older than this many quarters (counting the latest) counts as "not enough data".
QUARTERS_KEPT = 4
FLAT_TYPES = ["1-ROOM", "2-ROOM", "3-ROOM", "4-ROOM", "5-ROOM", "EXECUTIVE"]
# Below these the run is treated as broken and nothing is written.
MIN_TOWNS_WITH_PRICES = 20
MIN_COMMUTE_SHARE = 0.75

ATTRIBUTION = (
    "Contains information from HDB median rent and resale price datasets accessed from "
    "data.gov.sg, made available under the Singapore Open Data Licence. Travel times from "
    "OneMap, Singapore Land Authority."
)

# Town names as the datasets may spell them -> our key (letters and digits only).
TOWN_ALIASES = {"CENTRAL": "CENTRALAREA"}


class BuildError(RuntimeError):
    """The fresh data looks broken; keep the published file."""


# ---------------------------------------------------------------- parsing


def town_key(name: Any) -> str:
    key = re.sub(r"[^A-Z0-9]", "", str(name or "").upper())
    return TOWN_ALIASES.get(key, key)


def norm_flat(value: Any) -> str | None:
    """'3-RM', '3 ROOM', '3-room' -> '3-ROOM'; 'EXEC' -> 'EXECUTIVE'; anything else None."""
    s = str(value or "").upper().strip()
    if s.startswith("EXEC"):
        return "EXECUTIVE"
    m = re.fullmatch(r"([1-5])\s*[- ]?\s*(RM|ROOM)S?", s)
    return f"{m.group(1)}-ROOM" if m else None


def norm_quarter(value: Any) -> str | None:
    """'2026-Q3', '2026 Q3', '2026Q3', 'Q3 2026' -> '2026-Q3'."""
    s = str(value or "").upper().strip()
    m = re.fullmatch(r"(\d{4})\s*-?\s*Q([1-4])", s) or re.fullmatch(r"Q([1-4])\s*-?\s*(\d{4})", s)
    if not m:
        return None
    year, q = (m.group(1), m.group(2)) if len(m.group(1)) == 4 else (m.group(2), m.group(1))
    return f"{year}-Q{q}"


def quarter_index(q: str) -> int:
    year, n = q.split("-Q")
    return int(year) * 4 + int(n) - 1


def parse_price(value: Any) -> int | None:
    """A median as an int; 'na', '-', '' (fewer than 20 transactions) and junk are None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int | float):
        return int(round(value)) if value > 0 else None
    s = re.sub(r"[,$\s]", "", str(value or ""))
    try:
        v = float(s)
    except ValueError:
        return None
    return int(round(v)) if v > 0 else None


def pick_fields(rows: list[dict]) -> dict[str, str]:
    """Which columns hold the quarter, town, flat type and median. Raises BuildError."""
    keys = [k for k in (rows[0] if rows else {}) if k != "_id"]

    def find(*words: str) -> str | None:
        return next((k for k in keys if any(w in k.lower() for w in words)), None)

    fields = {"quarter": find("quarter"), "town": find("town"), "flat": find("flat")}
    used = set(fields.values())
    rest = [k for k in keys if k not in used]
    fields["value"] = next(
        (k for k in rest if any(w in k.lower() for w in ("median", "rent", "price"))),
        rest[0] if len(rest) == 1 else None,
    )
    missing = [name for name, k in fields.items() if not k]
    if missing:
        raise BuildError(f"columns not found: {missing} in {keys}")
    return fields  # type: ignore[return-value]


def parse_medians(rows: list[dict]) -> tuple[str, dict[str, dict], dict]:
    """(latest quarter, {town key: {flat type: {"median", "quarter"} | None}}, notes).

    Each cell takes the latest of the last QUARTERS_KEPT quarters that has a number; a cell
    with only 'na' in that window is None. Every town gets every flat type that appears in
    the dataset, so a missing type reads as "not enough data" too."""
    fields = pick_fields(rows)
    cells: dict[tuple[str, str], list[tuple[str, int | None]]] = {}
    unknown_flats: set[str] = set()
    bad_quarters = 0
    for row in rows:
        q = norm_quarter(row.get(fields["quarter"]))
        if not q:
            bad_quarters += 1
            continue
        flat = norm_flat(row.get(fields["flat"]))
        if not flat:
            unknown_flats.add(str(row.get(fields["flat"])))
            continue
        town = town_key(row.get(fields["town"]))
        cells.setdefault((town, flat), []).append((q, parse_price(row.get(fields["value"]))))
    if not cells:
        raise BuildError("no usable rows")
    latest = max(q for values in cells.values() for q, _ in values)
    oldest = quarter_index(latest) - QUARTERS_KEPT + 1
    flats = [f for f in FLAT_TYPES if any(flat == f for _, flat in cells)]
    out: dict[str, dict] = {}
    for town in sorted({t for t, _ in cells}):
        out[town] = {}
        for flat in flats:
            found = [
                (q, v)
                for q, v in cells.get((town, flat), [])
                if v is not None and quarter_index(q) >= oldest
            ]
            if found:
                q, v = max(found)
                out[town][flat] = {"median": v, "quarter": q}
            else:
                out[town][flat] = None
    notes = {
        "fields": fields,
        "rows": len(rows),
        "unknown_flat_types": sorted(unknown_flats),
        "rows_without_quarter": bad_quarters,
    }
    return latest, out, notes


# ---------------------------------------------------------------- routes


def depart_day(today: date, holidays: set[str]) -> date:
    """The next weekday after today that is not a public holiday."""
    d = today + timedelta(days=1)
    while d.weekday() >= 5 or d.isoformat() in holidays:
        d += timedelta(days=1)
    return d


def parse_fare(value: Any) -> int | None:
    """OneMap's adult card fare for an itinerary ("1.94", dollars) in cents; None if missing."""
    if isinstance(value, bool):
        return None
    try:
        cents = round(float(str(value).replace("$", "").strip()) * 100)
    except ValueError:
        return None
    # A single MRT/bus trip in Singapore costs well under $10; anything else is not a fare.
    return cents if 0 < cents < 1000 else None


def parse_route(body: Any) -> dict | None:
    """{"min", "transfers", "fare"} of the fastest itinerary in a OneMap routing answer.
    fare is the adult card fare in cents, or None when OneMap gives none."""
    plan = body.get("plan") if isinstance(body, dict) else None
    its = [i for i in ((plan or {}).get("itineraries") or []) if isinstance(i, dict)]
    its = [i for i in its if isinstance(i.get("duration"), int | float) and i["duration"] > 0]
    if not its:
        return None
    best = min(its, key=lambda i: i["duration"])
    transfers = best.get("transfers")
    if not isinstance(transfers, int):
        legs = [leg for leg in best.get("legs") or [] if isinstance(leg, dict)]
        transfers = max(0, sum(1 for leg in legs if leg.get("transitLeg")) - 1)
    return {
        "min": int(round(best["duration"] / 60)),
        "transfers": transfers,
        "fare": parse_fare(best.get("fare")),
    }


def route_sample(body: Any) -> dict:
    """A short look at a OneMap answer for the dry-run log (no account data in it)."""
    if not isinstance(body, dict):
        return {"type": type(body).__name__}
    plan = body.get("plan") if isinstance(body.get("plan"), dict) else {}
    its = plan.get("itineraries") or []
    first = its[0] if its and isinstance(its[0], dict) else {}
    return {
        "keys": sorted(body),
        "plan_keys": sorted(plan),
        "itineraries": len(its),
        "first": {k: v for k, v in first.items() if isinstance(v, int | float | str | bool)},
        "first_legs": [
            {k: leg.get(k) for k in ("mode", "route", "duration", "transitLeg")}
            for leg in first.get("legs") or []
            if isinstance(leg, dict)
        ],
    }


# Commute value for a town that is itself the office area (Jurong East, Woodlands).
SAME_AREA = {"min": None, "transfers": None, "same_area": True}

Sleep = Callable[[float], Awaitable[None]]


async def fetch_route(
    om: OneMap,
    start: tuple[float, float],
    end: tuple[float, float],
    day: date,
    *,
    attempts: int = 3,
    sleep: Sleep = asyncio.sleep,
) -> tuple[dict | None, Any]:
    """(parsed route or None, raw JSON body or None). Retries 429, 5xx and network errors
    with backoff; other answers are final."""
    params = {
        "start": f"{start[0]},{start[1]}",
        "end": f"{end[0]},{end[1]}",
        "routeType": "pt",
        "date": day.strftime("%m-%d-%Y"),
        "time": DEPART_TIME,
        "mode": "TRANSIT",
        "maxWalkDistance": "1000",
        "numItineraries": "3",
    }
    for attempt in range(attempts):
        try:
            r = await om.get(ROUTE_URL, params)
        except httpx.HTTPError as e:
            log.warning("OneMap route: %s (attempt %d)", type(e).__name__, attempt + 1)
        else:
            if r.status_code == 429 or r.status_code >= 500:
                log.warning("OneMap route: HTTP %s (attempt %d)", r.status_code, attempt + 1)
            elif not r.is_success:
                log.warning("OneMap route: HTTP %s", r.status_code)
                return None, None
            else:
                try:
                    body = r.json()
                except ValueError:
                    return None, None
                return parse_route(body), body
        if attempt + 1 < attempts:
            await sleep(2.0 * 2**attempt)
    return None, None


def _usable(entry: Any, start: list[float], end: list[float]) -> bool:
    """A cached route for these points, good enough to fall back on when OneMap fails."""
    return (
        isinstance(entry, dict)
        and entry.get("from") == start
        and entry.get("to") == end
        and isinstance(entry.get("min"), int)
    )


def _cached(entry: Any, start: list[float], end: list[float]) -> bool:
    # Entries cached before fares were kept are asked again once.
    return _usable(entry, start, end) and "fare" in entry


def _route(entry: dict) -> dict:
    return {"min": entry["min"], "transfers": entry.get("transfers"), "fare": entry.get("fare")}


async def build_routes(
    om: OneMap,
    towns: list[dict],
    areas: list[dict],
    cache: dict,
    today: date,
    holidays: set[str],
    *,
    pause: float = 0.25,
    sleep: Sleep = asyncio.sleep,
) -> tuple[dict, dict, dict]:
    """({town id: {area id: {"min", "transfers", "fare"} | SAME_AREA | None}}, new cache, notes).

    None means no route is known; SAME_AREA means the town is the office area."""
    day = depart_day(today, holidays)
    fresh_after = (today - timedelta(days=ROUTE_MAX_AGE_DAYS)).isoformat()
    new_cache: dict = {}
    out: dict[str, dict] = {}
    notes: dict[str, Any] = {"depart": f"{day.isoformat()} {DEPART_TIME}", "sample": None}
    counts = {"cached": 0, "fetched": 0, "failed_used_old": 0, "failed": 0, "no_fare": 0}
    for town in towns:
        out[town["id"]] = {}
        for area in areas:
            key = f"{town['id']}|{area['id']}"
            start, end = [town["lat"], town["lng"]], [area["lat"], area["lng"]]
            old = cache.get(key)
            if town["id"] == area["id"] or start == end:
                # The town is the office area: the page shows "In this area", not a time.
                out[town["id"]][area["id"]] = dict(SAME_AREA)
                continue
            if _cached(old, start, end) and str(old.get("at", "")) >= fresh_after:
                new_cache[key] = old
                out[town["id"]][area["id"]] = _route(old)
                counts["cached"] += 1
                continue
            route, body = await fetch_route(
                om, (start[0], start[1]), (end[0], end[1]), day, sleep=sleep
            )
            if body is not None and notes["sample"] is None:
                notes["sample"] = {"pair": key, **route_sample(body)}
            await sleep(pause)  # stay well under OneMap's 250 requests/minute
            if route:
                new_cache[key] = {"from": start, "to": end, **route, "at": today.isoformat()}
                out[town["id"]][area["id"]] = route
                counts["fetched"] += 1
                if route["fare"] is None:
                    counts["no_fare"] += 1
            elif _usable(old, start, end):
                new_cache[key] = old
                out[town["id"]][area["id"]] = _route(old)
                counts["failed_used_old"] += 1
            else:
                out[town["id"]][area["id"]] = None
                counts["failed"] += 1
    notes.update(counts)
    return out, new_cache, notes


# ---------------------------------------------------------------- assemble


def assemble(
    points: dict,
    rent: tuple[str, dict],
    resale: tuple[str, dict],
    commute: dict,
) -> dict:
    """The published JSON without generated_at. Raises BuildError when it looks broken."""
    rent_q, rent_by_town = rent
    resale_q, resale_by_town = resale
    towns = []
    priced = 0
    for t in points["towns"]:
        key = town_key(t["town"])
        r, s = rent_by_town.get(key, {}), resale_by_town.get(key, {})
        if any(r.values()) or any(s.values()):
            priced += 1
        towns.append(
            {
                "id": t["id"],
                "name": t["name"],
                "station": t["station"],
                "lat": t["lat"],
                "lng": t["lng"],
                "rent": r,
                "resale": s,
                "commute": commute.get(t["id"], {}),
            }
        )
    if priced < MIN_TOWNS_WITH_PRICES:
        raise BuildError(f"only {priced} towns have prices")
    pairs = [v for c in commute.values() for v in c.values()]
    share = sum(1 for v in pairs if v is not None) / len(pairs) if pairs else 0.0
    if share < MIN_COMMUTE_SHARE:
        raise BuildError(f"only {share:.0%} of commutes are known")
    return {
        "rent_quarter": rent_q,
        "resale_quarter": resale_q,
        "commute_depart": "weekday 08:30",
        "areas": [
            {k: a[k] for k in ("id", "name", "station", "lat", "lng")} for a in points["areas"]
        ],
        "towns": towns,
        "attribution": ATTRIBUTION,
    }


def _dump(obj: Any) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()


def publish(path: Path, data: dict, now: datetime) -> bool:
    """Write data with a new generated_at, unless only generated_at would change."""
    try:
        old = json.loads(path.read_bytes())
    except (OSError, ValueError):
        old = None
    if isinstance(old, dict):
        old.pop("generated_at", None)
        if old == data:
            return False
    stamp = now.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    path.write_bytes(_dump({"generated_at": stamp, **data}))
    return True


def save_cache(path: Path, cache: dict) -> bool:
    payload = json.dumps(cache, indent=1, sort_keys=True) + "\n"
    try:
        if path.read_text() == payload:
            return False
    except OSError:
        pass
    path.write_text(payload)
    return True


def _load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


async def build(
    dg: DataGov,
    om: OneMap,
    today: date,
    out_dir: Path,
    cache: dict,
    *,
    sleep: Sleep = asyncio.sleep,
) -> tuple[dict, dict, dict]:
    """(data without generated_at, new route cache, report). Raises BuildError."""
    points = json.loads(POINTS_FILE.read_text())
    holidays = {
        str(h.get("d")) for h in _load_json(out_dir / "holidays.json", []) if isinstance(h, dict)
    }
    report: dict[str, Any] = {}
    t0 = time.monotonic()
    datasets = {}
    for name, dataset in (("rent", RENT_MEDIANS), ("resale", RESALE_MEDIANS)):
        rows = await dg.rows(dataset)
        report[f"{name}_sample_rows"] = rows[:3]
        latest, by_town, notes = parse_medians(rows)
        known = {town_key(t["town"]) for t in points["towns"]}
        notes["latest_quarter"] = latest
        notes["towns_not_in_points"] = sorted(set(by_town) - known)
        notes["points_without_data"] = sorted(known - set(by_town))
        report[name] = notes
        datasets[name] = (latest, by_town)
    report["prices_seconds"] = round(time.monotonic() - t0, 1)
    t1 = time.monotonic()
    commute, new_cache, route_notes = await build_routes(
        om, points["towns"], points["areas"], cache, today, holidays, sleep=sleep
    )
    report["routes"] = route_notes
    report["routes_seconds"] = round(time.monotonic() - t1, 1)
    report["datagov_key_rejected"] = dg.key.rejected
    try:
        data = assemble(points, datasets["rent"], datasets["resale"], commute)
    except BuildError as e:
        report["error"] = str(e)
        raise BuildError(json.dumps(report, default=str)) from e
    return data, new_cache, report


async def main(out_dir: Path, dry_run: bool) -> int:
    settings = get_settings()
    today = datetime.now(SGT).date()
    cache = _load_json(ROUTE_CACHE_FILE, {})
    async with httpx.AsyncClient(timeout=60, follow_redirects=True) as client:
        dg = DataGov(client, settings.datagov_api_key)
        om = OneMap(client, settings.onemap_email, settings.onemap_password)
        if not om.configured:
            log.warning("ONEMAP_EMAIL / ONEMAP_PASSWORD not set: only cached routes are used")
        try:
            data, new_cache, report = await build(dg, om, today, out_dir, cache)
        except BuildError as e:
            print("where-to-live: build failed, nothing written:\n" + str(e))
            return 1
    print("where-to-live report:")
    print(json.dumps(report, indent=1, default=str))
    if dry_run:
        print("where-to-live JSON (dry run, first two towns):")
        print(json.dumps({**data, "towns": data["towns"][:2]}, indent=1, ensure_ascii=False))
        print(f"dry run: {len(_dump(data))} bytes, {len(data['towns'])} towns, nothing written")
        return 0
    changed = publish(out_dir / OUT_NAME, data, datetime.now(UTC))
    cache_changed = save_cache(ROUTE_CACHE_FILE, new_cache)
    print(
        f"{OUT_NAME}: {'updated' if changed else 'unchanged'}; "
        f"route cache: {'updated' if cache_changed else 'unchanged'}"
    )
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out_dir", nargs="?", default="../web/data", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="print the report, write nothing")
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args.out_dir, args.dry_run)))
