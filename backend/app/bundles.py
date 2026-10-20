"""Static data bundles beyond bus stops: hawkers, dengue, POIs, car parks, HDB blocks,
resale and rent statistics, and prayer times.

Each `build_*` function downloads from data.gov.sg (or OneMap for geocoding) and returns
a compact JSON-ready object. The pure `compact_*` / `summarise_*` helpers do the shaping
and are unit-tested without network.
"""

import asyncio
import html
import json
import logging
import math
import re
import statistics
import time
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from typing import Any

import httpx

from .svy21 import to_latlon

log = logging.getLogger(__name__)

DATASTORE_URL = "https://data.gov.sg/api/action/datastore_search"
POLL_DOWNLOAD_URL = "https://api-open.data.gov.sg/v1/public/api/datasets/{id}/poll-download"
ONEMAP_SEARCH_URL = "https://www.onemap.gov.sg/api/common/elastic/search"

# data.gov.sg dataset ids (verified against the live catalogue, Oct 2026).
HAWKER_CLOSURES = "d_bda4baa634dd1cc7a6c7cad5f19e2d68"
DENGUE_CLUSTERS = "d_dbfabf16158d1b0e1c420627c0819168"
MRT_EXITS = "d_b39d3a0871985372d7e1637193335da5"
PRESCHOOLS = "d_61eefab99958fd70e6aab17320a71f1c"
SCHOOLS = "d_688b934f82c1059ed0a6993d2a829089"
COMMUNITY_CLUBS = "d_9de02d3fb33d96da1855f4fbef549a0f"
PARKS = "d_0542d48f0991541706b58059381a6eca"
LIBRARIES = "d_27b8dae65d9ca1539e14d09578b17cbf"
SPORT_FACILITIES = "d_2cfb0867cdeb2b7303068995699dc33b"
CARPARK_INFO = "d_23f946fa557947f93a8043bbef41dd09"
HDB_PROPERTY = "d_17f5382f26140b1fdae0ba2ef6239d2f"
RESALE = "d_8b84c4ee58e3cfc0ece0d773c8ca6abc"
RENTING_OUT = "d_c9f57187485a850908655db0e8cfe651"
PRAYER_TIMES = "d_d441e7242e78efc566024dd5b0d9829c"  # 2026 timetable

PAGE = 10000


def _r(x: float) -> float:
    return round(float(x), 5)


def _haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p = math.pi / 180
    a = (
        math.sin((lat2 - lat1) * p / 2) ** 2
        + math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin((lng2 - lng1) * p / 2) ** 2
    )
    return 12742000 * math.asin(math.sqrt(a))


# ---------------------------------------------------------------- downloads


class DataGov:
    """data.gov.sg helpers with gentle retries on 429 (the anonymous rate limit is low)."""

    def __init__(self, client: httpx.AsyncClient, api_key: str | None = None, pause: float = 12.0):
        self.client = client
        self.headers = {"x-api-key": api_key} if api_key else {}
        self.pause = pause

    async def _get(self, url: str, params: dict | None = None) -> httpx.Response:
        for attempt in range(6):
            resp = await self.client.get(url, params=params, headers=self.headers)
            if resp.status_code != 429:
                resp.raise_for_status()
                return resp
            await asyncio.sleep(self.pause * (attempt + 1))
        resp.raise_for_status()
        return resp

    async def rows(
        self, resource_id: str, sort: str | None = None, stop=None, max_rows: int = 400_000
    ) -> list[dict]:
        """All rows of a datastore table, page by page. `stop(row)` ends paging early
        (used with a descending sort to fetch only recent rows)."""
        out: list[dict] = []
        offset = 0
        while offset < max_rows:
            params: dict[str, Any] = {"resource_id": resource_id, "limit": PAGE, "offset": offset}
            if sort:
                params["sort"] = sort
            result = (await self._get(DATASTORE_URL, params)).json().get("result", {})
            records = result.get("records") or []
            for row in records:
                if stop and stop(row):
                    return out
                out.append(row)
            if len(records) < PAGE:
                break
            offset += PAGE
        return out

    async def geojson(self, dataset_id: str) -> dict:
        meta = (await self._get(POLL_DOWNLOAD_URL.format(id=dataset_id))).json()
        url = (meta.get("data") or {}).get("url")
        if not url:
            raise RuntimeError(f"no download url for {dataset_id}")
        resp = await self.client.get(url)
        resp.raise_for_status()
        return resp.json()


class Geocoder:
    """OneMap search with a JSON cache file committed to the repo, so each address is
    looked up once. Stops after `budget_s` seconds; the next daily run continues."""

    def __init__(self, client: httpx.AsyncClient, cache_path: Path | None, budget_s: float = 2400):
        self.client = client
        self.path = cache_path
        self.cache: dict[str, list[float] | None] = {}
        if cache_path and cache_path.exists():
            self.cache = json.loads(cache_path.read_text())
        self.deadline = time.monotonic() + budget_s
        self.looked_up = 0

    def save(self) -> None:
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(self.cache, sort_keys=True, separators=(",", ":")))

    async def find(self, query: str, block: str | None = None) -> tuple[float, float] | None:
        key = query.upper()
        if key in self.cache:
            hit = self.cache[key]
            return (hit[0], hit[1]) if hit else None
        if time.monotonic() > self.deadline:
            return None
        params = {"searchVal": query, "returnGeom": "Y", "getAddrDetails": "Y", "pageNum": 1}
        try:
            resp = await self.client.get(ONEMAP_SEARCH_URL, params=params)
            if resp.status_code == 429:
                await asyncio.sleep(30)
                return None
            results = resp.json().get("results") or []
        except (httpx.HTTPError, ValueError):
            return None
        self.looked_up += 1
        await asyncio.sleep(0.25)  # stay well under OneMap's 250 requests/minute
        pick = None
        for r in results:
            if block is None or str(r.get("BLK_NO", "")).upper() == block.upper():
                pick = r
                break
        if pick is None:
            self.cache[key] = None
            return None
        latlng = [_r(pick["LATITUDE"]), _r(pick["LONGITUDE"])]
        self.cache[key] = latlng
        return latlng[0], latlng[1]


# ---------------------------------------------------------------- hawkers


def _dmy(s: Any) -> date | None:
    m = re.fullmatch(r"\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*", str(s or ""))
    if not m:
        return None
    try:
        return date(int(m[3]), int(m[2]), int(m[1]))
    except ValueError:
        return None


def compact_hawkers(rows: list[dict]) -> list[dict]:
    """Hawker centres with their cleaning and other-works closures.
    Reason codes: "cleaning" or "works"; the app words them per language."""
    out = []
    for r in rows:
        if str(r.get("status", "")).lower() not in ("existing", ""):
            continue
        try:
            lat, lng = float(r["latitude_hc"]), float(r["longitude_hc"])
        except (KeyError, TypeError, ValueError):
            continue
        closures = []
        for q in ("q1", "q2", "q3", "q4"):
            a, b = _dmy(r.get(f"{q}_cleaningstartdate")), _dmy(r.get(f"{q}_cleaningenddate"))
            if a and b:
                closures.append([a.isoformat(), b.isoformat(), "cleaning"])
        a, b = _dmy(r.get("other_works_startdate")), _dmy(r.get("other_works_enddate"))
        if a and b:
            closures.append([a.isoformat(), b.isoformat(), "works"])
        out.append(
            {
                "id": str(r.get("serial_no") or r.get("_id")),
                "n": str(r.get("name", "")).strip(),
                "a": str(r.get("address_myenv", "")).strip(),
                "la": _r(lat),
                "lo": _r(lng),
                "c": closures,
            }
        )
    return out


# ---------------------------------------------------------------- GeoJSON helpers


def _props_name(props: dict) -> str:
    for k in ("NAME", "STATION_NA", "Name", "name"):
        v = props.get(k)
        if v and not str(v).lower().startswith("kml_"):
            return str(v).strip()
    return html_field(str(props.get("Description", "")), "NAME") or html_field(
        str(props.get("Description", "")), "CENTRE_NAME"
    )


def html_field(description: str, key: str) -> str:
    """Value of `<th>KEY</th><td>value</td>` in the HTML tables some GeoJSON layers use."""
    m = re.search(rf"<th>\s*{re.escape(key)}\s*</th>\s*<td>(.*?)</td>", description, re.S | re.I)
    return html.unescape(m[1]).strip() if m else ""


def _ring_points(geom: dict) -> list[tuple[float, float]]:
    """All (lng, lat) vertices of a Point, Polygon or MultiPolygon."""
    t, c = geom.get("type"), geom.get("coordinates")
    if t == "Point":
        return [(c[0], c[1])]
    if t == "Polygon":
        return [(p[0], p[1]) for p in c[0]]
    if t == "MultiPolygon":
        return [(p[0], p[1]) for poly in c for p in poly[0]]
    return []


def centroid(geom: dict) -> tuple[float, float, float] | None:
    """(lat, lng, radius_m) of a geometry; radius is 0 for points."""
    pts = _ring_points(geom or {})
    if not pts:
        return None
    lng = sum(p[0] for p in pts) / len(pts)
    lat = sum(p[1] for p in pts) / len(pts)
    radius = max(_haversine(lat, lng, p[1], p[0]) for p in pts)
    return lat, lng, radius


def compact_dengue(geo: dict) -> dict:
    out = []
    for f in geo.get("features", []):
        props = f.get("properties") or {}
        c = centroid(f.get("geometry"))
        if not c:
            continue
        locality = str(
            props.get("LOCALITY") or html_field(str(props.get("Description", "")), "LOCALITY")
        )
        cases = (
            props.get("CASE_SIZE")
            or html_field(str(props.get("Description", "")), "CASE_SIZE")
            or 0
        )
        out.append(
            {
                "loc": locality.strip(),
                "n": int(float(cases)),
                "la": _r(c[0]),
                "lo": _r(c[1]),
                "r": round(c[2]),
            }
        )
    out.sort(key=lambda x: -x["n"])
    return {"clusters": out}


def compact_points(geo: dict, detail_key: str | None = None) -> list[dict]:
    out = []
    for f in geo.get("features", []):
        props = f.get("properties") or {}
        c = centroid(f.get("geometry"))
        name = _props_name(props)
        if not c or not name:
            continue
        item = {"n": name.title() if name.isupper() else name, "la": _r(c[0]), "lo": _r(c[1])}
        if detail_key:
            d = props.get(detail_key) or html_field(str(props.get("Description", "")), detail_key)
            if d:
                item["d"] = str(d).strip()
        out.append(item)
    return out


def compact_mrt(geo: dict) -> list[dict]:
    """One point per station: the average of its exits."""
    by_station: dict[str, list[tuple[float, float]]] = defaultdict(list)
    for f in geo.get("features", []):
        props = f.get("properties") or {}
        name = str(
            props.get("STATION_NA") or html_field(str(props.get("Description", "")), "STATION_NA")
        )
        c = centroid(f.get("geometry"))
        if name and c:
            by_station[name.strip()].append((c[0], c[1]))
    out = []
    for name, pts in sorted(by_station.items()):
        lat = sum(p[0] for p in pts) / len(pts)
        lng = sum(p[1] for p in pts) / len(pts)
        out.append({"n": name.title(), "la": _r(lat), "lo": _r(lng)})
    return out


SPORT_KEYWORDS = ("swimming", "sports hall", "stadium", "activesg", "sport centre", "sports centre")


def compact_sports(rows: list[dict]) -> list[dict]:
    """Public pools, sports halls and stadiums (the census also lists condo gyms)."""
    venues: dict[str, dict] = {}
    for r in rows:
        name = str(r.get("VenueName", "")).strip()
        kind = str(r.get("SportsFacility", "")).strip()
        hay = f"{name} {kind}".lower()
        if not any(k in hay for k in SPORT_KEYWORDS):
            continue
        if any(
            k in name.lower() for k in ("condo", "residences", "condominium", "hotel", "club house")
        ):
            continue
        try:
            lat, lng = float(r["Latitude"]), float(r["Longitude"])
        except (KeyError, TypeError, ValueError):
            continue
        v = venues.setdefault(
            name,
            {
                "n": name.title() if name.isupper() else name,
                "la": _r(lat),
                "lo": _r(lng),
                "k": set(),
            },
        )
        v["k"].add(kind)
    out = []
    for v in venues.values():
        kinds = sorted(v.pop("k"))
        v["d"] = ", ".join(kinds[:3])
        out.append(v)
    return out


# ---------------------------------------------------------------- car parks


def compact_carparks(rows: list[dict]) -> list[dict]:
    out = []
    for r in rows:
        try:
            lat, lng = to_latlon(float(r["y_coord"]), float(r["x_coord"]))
        except (KeyError, TypeError, ValueError):
            continue
        out.append(
            {
                "id": str(r.get("car_park_no", "")).strip(),
                "a": str(r.get("address", "")).strip().title(),
                "la": _r(lat),
                "lo": _r(lng),
                "t": str(r.get("car_park_type", "")).strip(),
                "f": str(r.get("free_parking", "")).strip(),
                "n": str(r.get("night_parking", "")).strip(),
            }
        )
    return out


# ---------------------------------------------------------------- HDB resale and rent


def months_back(today: date, n: int) -> str:
    """'YYYY-MM' n months before today's month."""
    y, m = today.year, today.month - n
    while m <= 0:
        m += 12
        y -= 1
    return f"{y:04d}-{m:02d}"


def summarise_resale(rows: list[dict], since: str) -> dict:
    """Median price per block and flat type, plus town medians, for months >= since.
    Block entries: [median, count, latest month, latest price]."""
    per_block: dict[str, dict[str, list[tuple[str, int]]]] = defaultdict(lambda: defaultdict(list))
    per_town: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(list))
    block_town: dict[str, Counter] = defaultdict(Counter)
    months = []
    for r in rows:
        month = str(r.get("month", ""))
        if month < since:
            continue
        try:
            price = int(float(r["resale_price"]))
        except (KeyError, TypeError, ValueError):
            continue
        key = f"{str(r.get('block', '')).strip()}|{str(r.get('street_name', '')).strip()}"
        ft = str(r.get("flat_type", "")).strip()
        town = str(r.get("town", "")).strip()
        per_block[key][ft].append((month, price))
        per_town[town][ft].append(price)
        block_town[key][town] += 1
        months.append(month)
    blocks = {}
    for key, types in per_block.items():
        blocks[key] = {}
        for ft, sales in types.items():
            latest = max(sales)
            blocks[key][ft] = [
                int(statistics.median(p for _, p in sales)),
                len(sales),
                latest[0],
                latest[1],
            ]
    towns = {
        town: {ft: int(statistics.median(ps)) for ft, ps in types.items()}
        for town, types in per_town.items()
    }
    return {
        "from": min(months) if months else since,
        "to": max(months) if months else since,
        "blocks": blocks,
        "towns": towns,
        "block_town": {k: c.most_common(1)[0][0] for k, c in block_town.items()},
    }


def summarise_rent(rows: list[dict], since: str) -> dict:
    """Median monthly rent per town and flat type for approvals >= since."""
    per_town: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(list))
    months = []
    for r in rows:
        month = str(r.get("rent_approval_date", ""))
        if month < since:
            continue
        try:
            rent = int(float(r["monthly_rent"]))
        except (KeyError, TypeError, ValueError):
            continue
        per_town[str(r.get("town", "")).strip()][str(r.get("flat_type", "")).strip()].append(rent)
        months.append(month)
    towns = {
        town: {ft: int(statistics.median(v)) for ft, v in sorted(types.items()) if len(v) >= 3}
        for town, types in per_town.items()
    }
    period = f"{min(months)} – {max(months)}" if months else ""
    return {"period": period, "towns": {t: v for t, v in towns.items() if v}}


# HDB town codes in the property dataset (bldg_contract_town).
TOWN_CODES = {
    "AMK": "ANG MO KIO", "BB": "BUKIT BATOK", "BD": "BEDOK", "BH": "BISHAN", "BM": "BUKIT MERAH",
    "BP": "BUKIT PANJANG", "BT": "BUKIT TIMAH", "CCK": "CHOA CHU KANG", "CL": "CLEMENTI",
    "CT": "CENTRAL AREA", "GL": "GEYLANG", "HG": "HOUGANG", "JE": "JURONG EAST",
    "JW": "JURONG WEST", "KWN": "KALLANG/WHAMPOA", "MP": "MARINE PARADE", "PG": "PUNGGOL",
    "PRC": "PASIR RIS", "QT": "QUEENSTOWN", "SB": "SEMBAWANG", "SGN": "SERANGOON",
    "SK": "SENGKANG", "TAP": "TAMPINES", "TG": "TENGAH", "TP": "TOA PAYOH", "WL": "WOODLANDS",
    "YS": "YISHUN",
}  # fmt: skip


def residential_blocks(rows: list[dict], block_town: dict[str, str]) -> list[dict]:
    """HDB residential blocks without coordinates yet: {"b","s","t","y","f"}."""
    out = []
    for r in rows:
        if str(r.get("residential", "")).upper() != "Y":
            continue
        b, s = str(r.get("blk_no", "")).strip(), str(r.get("street", "")).strip()
        if not b or not s:
            continue
        code = str(r.get("bldg_contract_town", "")).strip()
        town = block_town.get(f"{b}|{s}") or TOWN_CODES.get(code, code)
        try:
            year = int(r.get("year_completed") or 0)
            floors = int(r.get("max_floor_lvl") or 0)
        except ValueError:
            year, floors = 0, 0
        out.append({"b": b, "s": s, "t": town, "y": year, "f": floors})
    return out


# ---------------------------------------------------------------- prayer times


def compact_prayer(rows: list[dict]) -> dict:
    """{"days": {"2026-10-20": ["05:35", "06:52", "12:58", "16:12", "19:01", "20:10"]}}.
    Older MUIS files write afternoon times on a 12-hour clock; normalise to 24-hour."""
    names = ("Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak")
    days = {}
    for r in rows:
        d = str(r.get("Date", ""))[:10]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", d):
            continue
        times = []
        for i, n in enumerate(names):
            m = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*", str(r.get(n, "")))
            if not m:
                break
            h, mi = int(m[1]), int(m[2])
            if i >= 2 and h < 11:  # Zohor onwards are afternoon/evening
                h += 12
            times.append(f"{h:02d}:{mi:02d}")
        if len(times) == 6:
            days[d] = times
    return {"days": days}


# ---------------------------------------------------------------- builders


async def build_hawkers(dg: DataGov) -> list[dict]:
    return compact_hawkers(await dg.rows(HAWKER_CLOSURES))


async def build_dengue(dg: DataGov) -> dict:
    return compact_dengue(await dg.geojson(DENGUE_CLUSTERS))


async def build_carparks(dg: DataGov) -> list[dict]:
    return compact_carparks(await dg.rows(CARPARK_INFO))


async def build_prayer(dg: DataGov) -> dict:
    return compact_prayer(await dg.rows(PRAYER_TIMES))


async def build_poi(dg: DataGov, geo: Geocoder) -> dict:
    out: dict[str, list] = {}

    async def safe(key: str, coro) -> None:
        try:
            out[key] = await coro
        except Exception as e:  # one broken layer should not drop the others
            log.warning("poi %s failed: %s", key, e)

    async def schools(level: str) -> list[dict]:
        rows = [
            r for r in await dg.rows(SCHOOLS) if str(r.get("mainlevel_code", "")).upper() == level
        ]
        items = []
        for r in rows:
            pc = str(r.get("postal_code", "")).strip().zfill(6)
            hit = await geo.find(pc)
            if hit:
                items.append({"n": str(r["school_name"]).title(), "la": hit[0], "lo": hit[1]})
        return items

    async def ccs() -> list[dict]:
        geo_cc = await dg.geojson(COMMUNITY_CLUBS)
        feats = [
            f
            for f in geo_cc.get("features", [])
            if "CC" in str((f.get("properties") or {}).get("DESCRIPTION", "CC")).upper()
        ]
        return compact_points({"features": feats})

    await safe("mrt", _wrap(compact_mrt, dg.geojson(MRT_EXITS)))
    await safe("primary", schools("PRIMARY"))
    await safe("school", schools("SECONDARY"))
    await safe("preschool", _wrap(compact_points, dg.geojson(PRESCHOOLS)))
    await safe("park", _wrap(compact_points, dg.geojson(PARKS)))
    await safe("library", _wrap(compact_points, dg.geojson(LIBRARIES)))
    await safe("cc", ccs())
    await safe("sport", _wrap(compact_sports, dg.rows(SPORT_FACILITIES)))
    return out


async def _wrap(fn, coro):
    return fn(await coro)


async def build_homes(dg: DataGov, geo: Geocoder, today: date) -> tuple[list[dict], dict, dict]:
    """(hdb_blocks, hdb_resale, hdb_rent). Resale uses the last 24 months, rent the last 6."""
    since = months_back(today, 24)
    resale_rows = await dg.rows(
        RESALE, sort="month desc", stop=lambda r: str(r.get("month", "")) < since
    )
    resale = summarise_resale(resale_rows, since)
    block_town = resale.pop("block_town")

    rent_since = months_back(today, 6)
    rent_rows = await dg.rows(
        RENTING_OUT,
        sort="rent_approval_date desc",
        stop=lambda r: str(r.get("rent_approval_date", "")) < rent_since,
    )
    rent = summarise_rent(rent_rows, rent_since)

    blocks = []
    for b in residential_blocks(await dg.rows(HDB_PROPERTY), block_town):
        hit = await geo.find(f"{b['b']} {b['s']}", block=b["b"])
        if hit:
            blocks.append({**b, "la": hit[0], "lo": hit[1]})
    return blocks, resale, rent
