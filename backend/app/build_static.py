"""Build static data bundles for the app (served by Vercel from web/data/).

Run daily by .github/workflows/data.yml:
    cd backend && python -m app.build_static ../web/data

Writes (all compact JSON, keys documented in app/lib/data.dart):
    bus_stops.json   LTA bus stops (required; the build fails without it)
    hawkers.json     NEA hawker centres and closure dates
    dengue.json      NEA active dengue clusters
    poi.json         MRT stations, schools, preschools, parks, libraries, CCs, sports
    carparks.json    HDB car parks (SVY21 converted to lat/lng)
    hdb_blocks.json  HDB residential blocks with coordinates (OneMap, cached)
    hdb_resale.json  resale medians per block and town, last 24 months
    hdb_rent.json    median rent per town, last 6 months
    prayer.json      MUIS prayer times for the year
    manifest.json    {"version", "files": {name: {path, count, sha256}}}

Optional bundles are best effort: if one upstream fails, the previous file stays.
"""

import asyncio
import hashlib
import json
import logging
import sys
from datetime import date
from pathlib import Path

import httpx

from . import bundles as b
from .config import get_settings
from .sources import Sources, compact_bus_stops

log = logging.getLogger(__name__)

MIN_EXPECTED_STOPS = 4000  # Singapore has ~5,000; fewer means a broken upstream response
GEOCODE_CACHE = Path(__file__).resolve().parent.parent / "data" / "geocode.json"

# Minimum sizes below which a fresh bundle is treated as broken and not published.
MIN_COUNTS = {"hawkers": 80, "carparks": 1500, "hdb_blocks": 100, "prayer": 300}


def _dump(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()


def _count(obj) -> int:
    if isinstance(obj, list):
        return len(obj)
    if isinstance(obj, dict):
        for k in ("clusters", "blocks", "towns", "days"):
            if k in obj:
                return len(obj[k])
        return sum(len(v) for v in obj.values() if isinstance(v, list))
    return 0


async def build(
    out_dir: Path,
    client: httpx.AsyncClient | None = None,
    *,
    only_bus_stops: bool = False,
    geocode_cache: Path | None = GEOCODE_CACHE,
    geocode_budget_s: float = 2400,
    pause: float = 12.0,
    today: date | None = None,
) -> dict:
    settings = get_settings()
    own = client is None
    client = client or httpx.AsyncClient(timeout=60)
    out_dir.mkdir(parents=True, exist_ok=True)
    results: dict[str, object] = {}
    try:
        stops = compact_bus_stops(await Sources(settings, client).bus_stops())
        if len(stops) < MIN_EXPECTED_STOPS:
            raise RuntimeError(f"only {len(stops)} bus stops returned; refusing to publish")
        results["bus_stops"] = stops

        if not only_bus_stops:
            dg = b.DataGov(client, settings.datagov_api_key, pause=pause)
            geo = b.Geocoder(client, geocode_cache, budget_s=geocode_budget_s)

            async def attempt(name: str, coro) -> None:
                try:
                    data = await coro
                except Exception as e:  # keep yesterday's file
                    log.warning("bundle %s failed: %s", name, e)
                    return
                if _count(data) < MIN_COUNTS.get(name, 1):
                    log.warning("bundle %s too small (%d); keeping previous", name, _count(data))
                    return
                results[name] = data

            await attempt("hawkers", b.build_hawkers(dg))
            await attempt("dengue", b.build_dengue(dg))
            await attempt("carparks", b.build_carparks(dg))
            await attempt("prayer", b.build_prayer(dg))
            await attempt("poi", b.build_poi(dg, geo))
            try:
                blocks, resale, rent = await b.build_homes(dg, geo, today or date.today())
                for name, data in (
                    ("hdb_blocks", blocks),
                    ("hdb_resale", resale),
                    ("hdb_rent", rent),
                ):
                    if _count(data) >= MIN_COUNTS.get(name, 1):
                        results[name] = data
            except Exception as e:
                log.warning("homes bundles failed: %s", e)
            geo.save()
            log.info("geocoded %d new addresses", geo.looked_up)
    finally:
        if own:
            await client.aclose()

    files = {}
    for name, data in results.items():
        payload = _dump(data)
        (out_dir / f"{name}.json").write_bytes(payload)
    # Describe every bundle on disk, including ones kept from a previous run.
    for path in sorted(out_dir.glob("*.json")):
        name = path.stem
        if name == "manifest":
            continue
        payload = path.read_bytes()
        data = results.get(name)
        if data is None:
            data = json.loads(payload)
        files[name] = {
            "path": path.name,
            "count": _count(data),
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    version = hashlib.sha256("".join(f["sha256"] for f in files.values()).encode()).hexdigest()
    manifest = {"version": version[:12], "files": files}
    (out_dir / "manifest.json").write_bytes(_dump(manifest))
    return manifest


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "../web/data")
    summary = asyncio.run(build(target))
    print(json.dumps({k: v["count"] for k, v in summary["files"].items()}, indent=2))
