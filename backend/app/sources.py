"""Thin async clients for data.gov.sg and LTA DataMall."""

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
