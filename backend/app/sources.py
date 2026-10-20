"""Thin async clients for data.gov.sg and LTA DataMall."""

import json
import re
from dataclasses import dataclass

import httpx

from .config import Settings


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
    Dataset("nea:uv", "uv", every_s=1800, ttl_s=3600),
    Dataset("nea:wbgt", "weather", every_s=900, ttl_s=1800, params={"api": "wbgt"}),
    Dataset("nea:lightning", "weather", every_s=300, ttl_s=900, params={"api": "lightning"}),
]

# LTA datasets polled centrally (small, shared by everyone).
LTA_DATASETS: list[Dataset] = [
    Dataset("lta:train-alerts", "TrainServiceAlerts", every_s=120, ttl_s=600),
]


class Sources:
    def __init__(self, settings: Settings, client: httpx.AsyncClient) -> None:
        self.s = settings
        self.http = client

    async def datagov(self, ds: Dataset) -> dict:
        headers = {"x-api-key": self.s.datagov_api_key} if self.s.datagov_api_key else {}
        r = await self.http.get(
            f"{self.s.datagov_base_url}/{ds.path}", params=ds.params, headers=headers
        )
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

    async def crowd(self, line: str, kind: str) -> dict:
        """Platform crowd density for one train line. kind: "realtime" or "forecast"."""
        path = "PCDRealTime" if kind == "realtime" else "PCDForecast"
        return await self.lta(path, {"TrainLine": line})

    async def carpark_availability(self) -> dict[str, list[int]]:
        """All HDB car parks: {"ACB": [total_car_lots, available_car_lots]}."""
        r = await self.http.get(self.s.carpark_url, headers=self._datagov_headers())
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
        r = await self.http.get(
            self.s.datastore_url,
            params={
                "resource_id": self.s.cea_dataset_id,
                "filters": json.dumps({"registration_no": reg_no}),
                "limit": 5,
            },
            headers=self._datagov_headers(),
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

    def _datagov_headers(self) -> dict:
        return {"x-api-key": self.s.datagov_api_key} if self.s.datagov_api_key else {}

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


def compact_taxis(points: list[dict]) -> list[list[float]]:
    """LTA Taxi-Availability rows -> [[lat, lng]] rounded to 4 decimals (~11 m)."""
    out = []
    for p in points:
        try:
            out.append([round(float(p["Latitude"]), 4), round(float(p["Longitude"]), 4)])
        except (KeyError, TypeError, ValueError):
            continue
    return out
