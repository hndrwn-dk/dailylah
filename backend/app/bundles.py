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
from datetime import date, timedelta
from pathlib import Path
from typing import Any

import httpx

from .onemap import OneMap
from .svy21 import to_latlon

log = logging.getLogger(__name__)

DATASTORE_URL = "https://data.gov.sg/api/action/datastore_search"
POLL_DOWNLOAD_URL = "https://api-open.data.gov.sg/v1/public/api/datasets/{id}/poll-download"
COLLECTION_META_URL = "https://api-production.data.gov.sg/v2/public/api/collections/{id}/metadata"
DATASET_META_URL = "https://api-production.data.gov.sg/v2/public/api/datasets/{id}/metadata"
ONEMAP_SEARCH_URL = "https://www.onemap.gov.sg/api/common/elastic/search"

# data.gov.sg dataset ids (verified against the live catalogue, Oct 2026).
HAWKER_CLOSURES = "d_bda4baa634dd1cc7a6c7cad5f19e2d68"
DENGUE_CLUSTERS = "d_dbfabf16158d1b0e1c420627c0819168"
MRT_EXITS = "d_b39d3a0871985372d7e1637193335da5"
STATION_CODES = "d_d312a5b127e1ae74299b8ae664cedd4e"  # LTA codes (no TEL in the 2024 file)
PRESCHOOLS = "d_61eefab99958fd70e6aab17320a71f1c"
SCHOOLS = "d_688b934f82c1059ed0a6993d2a829089"
COMMUNITY_CLUBS = "d_9de02d3fb33d96da1855f4fbef549a0f"
PARKS = "d_0542d48f0991541706b58059381a6eca"
PARK_FACILITIES = "d_14d807e20158338fd578c2913953516e"  # NParks points: NAME, CLASS (weekly)
LIBRARIES = "d_27b8dae65d9ca1539e14d09578b17cbf"
SPORT_FACILITIES = "d_2cfb0867cdeb2b7303068995699dc33b"
PUBLIC_HOLIDAYS = "d_8ef23381f9417e4d4254ee8b4dcdb176"  # MOM, consolidated 2020 onwards
SUPERMARKETS = "d_11edd0117280c5776651d7891114c88c"  # NEA list of supermarket licences
CARPARK_INFO = "d_23f946fa557947f93a8043bbef41dd09"
HDB_PROPERTY = "d_17f5382f26140b1fdae0ba2ef6239d2f"
RESALE = "d_8b84c4ee58e3cfc0ece0d773c8ca6abc"
RENTING_OUT = "d_c9f57187485a850908655db0e8cfe651"
PRAYER_TIMES = "d_d441e7242e78efc566024dd5b0d9829c"  # 2026 timetable, fallback
PRAYER_COLLECTION = "2312"  # MUIS: one dataset per year, named "... Timetable <year>"
BICYCLE_RACKS = "d_937424cca6d1617288a82a7aeb89f76d"  # LTA racks near MRT stations
AEDS = "d_4e6b82c58a8a832f6f1fee5dfa6d47ea"  # SCDF public access AEDs
FIRE_STATIONS = "d_5d3d2c4f3556edb5d8c995f42e603b24"
CHAS_CLINICS = "d_548c33ea2d99e29ec63a7cc9edcccedc"
CD_SHELTERS = "d_291795a678b8cf82f108780a6235ce18"  # no coordinates: geocoded by postal code
HDB_BUILDINGS = "d_16b157c52ed637edd6ba1232e026258d"  # footprints with BLK_NO, ST_COD, POSTAL_COD

PAGE = 10000


def _r(x: float) -> float:
    return round(float(x), 5)


def in_sg(la: object, lo: object) -> bool:
    """Inside Singapore's bounding box; catches bad source coordinates."""
    try:
        return 1.15 <= float(la) <= 1.48 and 103.59 <= float(lo) <= 104.1  # type: ignore
    except (TypeError, ValueError):
        return False


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
        self,
        resource_id: str,
        sort: str | None = None,
        stop=None,
        max_rows: int = 400_000,
        page: int = PAGE,
    ) -> list[dict]:
        """All rows of a datastore table, page by page. `stop(row)` ends paging early
        (used with a descending sort to fetch only recent rows)."""
        out: list[dict] = []
        offset = 0
        while offset < max_rows:
            params: dict[str, Any] = {"resource_id": resource_id, "limit": page, "offset": offset}
            if sort:
                params["sort"] = sort
            result = (await self._get(DATASTORE_URL, params)).json().get("result", {})
            records = result.get("records") or []
            for row in records:
                if stop and stop(row):
                    return out
                out.append(row)
            if len(records) < page:
                break
            offset += page
        return out

    async def collection_datasets(self, collection_id: str) -> dict[str, str]:
        """{dataset id: dataset name} for every dataset in a data.gov.sg collection."""
        meta = (await self._get(COLLECTION_META_URL.format(id=collection_id))).json()
        ids = ((meta.get("data") or {}).get("collectionMetadata") or {}).get("childDatasets") or []
        out = {}
        for i in ids:
            d = (await self._get(DATASET_META_URL.format(id=i))).json().get("data") or {}
            out[str(i)] = str(d.get("name", ""))
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

    def __init__(
        self,
        client: httpx.AsyncClient,
        cache_path: Path | None,
        budget_s: float = 2400,
        onemap: OneMap | None = None,
    ):
        self.client = client
        self.onemap = onemap
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
            for attempt in range(4):
                if self.onemap is not None:
                    resp = await self.onemap.get(ONEMAP_SEARCH_URL, params)
                else:
                    resp = await self.client.get(ONEMAP_SEARCH_URL, params=params)
                if resp.status_code != 429:
                    break
                await asyncio.sleep(20 * (attempt + 1))
            if resp.status_code != 200:
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
        title = name.title().replace("Mrt", "MRT").replace("Lrt", "LRT")
        out.append({"n": title, "la": _r(lat), "lo": _r(lng)})
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


def compact_holidays(rows: list[dict], today: date) -> list[dict]:
    """MOM public holidays from a month ago onwards: [{"d": "2026-12-25", "n": "Christmas Day"}]."""
    since = (today - timedelta(days=31)).isoformat()
    out = []
    for r in rows:
        low = {str(k).lower(): v for k, v in r.items()}
        d = str(low.get("date", "")).strip()[:10]
        name = str(low.get("holiday", "")).strip()
        if len(d) == 10 and name and d >= since:
            out.append({"d": d, "n": name})
    return sorted(out, key=lambda x: x["d"])


async def build_holidays(dg: DataGov, today: date) -> list[dict]:
    return compact_holidays(await dg.rows(PUBLIC_HOLIDAYS), today)


def pick_prayer_datasets(names: dict[str, str], years: list[int]) -> list[str]:
    """Dataset ids of the yearly MUIS timetables for [years], skipping the consolidated one."""
    out = []
    for y in years:
        for i, n in names.items():
            if str(y) in n and "consolidated" not in n.lower() and i not in out:
                out.append(i)
                break
    return out


async def build_prayer(dg: DataGov, today: date) -> dict:
    """This year's and next year's timetables, so the app keeps working on 1 January.
    MUIS publishes next year's file late in the year; until then only this year is in."""
    try:
        ids = pick_prayer_datasets(
            await dg.collection_datasets(PRAYER_COLLECTION), [today.year, today.year + 1]
        )
    except Exception as e:  # discovery is best effort; the known id still works
        log.warning("prayer collection lookup failed: %s", e)
        ids = []
    if not ids:
        ids = [PRAYER_TIMES]
    days: dict[str, list[str]] = {}
    for i in ids:
        days.update(compact_prayer(await dg.rows(i))["days"])
    since = f"{today.year}-01-01"
    return {"days": {d: t for d, t in sorted(days.items()) if d >= since}}


def school_level(code: object) -> str | None:
    """MOE "mainlevel_code" to our two lists. Values look like "PRIMARY",
    "SECONDARY (S1-S5)", "MIXED LEVEL (P1-S4)", "JUNIOR COLLEGE"."""
    c = str(code or "").strip().upper()
    if c.startswith("PRIMARY") or c.startswith("MIXED LEVEL (P1"):
        return "PRIMARY"
    if c.startswith(("SECONDARY", "MIXED LEVEL", "JUNIOR COLLEGE", "CENTRALISED INSTITUTE")):
        return "SECONDARY"
    return None


async def build_poi(dg: DataGov, geo: Geocoder) -> dict:
    out: dict[str, list] = {}

    async def safe(key: str, coro) -> None:
        try:
            out[key] = await coro
        except Exception as e:  # one broken layer should not drop the others
            log.warning("poi %s failed: %s", key, e)

    async def schools(level: str) -> list[dict]:
        rows = [r for r in await dg.rows(SCHOOLS) if school_level(r.get("mainlevel_code")) == level]
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

    async def parks() -> list[dict]:
        items = compact_points(await dg.geojson(PARKS))
        try:
            return attach_facilities(items, await dg.geojson(PARK_FACILITIES))
        except Exception as e:  # parks without facility chips are still useful
            log.warning("park facilities failed: %s", e)
            return items

    await safe("mrt", _wrap(compact_mrt, dg.geojson(MRT_EXITS)))
    await safe("primary", schools("PRIMARY"))
    await safe("school", schools("SECONDARY"))
    await safe("preschool", _wrap(compact_points, dg.geojson(PRESCHOOLS)))
    await safe("park", parks())
    await safe("library", _wrap(compact_points, dg.geojson(LIBRARIES)))
    await safe("cc", ccs())
    await safe("sport", _wrap(compact_sports, dg.rows(SPORT_FACILITIES)))
    await safe("supermarket", supermarkets(dg, geo))
    return out


# Facility classes worth a chip, in the order shown. Others in the layer (lamp posts,
# benches, signs) are left out.
FACILITY_LABELS = {
    "PLAYGROUND": "Playground",
    "FITNESS AREA": "Fitness corner",
    "FITNESS CORNER": "Fitness corner",
    "TOILET": "Toilet",
    "CARPARK": "Car park",
    "CAR PARK": "Car park",
    "SHELTER": "Shelter",
    "BBQ PIT": "BBQ pit",
    "DOG RUN": "Dog run",
    "CYCLING PATH": "Cycling",
    "BICYCLE RACK": "Bike rack",
    "WATER POINT": "Water",
    "DRINKING FOUNTAIN": "Water",
    "EXERCISE STATION": "Fitness corner",
    "CAFE": "Food",
    "F&B": "Food",
    "RESTAURANT": "Food",
    "POND": "Pond",
    "LOOKOUT POINT": "Lookout",
    "CAMPSITE": "Camping",
    # Broader words last: substring matches try the keys in this order.
    "PAVILION": "Shelter",
    "WASHROOM": "Toilet",
    "RESTROOM": "Toilet",
    "PLAY AREA": "Playground",
    "FITNESS": "Fitness corner",
}


def _facility_label(cls: str) -> str | None:
    c = cls.strip().upper()
    if c in FACILITY_LABELS:
        return FACILITY_LABELS[c]
    for k, v in FACILITY_LABELS.items():
        if k in c:
            return v
    return None


def attach_facilities(parks: list[dict], geo: dict, radius: float = 250.0) -> list[dict]:
    """Add "f": facility labels to each park, from NParks facility points that share the
    park's name or lie within [radius] metres of its centre. Points are bucketed on a
    ~500 m grid so 15k facilities x 500 parks stays quick."""
    cell = 0.0045
    grid: dict[tuple[int, int], list[tuple[float, float, str]]] = defaultdict(list)
    by_name: dict[str, set[str]] = defaultdict(set)
    unknown: Counter[str] = Counter()
    for f in geo.get("features", []):
        props = f.get("properties") or {}
        desc = str(props.get("Description", ""))
        cls = str(props.get("CLASS") or props.get("Class") or html_field(desc, "CLASS") or "")
        label = _facility_label(cls) if cls else None
        if cls and not label:
            unknown[cls.strip().upper()] += 1
        c = centroid(f.get("geometry"))
        if not label or not c:
            continue
        grid[(int(c[0] / cell), int(c[1] / cell))].append((c[0], c[1], label))
        name = _props_name(props).strip().lower()
        if name:
            by_name[name].add(label)
    if unknown:  # shown in the data workflow log, to tune FACILITY_LABELS
        log.info("park facility classes without a label: %s", unknown.most_common(25))
    order = list(dict.fromkeys(FACILITY_LABELS.values()))
    out = []
    for p in parks:
        found = set(by_name.get(str(p["n"]).strip().lower(), ()))
        gx, gy = int(p["la"] / cell), int(p["lo"] / cell)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for la, lo, label in grid.get((gx + dx, gy + dy), ()):
                    if label not in found and _haversine(p["la"], p["lo"], la, lo) <= radius:
                        found.add(label)
        item = dict(p)
        if found:
            item["f"] = sorted(found, key=order.index)
        out.append(item)
    return out


def _pick(row: dict, *needles: str) -> str:
    """First non-empty value whose column name contains one of [needles] (case-insensitive)."""
    for k, v in row.items():
        if any(n in str(k).lower() for n in needles) and str(v or "").strip():
            return str(v).strip()
    return ""


async def supermarkets(dg: DataGov, geo: Geocoder) -> list[dict]:
    """NEA supermarket licences, geocoded by postal code (cached). Column names are matched
    loosely because the CSV headers are not documented."""
    items = []
    seen: set[tuple[str, str]] = set()
    for r in await dg.rows(SUPERMARKETS):
        name = _pick(r, "business_name", "licensee_name", "name")
        pc = "".join(ch for ch in _pick(r, "postal") if ch.isdigit()).zfill(6)
        if not name or pc == "000000" or (name, pc) in seen:
            continue
        seen.add((name, pc))
        hit = await geo.find(pc)
        if hit:
            addr = _pick(r, "premise_address", "address").title()
            items.append({"n": name.title(), "d": addr, "la": hit[0], "lo": hit[1]})
    return items


async def _wrap(fn, coro):
    return fn(await coro)


def compact_buildings(geo: dict) -> list[dict]:
    """HDB building footprints -> [{"b": block, "st": street code, "p": postal, "la", "lo"}]."""
    out = []
    for f in geo.get("features", []):
        props = f.get("properties") or {}
        c = centroid(f.get("geometry"))
        b = str(props.get("BLK_NO") or "").strip().upper()
        if not c or not b:
            continue
        out.append(
            {
                "b": b,
                "st": str(props.get("ST_COD") or "").strip().upper(),
                "p": str(props.get("POSTAL_COD") or "").strip(),
                "la": _r(c[0]),
                "lo": _r(c[1]),
            }
        )
    return out


def _street_prefix(street: str) -> str:
    return re.sub(r"[^A-Z]", "", street.upper())[:3]


def match_blocks(
    blocks: list[dict],
    buildings: list[dict],
    street_points: dict[str, tuple[float, float]] | None = None,
) -> list[dict]:
    """Give each HDB block (from Property Information) coordinates and a postal code.

    The footprint layer has block numbers and street *codes* but no street names, so
    each street name is matched to the street code whose block numbers overlap most,
    preferring codes that start like the street name (BEDOK NTH ST 2 -> "BED...") and
    lie near the street's geocoded point when one is known."""
    street_points = street_points or {}
    by_code: dict[str, dict[str, dict]] = defaultdict(dict)
    for bl in buildings:
        by_code[bl["st"]].setdefault(bl["b"], bl)
    code_centre = {
        code: (
            sum(x["la"] for x in bs.values()) / len(bs),
            sum(x["lo"] for x in bs.values()) / len(bs),
        )
        for code, bs in by_code.items()
    }
    by_street: dict[str, list[dict]] = defaultdict(list)
    for b in blocks:
        by_street[b["s"]].append(b)

    out = []
    for street, items in by_street.items():
        nums = {b["b"].upper() for b in items}
        point = street_points.get(street)
        best, best_score = None, 0.0
        for code, bs in by_code.items():
            overlap = len(nums & bs.keys()) / len(nums)
            if overlap == 0:
                continue
            score = overlap
            if code.startswith(_street_prefix(street)):
                score += 0.6
            if point:
                d = _haversine(point[0], point[1], *code_centre[code])
                if d > 3000:
                    continue
                score += 0.4 * (1 - d / 3000)
            if score > best_score:
                best, best_score = code, score
        if best is None or best_score < 0.5:
            continue
        for b in items:
            bl = by_code[best].get(b["b"].upper())
            if bl:
                out.append({**b, "p": bl["p"], "la": bl["la"], "lo": bl["lo"]})
    return out


async def build_resale(dg: DataGov, today: date) -> dict:
    """Resale medians for the last 24 months (keeps "block_town" for build_blocks)."""
    since = months_back(today, 24)
    rows = await dg.rows(RESALE, sort="month desc", stop=lambda r: str(r.get("month", "")) < since)
    return summarise_resale(rows, since)


async def build_rent(dg: DataGov, today: date) -> dict:
    since = months_back(today, 6)
    rows = await dg.rows(
        RENTING_OUT,
        sort="rent_approval_date desc",
        stop=lambda r: str(r.get("rent_approval_date", "")) < since,
    )
    return summarise_rent(rows, since)


async def build_blocks(dg: DataGov, geo: Geocoder, block_town: dict[str, str]) -> list[dict]:
    # Wide rows: smaller pages, or the API answers 413 Payload Too Large.
    blocks = residential_blocks(await dg.rows(HDB_PROPERTY, page=2000), block_town)
    buildings = compact_buildings(await dg.geojson(HDB_BUILDINGS))
    # One OneMap lookup per street (~600, cached) helps tell apart streets with the
    # same block numbers.
    points = {}
    for street in sorted({b["s"] for b in blocks}):
        hit = await geo.find(street)
        if hit:
            points[street] = hit
    return match_blocks(blocks, buildings, points)


# ---------------------------------------------------------------- emergency points

# Public hospitals with a 24-hour Emergency Department (A&E). Located through OneMap.
AE_HOSPITALS = [
    "Singapore General Hospital",
    "National University Hospital",
    "Tan Tock Seng Hospital",
    "Changi General Hospital",
    "Khoo Teck Puat Hospital",
    "Ng Teng Fong General Hospital",
    "Sengkang General Hospital",
    "KK Women's and Children's Hospital",
]


def _clean(v: Any) -> str:
    s = str(v or "").strip()
    return "" if s.lower() in ("null", "none", "nil", "na") else s


def compact_aeds(geo: dict) -> list[dict]:
    out = []
    for f in geo.get("features", []):
        p = f.get("properties") or {}
        c = centroid(f.get("geometry"))
        lat, lng = (
            (p.get("LATITUDE"), p.get("LONGITUDE"))
            if p.get("LATITUDE")
            else (c[0], c[1])
            if c
            else (None, None)
        )
        if lat is None or lng is None:
            continue
        name = _clean(p.get("BUILDING_NAME")) or " ".join(
            x for x in (_clean(p.get("HOUSE_NUMBER")), _clean(p.get("ROAD_NAME"))) if x
        )
        floor = _clean(p.get("AED_LOCATION_FLOOR_LEVEL"))
        desc = _clean(p.get("AED_LOCATION_DESCRIPTION"))
        item = {"n": name, "la": _r(lat), "lo": _r(lng)}
        detail = " · ".join(
            x for x in (f"Level {floor}" if floor and floor not in desc else "", desc) if x
        )
        if detail:
            item["d"] = detail[:140]
        hours = _clean(p.get("OPERATING_HOURS")).rstrip(";")
        if hours:
            item["h"] = hours[:80]
        out.append(item)
    return out


def compact_fire_stations(geo: dict) -> list[dict]:
    out = []
    for f in geo.get("features", []):
        p = f.get("properties") or {}
        c = centroid(f.get("geometry"))
        if not c:
            continue
        tel = re.search(r"Tel:?\s*([\d ]{8,9})", str(p.get("DESCRIPTION", "")))
        item = {
            "n": _clean(p.get("NAME")),
            "a": _clean(p.get("ADDRESS")),
            "la": _r(c[0]),
            "lo": _r(c[1]),
        }
        if tel:
            item["t"] = tel[1].replace(" ", "")
        out.append(item)
    return out


def compact_clinics(geo: dict) -> list[dict]:
    out = []
    for f in geo.get("features", []):
        desc = str((f.get("properties") or {}).get("Description", ""))
        c = centroid(f.get("geometry"))
        name = html_field(desc, "HCI_NAME")
        if not c or not name:
            continue
        addr = " ".join(
            x
            for x in (
                html_field(desc, "BLK_HSE_NO"),
                html_field(desc, "STREET_NAME").title(),
                html_field(desc, "BUILDING_NAME").title(),
            )
            if _clean(x)
        )
        item = {"n": name, "a": addr, "la": _r(c[0]), "lo": _r(c[1])}
        tel = re.sub(r"\D", "", html_field(desc, "HCI_TEL"))
        if len(tel) == 8:
            item["t"] = tel
        out.append(item)
    return out


async def build_emergency(dg: DataGov, geo: Geocoder) -> dict:
    out: dict[str, list] = {}

    async def safe(key: str, coro) -> None:
        try:
            items = await coro
        except Exception as e:
            log.warning("emergency %s failed: %s", key, e)
            return
        good = [x for x in items if in_sg(x.get("la"), x.get("lo"))]
        if len(good) < len(items):
            log.info(
                "emergency %s: dropped %d points outside Singapore", key, len(items) - len(good)
            )
        out[key] = good

    await safe("aed", _wrap(compact_aeds, dg.geojson(AEDS)))
    await safe("fire", _wrap(compact_fire_stations, dg.geojson(FIRE_STATIONS)))
    await safe("clinic", _wrap(compact_clinics, dg.geojson(CHAS_CLINICS)))

    async def shelters() -> list[dict]:
        items = []
        for r in await dg.rows(CD_SHELTERS):
            pc = _clean(r.get("POSTALCODE")).zfill(6)
            hit = await geo.find(pc) if pc.strip("0") else None
            if hit:
                items.append(
                    {
                        "n": _clean(r.get("NAME")),
                        "a": _clean(r.get("ADDRESS")),
                        "la": hit[0],
                        "lo": hit[1],
                    }
                )
        return items

    async def hospitals() -> list[dict]:
        items = []
        for name in AE_HOSPITALS:
            hit = await geo.find(name)
            if hit:
                items.append({"n": name, "la": hit[0], "lo": hit[1]})
        return items

    await safe("shelter", shelters())
    await safe("ae", hospitals())
    return out


def compact_racks(geo: dict) -> list[dict]:
    """LTA bicycle racks: {"n": "12 racks · sheltered", "la", "lo"}."""
    out = []
    for f in geo.get("features", []):
        desc = str((f.get("properties") or {}).get("Description", ""))
        c = centroid(f.get("geometry"))
        if not c:
            continue
        count = html_field(desc, "RACK_CNT")
        sheltered = html_field(desc, "SHLTR_IND").lower() == "yes"
        label = f"{count} bicycle racks" if count else "Bicycle racks"
        out.append(
            {"n": label + (" · sheltered" if sheltered else ""), "la": _r(c[0]), "lo": _r(c[1])}
        )
    return out


async def build_racks(dg: DataGov) -> list[dict]:
    return compact_racks(await dg.geojson(BICYCLE_RACKS))


# ---------------------------------------------------------------- MRT stations with codes

# Lines opened after LTA's station-code file was last refreshed.
EXTRA_STATION_CODES = {
    "WOODLANDS NORTH": ["TE1"], "WOODLANDS": ["TE2"], "WOODLANDS SOUTH": ["TE3"],
    "SPRINGLEAF": ["TE4"], "LENTOR": ["TE5"], "MAYFLOWER": ["TE6"], "BRIGHT HILL": ["TE7"],
    "UPPER THOMSON": ["TE8"], "CALDECOTT": ["TE9"], "STEVENS": ["TE11"], "NAPIER": ["TE12"],
    "ORCHARD BOULEVARD": ["TE13"], "ORCHARD": ["TE14"], "GREAT WORLD": ["TE15"],
    "HAVELOCK": ["TE16"], "OUTRAM PARK": ["TE17"], "MAXWELL": ["TE18"], "SHENTON WAY": ["TE19"],
    "MARINA BAY": ["TE20"], "GARDENS BY THE BAY": ["TE22"], "TANJONG RHU": ["TE23"],
    "KATONG PARK": ["TE24"], "TANJONG KATONG": ["TE25"], "MARINE PARADE": ["TE26"],
    "MARINE TERRACE": ["TE27"], "SIGLAP": ["TE28"], "BAYSHORE": ["TE29"],
    "HUME": ["DT4"], "PUNGGOL COAST": ["NE18"],
}  # fmt: skip


def _base_station(name: str) -> str:
    return re.sub(r"\s+(MRT|LRT)\s+STATION$", "", name.strip().upper())


def compact_mrt_stations(exits: dict, code_rows: list[dict]) -> list[dict]:
    """[{"n": "Marine Parade", "c": ["TE26"], "la", "lo"}] — one point per station (exit
    average), with line codes from LTA plus EXTRA_STATION_CODES."""
    codes: dict[str, set[str]] = defaultdict(set)
    for r in code_rows:
        name = str(r.get("mrt_station_english", "")).strip().upper()
        code = str(r.get("stn_code", "")).strip().upper()
        if name and code:
            codes[name].add(code)
    for name, extra in EXTRA_STATION_CODES.items():
        codes[name].update(extra)
    pts: dict[str, list[tuple[float, float]]] = defaultdict(list)
    for f in exits.get("features", []):
        name = str((f.get("properties") or {}).get("STATION_NA", ""))
        c = centroid(f.get("geometry"))
        if name and c:
            pts[_base_station(name)].append((c[0], c[1]))
    out = []
    for name, p in sorted(pts.items()):
        if not codes.get(name):
            continue
        out.append(
            {
                "n": name.title(),
                "c": sorted(codes[name]),
                "la": _r(sum(x[0] for x in p) / len(p)),
                "lo": _r(sum(x[1] for x in p) / len(p)),
            }
        )
    return out


async def build_mrt_stations(dg: DataGov) -> list[dict]:
    return compact_mrt_stations(await dg.geojson(MRT_EXITS), await dg.rows(STATION_CODES))


# ---------------------------------------------------------------- around home (OneMap themes)

# Works and upgrading near a home. Each theme names its fields differently.
PROJECT_THEMES = {
    "lup": "hdbluppropunderconstruction",
    "nrp": "hdbnrpunderconstruction",
    "eup": "bca_estate_upg_prog_osp",
    "hdb": "hdbbuildingunderconstruction",
    "hdbroad": "hdbroadsunderconstruction",
    "cycling": "hdbcyclingunderconstruction",
    "road": "lta_rdproj_unclass",
    "rail": "ltarailprj_uc_unclass",
    "drain": "drainageconstruction",
    "sewer": "sewerageconstruction",
    "water": "watersupplyconstruction",
    "abc": "abcwatersconstruction",
    "park": "nparks_uc_parks",
    "pc": "nparks_uc_pc",
    "parkfac": "underconstruction_facilities",
    "ura": "ura_project_public_pl",
}
_P_NAME = ("PROJNAME", "PROJECTTITLE", "INFRA_NAME", "STATIONNAM", "NAME")
_P_STATUS = ("STATUS", "DEVSTATUS", "DEVELOPMENT_STATUS", "DEVELOPMENTSTATUS", "DEV_STATUS")
_P_START = (
    "CNSTRN_CMCMNT",
    "ESTMT_CNSTRN_CMCMNT",
    "ESTSTARTDT",
    "EXPECTED_START_DATE",
    "STARTQUARTER",
    "EST_START_CONSTRUCTION",
    "ST_CON_DT",
)
_P_END = (
    "ESTMT_CNSTRN_CMPLTN",
    "ESTENDDT",
    "EXPECTED_COMPLETION_DATE",
    "ENDQUARTER",
    "EST_END_CONSTRUCTION",
    "END_CON_DT",
)
_P_BY = ("IMPLMT_ORG", "AGENCY", "IMPLEMENTOR", "OWNER", "IMPL_PARTY")
_P_CONTACT = ("HOTLINE", "QSM_CONTACT", "QSMCONTACT", "AGENCY_QSM_CONTACT", "CTRCTR_CNTCT")

# Places from OneMap themes: key -> (theme, detail field, phone field, hours field)
POINT_LABELS = {"bbq": "BBQ pit"}
POINT_THEMES = {
    "police": ("spf_establishments", "DESCRIPTION", "TELEPHONE", "OPERATING_HOURS"),
    "pharmacy": ("registered_pharmacy", None, None, None),
    "eldercare": ("eldercare", None, None, None),
    "studentcare": ("studentcare", "MONTHLY_FEE", "SCC_TELEPHONE", None),
    "family": ("family", "DESCRIPTION", "TELEPHONE", None),
    "rc": ("residentscommittee", None, None, None),
    "mp": ("constituencyoffices", None, None, None),
    "hdbbranch": ("hdb_branches", None, None, None),
    "ewaste": ("ewaste", "DESCRIPTION", None, None),
    "reuse": ("reusechannels", "ACCEPTEDITEMS", None, None),
    "attraction": ("tourism", "META_DESCRIPTION", None, "OPENING_HOURS"),
    "museum": ("museum", "DESCRIPTION", None, None),
    "bbq": ("nparks_bbq_pit", None, None, None),
    "activesg": ("sportsg_sport_facilities", "DESCRIPTION", None, None),
    "pcn": ("pcn_access_points", None, None, None),
}


def _first(props: dict, keys: tuple[str, ...]) -> str:
    for k in keys:
        v = props.get(k)
        if v not in (None, "", "null", "undefined", "NA", "-"):
            return str(v).strip()
    return ""


def project_date(value: str) -> str:
    """'20240626' -> '2024-06'; '3Q 2026' / '2Q2026' -> '3Q 2026'; placeholders -> ''."""
    v = (value or "").strip()
    if not v or "2999" in v:
        return ""
    m = re.fullmatch(r"(\d{4})(\d{2})(\d{2})", v)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    m = re.fullmatch(r"([1-4])Q\s*(\d{4})", v, re.I)
    if m:
        return f"{m.group(1)}Q {m.group(2)}"
    m = re.match(r"(\d{4})-(\d{2})", v)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", v)
    if m:
        return f"{m.group(3)}-{int(m.group(2)):02d}"
    return v[:20]


def _year(value: str) -> int | None:
    m = re.search(r"(20\d{2})", value or "")
    return int(m.group(1)) if m else None


def _theme_coords(item: dict) -> list[tuple[float, float]]:
    """(lat, lng) points from a OneMap theme row ('lat,lng' or '[[lng, lat], ...]')."""
    raw = item.get("LatLng")
    if raw is None:
        return []
    if isinstance(raw, str):
        raw = raw.strip()
        if raw.startswith("["):
            try:
                raw = json.loads(raw)
            except ValueError:
                return []
        else:
            parts = raw.split(",")
            try:
                return [(float(parts[0]), float(parts[1]))]
            except (IndexError, ValueError):
                return []
    pts: list[tuple[float, float]] = []

    def walk(x) -> None:
        if isinstance(x, list) and len(x) == 2 and all(isinstance(v, (int, float)) for v in x):
            lng, lat = float(x[0]), float(x[1])
            if lat > lng:  # some layers give [lat, lng]
                lat, lng = lng, lat
            pts.append((lat, lng))
        elif isinstance(x, list):
            for y in x:
                walk(y)

    walk(raw)
    return pts


def _spot(pts: list[tuple[float, float]]) -> tuple[float, float, float] | None:
    if not pts:
        return None
    lat = sum(p[0] for p in pts) / len(pts)
    lng = sum(p[1] for p in pts) / len(pts)
    return lat, lng, max(_haversine(lat, lng, p[0], p[1]) for p in pts)


def _ended(end: str, today: date) -> bool:
    """True when the estimated end ('3Q 2026', '2026-03') is before this quarter/month."""
    m = re.fullmatch(r"([1-4])Q (\d{4})", end)
    if m:
        return (int(m.group(2)), int(m.group(1)) * 3) < (today.year, today.month)
    m = re.fullmatch(r"(\d{4})-(\d{2})", end)
    if m:
        return (int(m.group(1)), int(m.group(2))) < (today.year, today.month)
    y = _year(end)
    return y is not None and y < today.year


def _sample(pts: list[tuple[float, float]], n: int = 40) -> list[list[float]]:
    step = max(1, len(pts) // n)
    return [[_r(la), _r(lo)] for la, lo in pts[::step]]


def compact_projects(kind: str, rows: list[dict], today: date) -> list[dict]:
    """Theme rows -> [{"k","n","s","from","to","by","t","la","lo","r","p"}]. Rows of the same
    project are merged; finished work is dropped. "p" holds sample points of the site so the
    app can measure the distance to its nearest edge (big road projects span whole towns)."""
    merged: dict[str, dict] = {}
    for row in rows:
        pts = _theme_coords(row)
        name = _first(row, _P_NAME)
        if not pts or not name or re.fullmatch(r"[A-Z0-9]+(_[A-Z0-9]+)+", name):
            continue
        status = _first(row, _P_STATUS)
        end = project_date(_first(row, _P_END))
        if "complet" in status.lower() or _ended(end, today):
            continue
        item = merged.setdefault(
            name,
            {
                "k": kind,
                "n": name.title() if name.isupper() else name,
                "s": {"U/C": "Under construction"}.get(status, status),
                "from": project_date(_first(row, _P_START)),
                "to": end,
                "by": _first(row, _P_BY),
                "t": _first(row, _P_CONTACT),
                "_pts": [],
            },
        )
        item["_pts"] += pts
    out = []
    for item in merged.values():
        pts = item.pop("_pts")
        spot = _spot(pts)
        if not spot:
            continue
        item |= {"la": _r(spot[0]), "lo": _r(spot[1]), "r": round(spot[2]), "p": _sample(pts)}
        out.append({k: v for k, v in item.items() if v not in ("", None)})
    return out


def _fix_text(v: str) -> str:
    """Undo UTF-8 read as Latin-1 ('youâ€™ll' -> 'you'll') and strip HTML."""
    if "â€" in v or "Ã" in v:
        try:
            v = v.encode("cp1252").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(v))).strip()


def compact_theme_points(
    rows: list[dict],
    detail: str | None,
    tel: str | None,
    hours: str | None,
    label: str = "",
) -> list[dict]:
    out = []
    for row in rows:
        pts = _theme_coords(row)
        name = _fix_text(str(row.get("NAME") or ""))
        if re.fullmatch(r"[A-Za-z0-9]+(_[A-Za-z0-9]+)+", name):
            name = label  # placeholder names such as "NPARKS_BBQ_PIT"
        if not pts or not name:
            continue
        lat, lng = pts[0]
        addr = " ".join(
            str(row.get(k) or "").strip()
            for k in ("ADDRESSBLOCKHOUSENUMBER", "ADDRESSSTREETNAME", "ADDRESSPOSTALCODE")
            if str(row.get(k) or "").strip() not in ("", "null", "0")
        )
        item = {"n": name.title() if name.isupper() else name, "la": _r(lat), "lo": _r(lng)}
        if addr:
            item["a"] = addr.title()
        for key, field in (("d", detail), ("t", tel), ("h", hours)):
            v = str(row.get(field) or "").strip() if field else ""
            if v and v.lower() not in ("null", "na", "-"):
                item[key] = _fix_text(v)[:200]
        out.append(item)
    return out


async def theme_rows(om: OneMap, query_name: str) -> list[dict]:
    body = await om.theme(query_name)
    res = body.get("SrchResults") or []
    return [r for r in res[1:] if isinstance(r, dict) and "ErrorMessage" not in r]


async def build_around(om: OneMap, today: date) -> dict:
    """Upgrading, works and services near homes, from OneMap themes (needs a token)."""
    if not om.configured:
        raise RuntimeError("ONEMAP_EMAIL / ONEMAP_PASSWORD not set")
    projects: list[dict] = []
    points: dict[str, list] = {}
    for kind, theme in PROJECT_THEMES.items():
        try:
            projects += compact_projects(kind, await theme_rows(om, theme), today)
        except Exception as e:  # one broken layer should not drop the others
            log.warning("around %s failed: %s", kind, e)
        await asyncio.sleep(0.3)
    for key, (theme, detail, tel, hours) in POINT_THEMES.items():
        try:
            points[key] = compact_theme_points(
                await theme_rows(om, theme), detail, tel, hours, POINT_LABELS.get(key, "")
            )
        except Exception as e:
            log.warning("around %s failed: %s", key, e)
        await asyncio.sleep(0.3)
    return {"projects": projects, "points": points}


# ---------------------------------------------------------------- halal places (Muslim.sg)

HALAL_URL = "https://muslim.sg/halal-cafe-restaurant-food/search"
HALAL_HEADERS = {"User-Agent": "DailyLah/0.2 (+https://www.tursinalabs.com/dailylah)"}


def _js_string(v: str) -> str:
    """Decode a JS string literal body ('\\u002F' -> '/')."""
    try:
        return json.loads(f'"{v}"')
    except ValueError:
        return v


def parse_halal_page(text: str) -> list[dict]:
    """Listings on one Muslim.sg search page: names and addresses from the cards, coordinates
    from the page state, matched by address (cards without coordinates are skipped).
    [{"n", "a", "la", "lo"}]."""
    coords: dict[str, tuple[float, float]] = {}
    i = text.find("halal_places:")
    if i >= 0:
        for la, lo, addr in re.findall(
            r'lat:(-?[\d.]+),\s*lon:(-?[\d.]+),\s*address:"((?:[^"\\]|\\.)*)"', text[i:]
        ):
            coords[_norm_addr(_js_string(addr))] = (float(la), float(lo))
    out = []
    for card in text.split('class="card-box"')[1:]:
        name = re.search(r'<div class="card-name"[^>]*>(.*?)</div>', card, re.S)
        addr = re.search(r'<div class="address-box"[^>]*>(.*?)</div>', card, re.S)
        if not name or not addr:
            continue
        n = html.unescape(re.sub(r"\s+", " ", name.group(1))).strip()
        a = html.unescape(re.sub(r"\s+", " ", addr.group(1))).strip()
        ll = coords.get(_norm_addr(a))
        if not n or not ll or not (1.1 < ll[0] < 1.5 and 103.5 < ll[1] < 104.1):
            continue
        out.append(
            {
                "n": n.title() if n.isupper() else n,
                "a": a.title() if a.isupper() else a,
                "la": _r(ll[0]),
                "lo": _r(ll[1]),
            }
        )
    return out


def _norm_addr(a: str) -> str:
    return re.sub(r"\s+", " ", a).strip().upper()


def halal_total(text: str) -> int:
    m = re.search(r"halal_places:.*?total:(\d+)", text, re.S)
    return int(m.group(1)) if m else 0


async def build_halal(client: httpx.AsyncClient, pause: float = 1.0, max_pages: int = 400):
    """Halal places listed on Muslim.sg (MUIS's lifestyle platform), fetched gently. Walks
    every page up to the listed total; a page that cannot be read is skipped."""
    out: list[dict] = []
    seen: set[tuple[str, str]] = set()
    last = max_pages
    page = 1
    while page <= last:
        resp = await client.get(HALAL_URL, params={"page": page}, headers=HALAL_HEADERS)
        resp.raise_for_status()
        if page == 1:
            total = halal_total(resp.text)
            if total:
                last = min(max_pages, -(-total // 20))
        items = parse_halal_page(resp.text)
        if not items and page == 1:
            break
        for it in items:
            key = (it["n"].upper(), it["a"].upper())
            if key not in seen:
                seen.add(key)
                out.append(it)
        page += 1
        await asyncio.sleep(pause)
    return out
