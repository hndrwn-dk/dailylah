"""Thin async clients for data.gov.sg and LTA DataMall."""

import json
import re
from dataclasses import dataclass

import httpx

from .config import Settings
from .datagov import DataGovKey


@dataclass(frozen=True)
class Dataset:
    key: str  # cache key, e.g. "nea:two-hr-forecast"
    path: str  # path under data.gov.sg real-time API
    every_s: int  # minimum interval between polls
    ttl_s: int  # how long the cached value is served
    params: dict | None = None


# Real-time NEA datasets polled centrally by /internal/poll.
# Endpoints: https://api-open.data.gov.sg/v2/real-time/api/<path>
NEA_DATASETS: list[Dataset] = [
    Dataset("nea:two-hr-forecast", "two-hr-forecast", every_s=600, ttl_s=1800),
    Dataset("nea:rainfall", "rainfall", every_s=300, ttl_s=900),
    Dataset("nea:psi", "psi", every_s=1800, ttl_s=3600),
    Dataset("nea:pm25", "pm25", every_s=1800, ttl_s=3600),
    Dataset("nea:uv", "uv", every_s=1800, ttl_s=3600),
    Dataset("nea:wbgt", "weather", every_s=900, ttl_s=1800, params={"api": "wbgt"}),
    Dataset("nea:lightning", "weather", every_s=300, ttl_s=900, params={"api": "lightning"}),
]

# LTA datasets polled centrally (small, shared by everyone).
LTA_DATASETS: list[Dataset] = [
    Dataset("lta:train-alerts", "TrainServiceAlerts", every_s=120, ttl_s=600),
]


_KEYS: dict[str | None, DataGovKey] = {}


def _key_for(key: str | None) -> DataGovKey:
    """One DataGovKey per key value, so a rejected key is skipped for the life of the
    process (a new key in the env restarts the service)."""
    if key not in _KEYS:
        _KEYS[key] = DataGovKey(key)
    return _KEYS[key]


class Sources:
    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.s = settings
        self.http = client
        self.key = _key_for(settings.datagov_api_key)

    async def datagov(self, ds: Dataset) -> dict:
        r = await self.key.get(self.http, f"{self.s.datagov_base_url}/{ds.path}", ds.params)
        r.raise_for_status()
        return r.json()

    async def lta(self, path: str, params: dict | None = None) -> dict:
        if not self.s.lta_account_key:
            raise RuntimeError("LTA_ACCOUNT_KEY is not set")
        r = await self.http.get(
            f"{self.s.lta_base_url}/{path}",
            params=params,
            headers={"AccountKey": self.s.lta_account_key, "accept": "application/json"},
        )
        r.raise_for_status()
        return r.json()

    async def bus_arrival(self, stop_code: str) -> dict:
        return await self.lta("v3/BusArrival", {"BusStopCode": stop_code})

    async def ev_points(self, postal: str) -> dict:
        """EV charging points at one postal code, with live charger status."""
        return await self.lta("EVChargingPoints", {"PostalCode": postal})

    async def ev_batch(self) -> dict:
        """All EV charging points in Singapore: EVCBatch returns a link to one JSON file."""
        links = (await self.lta("EVCBatch")).get("value") or []
        link = links[0].get("Link") if isinstance(links, list) and links else None
        if not link:
            raise RuntimeError("EVCBatch returned no download link")
        r = await self.http.get(link)
        r.raise_for_status()
        return r.json()

    async def crowd(self, line: str, kind: str) -> dict:
        """Platform crowd density for one train line. kind: "realtime" or "forecast"."""
        path = "PCDRealTime" if kind == "realtime" else "PCDForecast"
        return await self.lta(path, {"TrainLine": line})

    async def carpark_availability(self) -> dict[str, list[int]]:
        """All HDB car parks: {"ACB": [total_car_lots, available_car_lots]}."""
        r = await self.key.get(self.http, self.s.carpark_url)
        r.raise_for_status()
        return compact_carparks(r.json())

    async def taxis(self, page_size: int = 500, max_pages: int = 20) -> list[list[float]]:
        """Available taxi positions, rounded to ~10 m: [[lat, lng], ...]."""
        pts: list[dict] = []
        for page in range(max_pages):
            batch = (await self.lta("Taxi-Availability", {"$skip": page * page_size})).get(
                "value", []
            )
            pts.extend(batch)
            if len(batch) < page_size:
                break
        return compact_taxis(pts)

    async def cea_agent(self, reg_no: str) -> list[dict]:
        """CEA salesperson register rows for one registration number."""
        r = await self.key.get(
            self.http,
            self.s.datastore_url,
            {
                "resource_id": self.s.cea_dataset_id,
                "filters": json.dumps({"registration_no": reg_no}),
                "limit": 5,
            },
        )
        r.raise_for_status()
        rows = r.json().get("result", {}).get("records", [])
        return [
            {
                "name": row.get("salesperson_name", ""),
                "registration_no": row.get("registration_no", ""),
                "start": row.get("registration_start_date", ""),
                "end": row.get("registration_end_date", ""),
                "agency": row.get("estate_agent_name", ""),
                "agency_licence": row.get("estate_agent_license_no", ""),
            }
            for row in rows
        ]

    async def taxi_stands(self, page_size: int = 500, max_pages: int = 10) -> list[dict]:
        """All taxi stands and stops (static, refreshed daily in the data bundle)."""
        rows: list[dict] = []
        for page in range(max_pages):
            batch = (await self.lta("TaxiStands", {"$skip": page * page_size})).get("value", [])
            rows.extend(batch)
            if len(batch) < page_size:
                break
        return rows

    async def _lta_all(self, path: str, page_size: int = 500, max_pages: int = 80) -> list[dict]:
        rows: list[dict] = []
        for page in range(max_pages):
            batch = (await self.lta(path, {"$skip": page * page_size})).get("value", [])
            rows.extend(batch)
            if len(batch) < page_size:
                break
        return rows

    async def parking(self) -> list[list]:
        """Live lots for LTA, URA and HDB car parks, by lot type (C car, Y motorcycle, H heavy)."""
        return compact_parking(await self._lta_all("CarParkAvailabilityv2", max_pages=12))

    async def traffic_incidents(self) -> list[list]:
        return compact_incidents((await self.lta("TrafficIncidents")).get("value", []))

    async def bus_routes(self) -> dict:
        return compact_bus_routes(await self._lta_all("BusRoutes", max_pages=80))

    async def bus_stops(self, page_size: int = 500, max_pages: int = 40) -> list[dict]:
        """All bus stops. LTA pages results 500 at a time via $skip."""
        stops: list[dict] = []
        for page in range(max_pages):
            batch = (await self.lta("BusStops", {"$skip": page * page_size})).get("value", [])
            stops.extend(batch)
            if len(batch) < page_size:
                break
        return stops


# Train line codes accepted by LTA's platform crowd density APIs.
TRAIN_LINES = {"CCL", "CEL", "CGL", "DTL", "EWL", "NEL", "NSL", "TEL", "BPL", "SLRT", "PLRT"}


def compact_bus_stops(raw: list[dict]) -> list[dict]:
    """Shrink LTA BusStops rows for the app's offline bundle (~5k stops)."""
    out = []
    for s in raw:
        try:
            out.append(
                {
                    "c": s["BusStopCode"],
                    "n": s["Description"],
                    "r": s.get("RoadName", ""),
                    "la": round(float(s["Latitude"]), 6),
                    "lo": round(float(s["Longitude"]), 6),
                }
            )
        except (KeyError, TypeError, ValueError):
            continue
    out.sort(key=lambda x: x["c"])
    return out


CEA_REG_RE = re.compile(r"^[A-Z]\d{6}[A-Z]$")


def compact_carparks(payload: dict) -> dict[str, list[int]]:
    """data.gov.sg v1 carpark-availability -> {"ACB": [total, available]} for car lots."""
    out: dict[str, list[int]] = {}
    items = payload.get("items") or []
    if not items:
        return out
    for cp in items[0].get("carpark_data", []):
        for info in cp.get("carpark_info", []):
            if info.get("lot_type") != "C":
                continue
            try:
                out[cp["carpark_number"]] = [int(info["total_lots"]), int(info["lots_available"])]
            except (KeyError, TypeError, ValueError):
                continue
    return out


def compact_parking(rows: list[dict]) -> list[list]:
    """[[id, agency, lat, lng, lot_type, available, name]], skipping heavy-vehicle lots."""
    out = []
    for r in rows:
        lot = str(r.get("LotType", ""))
        if lot not in ("C", "Y"):
            continue
        try:
            lat, lng = (round(float(x), 5) for x in str(r["Location"]).split())
            avail = int(r["AvailableLots"])
        except (KeyError, TypeError, ValueError):
            continue
        out.append(
            [
                str(r.get("CarParkID", "")),
                str(r.get("Agency", "")),
                lat,
                lng,
                lot,
                avail,
                str(r.get("Development", "")).strip(),
            ]
        )
    return out


def compact_incidents(rows: list[dict]) -> list[list]:
    """[[type, lat, lng, message]] for current traffic incidents."""
    out = []
    for r in rows:
        try:
            out.append(
                [
                    str(r.get("Type", "")),
                    round(float(r["Latitude"]), 5),
                    round(float(r["Longitude"]), 5),
                    str(r.get("Message", "")).strip(),
                ]
            )
        except (KeyError, TypeError, ValueError):
            continue
    return out


def compact_bus_routes(rows: list[dict]) -> dict:
    """{"<service>|<direction>": [[stop_code, km_from_start], ...]} in stop order."""
    routes: dict[str, list[tuple[int, str, float]]] = {}
    for r in rows:
        try:
            key = f"{r['ServiceNo']}|{int(r['Direction'])}"
            seq = int(r["StopSequence"])
            dist = round(float(r.get("Distance") or 0), 1)
        except (KeyError, TypeError, ValueError):
            continue
        routes.setdefault(key, []).append((seq, str(r.get("BusStopCode", "")), dist))
    return {k: [[code, dist] for _, code, dist in sorted(v)] for k, v in sorted(routes.items())}


EV_POSTAL_RE = re.compile(r"\b(\d{6})\b")


def _ev_locations(body: object) -> list[dict]:
    """evLocationsData from an EVChargingPoints or EVCBatch body, wrapped in "value" or not."""
    for cand in (body, body.get("value") if isinstance(body, dict) else None):
        if isinstance(cand, dict) and isinstance(cand.get("evLocationsData"), list):
            return cand["evLocationsData"]
        if isinstance(cand, list):
            rows: list[dict] = []
            for item in cand:
                if isinstance(item, dict) and isinstance(item.get("evLocationsData"), list):
                    rows.extend(item["evLocationsData"])
            if rows:
                return rows
    return []


def _ev_plugs(loc: dict, live: bool) -> list[dict]:
    """Chargers at one location grouped by plug, current and speed, fastest first:
    {"t": "Type 2", "c": "AC", "kw": 7.4, "p": 0.7, "pu": "kWh", "n": total, "a": free (live)}."""
    groups: dict[tuple, dict] = {}
    for cp in loc.get("chargingPoints") or []:
        for pt in cp.get("plugTypes") or []:
            try:
                kw = round(float(pt.get("chargingSpeed") or 0), 1)
            except (TypeError, ValueError):
                kw = 0.0
            plug = str(pt.get("plugType") or "").strip()
            current = str(pt.get("powerRating") or "").strip()
            g = groups.setdefault(
                (plug, current, kw),
                {"t": plug, "c": current, "kw": kw, "p": None, "pu": "", "n": 0},
            )
            price = pt.get("price")
            if isinstance(price, (int, float)) and (g["p"] is None or price < g["p"]):
                g["p"], g["pu"] = round(float(price), 3), str(pt.get("priceType") or "")
            ids = pt.get("evIds") or [{}]
            g["n"] += len(ids)
            if live:
                g["a"] = g.get("a", 0) + sum(1 for e in ids if str(e.get("status")) == "1")
    return sorted(groups.values(), key=lambda g: (-g["kw"], g["t"]))


def compact_ev_sites(body: object) -> list[dict]:
    """EVCBatch file -> [{"id", "n", "a", "pc", "la", "lo", "op": [operators], "pl": plugs}]
    for the daily ev.json bundle (no live status; the app asks /v1/ev/{postal} for that)."""
    out = []
    for loc in _ev_locations(body):
        try:
            lat, lng = round(float(loc["latitude"]), 5), round(float(loc["longitude"]), 5)
        except (KeyError, TypeError, ValueError):
            continue
        addr = str(loc.get("address") or "").strip()
        m = EV_POSTAL_RE.search(addr)
        if not m or not (1.1 < lat < 1.5 and 103.5 < lng < 104.1):
            continue
        ops = sorted(
            {str(cp.get("operator") or "").strip() for cp in loc.get("chargingPoints") or []} - {""}
        )
        out.append(
            {
                "id": str(loc.get("locationId") or ""),
                "n": str(loc.get("name") or "").strip(),
                "a": addr,
                "pc": m.group(1),
                "la": lat,
                "lo": lng,
                "op": ops,
                "pl": _ev_plugs(loc, live=False),
            }
        )
    return out


def compact_ev_live(body: object) -> list[dict]:
    """EVChargingPoints for one postal code -> [{"id", "n", "pl": plugs with "a" free}]."""
    return [
        {
            "id": str(loc.get("locationId") or ""),
            "n": str(loc.get("name") or "").strip(),
            "pl": _ev_plugs(loc, live=True),
        }
        for loc in _ev_locations(body)
    ]


def compact_taxi_stands(rows: list[dict]) -> list[dict]:
    """LTA TaxiStands -> [{"n": name, "la", "lo", "d": "Taxi stand · Barrier-free"}]."""
    out = []
    for r in rows:
        try:
            lat, lng = round(float(r["Latitude"]), 5), round(float(r["Longitude"]), 5)
        except (KeyError, TypeError, ValueError):
            continue
        kind = "Taxi stop" if str(r.get("Type", "")).lower() == "stop" else "Taxi stand"
        detail = kind + (" · Barrier-free" if str(r.get("Bfa", "")).lower() == "yes" else "")
        name = str(r.get("Name") or r.get("TaxiCode") or "").strip()
        out.append({"n": name, "la": lat, "lo": lng, "d": detail})
    return out


def compact_taxis(points: list[dict]) -> list[list[float]]:
    """LTA Taxi-Availability rows -> [[lat, lng]] rounded to 4 decimals (~11 m)."""
    out = []
    for p in points:
        try:
            out.append([round(float(p["Latitude"]), 4), round(float(p["Longitude"]), 4)])
        except (KeyError, TypeError, ValueError):
            continue
    return out
