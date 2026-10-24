"""Build static data bundles for the app (served by Vercel from web/data/).

Run daily by .github/workflows/data.yml:
    cd backend && python -m app.build_static ../web/data

Writes (all compact JSON, keys documented in app/lib/data.dart):
    bus_stops.json   LTA bus stops (required; the build fails without it)
    hawkers.json     NEA hawker centres and closure dates
    dengue.json      NEA active dengue clusters
    poi.json         MRT stations, schools, preschools, parks, libraries, CCs, sports
    carparks.json    HDB car parks (SVY21 converted to lat/lng)
    hdb_blocks.json  HDB residential blocks with coordinates and postal codes (footprints)
    hdb_resale.json  resale medians per block and town, last 24 months
    hdb_rent.json    median rent per town, last 6 months
    prayer.json      MUIS prayer times for the year
    holidays.json    MOM public holidays from a month ago onwards
    events.json      public events in the next 30 days (Eventfinda)
    taxi_stands.json LTA taxi stands and stops
    bus_routes.json  stop order per bus service and direction (for "buses that go home")
    bicycle_racks.json LTA bicycle racks
    mrt_stations.json MRT/LRT stations with line codes (for the MRT part of a trip)
    emergency.json   AEDs, A&E hospitals, fire stations, CHAS clinics, CD shelters
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
from .events import build_events
from .onemap import OneMap
from .sources import Sources, compact_bus_stops, compact_taxi_stands
from .ura import build_private

log = logging.getLogger(__name__)

MIN_EXPECTED_STOPS = 4000  # Singapore has ~5,000; fewer means a broken upstream response
GEOCODE_CACHE = Path(__file__).resolve().parent.parent / "data" / "geocode.json"

# Minimum sizes below which a fresh bundle is treated as broken and not published.
MIN_COUNTS = {
    "private_homes": 500,
    "halal": 1000,
    "around": 50,
    "taxi_stands": 100,
    "bus_routes": 300,
    "bicycle_racks": 50,
    "hawkers": 80,
    "carparks": 1500,
    "hdb_blocks": 100,
    "prayer": 300,
    "holidays": 5,
    "events": 1,
}


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
    report: dict = {"errors": {}}
    try:
        stops = compact_bus_stops(await Sources(settings, client).bus_stops())
        if len(stops) < MIN_EXPECTED_STOPS:
            raise RuntimeError(f"only {len(stops)} bus stops returned; refusing to publish")
        results["bus_stops"] = stops

        if not only_bus_stops:
            dg = b.DataGov(client, settings.datagov_api_key, pause=pause)
            om = OneMap(client, settings.onemap_email, settings.onemap_password)
            geo = b.Geocoder(client, geocode_cache, budget_s=geocode_budget_s, onemap=om)

            async def attempt(name: str, coro) -> None:
                try:
                    data = await coro
                except Exception as e:  # keep yesterday's file
                    log.warning("bundle %s failed: %s", name, e)
                    report["errors"][name] = repr(e)[:300]
                    return
                if _count(data) < MIN_COUNTS.get(name, 1):
                    log.warning("bundle %s too small (%d); keeping previous", name, _count(data))
                    report["errors"][name] = f"too small: {_count(data)}"
                    return
                results[name] = data

            async def taxi_stands() -> list[dict]:
                return compact_taxi_stands(await Sources(settings, client).taxi_stands())

            await attempt("taxi_stands", taxi_stands())

            async def bus_routes() -> dict:
                return await Sources(settings, client).bus_routes()

            await attempt("bus_routes", bus_routes())
            await attempt("bicycle_racks", b.build_racks(dg))
            await attempt("mrt_stations", b.build_mrt_stations(dg))
            await attempt("hawkers", b.build_hawkers(dg))
            await attempt("dengue", b.build_dengue(dg))
            await attempt("carparks", b.build_carparks(dg))
            await attempt("prayer", b.build_prayer(dg, today or date.today()))
            await attempt("holidays", b.build_holidays(dg, today or date.today()))
            await attempt(
                "events",
                build_events(
                    client,
                    today or date.today(),
                    settings.eventfinda_user,
                    settings.eventfinda_password,
                ),
            )
            await attempt("poi", b.build_poi(dg, geo))
            await attempt("emergency", b.build_emergency(dg, geo))
            await attempt("halal", b.build_halal(client))
            await attempt(
                "private_homes",
                build_private(client, settings.ura_access_key, today or date.today()),
            )
            await attempt("around", b.build_around(om, today or date.today()))
            block_town: dict[str, str] = {}
            try:
                resale = await b.build_resale(dg, today or date.today())
                block_town = resale.pop("block_town")
                if resale["blocks"]:
                    results["hdb_resale"] = resale
            except Exception as e:
                report["errors"]["hdb_resale"] = repr(e)[:300]
            await attempt("hdb_rent", b.build_rent(dg, today or date.today()))
            await attempt("hdb_blocks", b.build_blocks(dg, geo, block_town))
            geo.save()
            log.info("geocoded %d new addresses", geo.looked_up)
            # The workflow fails its last step on this, after the bundles are committed.
            report["datagov_key_rejected"] = dg.key.rejected
            report["geocoded_new"] = geo.looked_up
            report["geocode_cache"] = len(geo.cache)
    finally:
        if own:
            await client.aclose()

    # Public, non-personal build notes (upstream errors and counts) for debugging, since
    # Actions logs are not always at hand.
    if not only_bus_stops:
        report_path = (
            geocode_cache.parent if geocode_cache else out_dir.parent
        ) / "build_report.json"
        report["counts"] = {k: _count(v) for k, v in results.items()}
        try:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(json.dumps(report, indent=1, sort_keys=True))
        except OSError:
            pass

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
