"""DailyLah API.

Public, read-only endpoints for the Flutter app (/v1/*) and one internal
endpoint (/internal/poll) called by an Upstash QStash schedule.
"""

import logging
import re
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request

from .cache import Cache
from .config import Settings, get_settings
from .sources import LTA_DATASETS, NEA_DATASETS, Dataset, Sources

log = logging.getLogger("dailylah")
STOP_RE = re.compile(r"^\d{5}$")
WEATHER_KEYS = {
    "forecast": "nea:two-hr-forecast",
    "rainfall": "nea:rainfall",
    "psi": "nea:psi",
    "uv": "nea:uv",
    "wbgt": "nea:wbgt",
    "lightning": "nea:lightning",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    s = get_settings()
    app.state.http = httpx.AsyncClient(timeout=s.http_timeout)
    app.state.cache = Cache(s.redis_url)
    app.state.sources = Sources(s, app.state.http)
    app.state.last_poll: dict[str, float] = {}
    yield
    await app.state.http.aclose()
    await app.state.cache.close()


app = FastAPI(title="DailyLah API", version="0.1.0", lifespan=lifespan)


def cache(request: Request) -> Cache:
    return request.app.state.cache


def sources(request: Request) -> Sources:
    return request.app.state.sources


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/weather/{kind}")
async def weather(kind: str, c: Cache = Depends(cache)) -> dict:
    key = WEATHER_KEYS.get(kind)
    if key is None:
        raise HTTPException(404, f"unknown weather kind: {kind}")
    data = await c.get(key)
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/train-alerts")
async def train_alerts(c: Cache = Depends(cache)) -> dict:
    data = await c.get("lta:train-alerts")
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/bus-arrival/{stop_code}")
async def bus_arrival(
    stop_code: str,
    c: Cache = Depends(cache),
    src: Sources = Depends(sources),
    s: Settings = Depends(get_settings),
) -> dict:
    """On-demand, memory-cached per stop. Never polled for all ~5,000 stops."""
    if not STOP_RE.match(stop_code):
        raise HTTPException(422, "stop_code must be 5 digits")
    key = f"lta:bus:{stop_code}"
    hit = await c.get(key)
    if hit is not None:
        return hit
    try:
        data = await src.bus_arrival(stop_code)
    except httpx.HTTPError as e:
        raise HTTPException(502, "upstream LTA error") from e
    data = {"fetched_at": int(time.time()), "data": data}
    c.set_memory_only(key, data, s.bus_arrival_ttl)  # memory only: saves Redis commands
    return data


async def verify_qstash(request: Request, s: Settings = Depends(get_settings)) -> None:
    if s.env == "dev" and not s.qstash_current_signing_key:
        return  # local dev: allow manual curl
    signature = request.headers.get("Upstash-Signature")
    if not signature:
        raise HTTPException(401, "missing signature")
    from qstash import Receiver

    receiver = Receiver(
        current_signing_key=s.qstash_current_signing_key,
        next_signing_key=s.qstash_next_signing_key,
    )
    body = (await request.body()).decode()
    try:
        receiver.verify(body=body, signature=signature, url=f"{s.public_base_url}/internal/poll")
    except Exception as e:  # noqa: BLE001 - SDK raises its own error types
        raise HTTPException(401, "invalid signature") from e


async def _poll_one(request: Request, ds: Dataset, kind: str) -> str:
    st = request.app.state
    now = time.monotonic()
    if now - st.last_poll.get(ds.key, -1e9) < ds.every_s:
        return "skipped"
    try:
        if kind == "nea":
            data = await st.sources.datagov(ds)
        else:
            data = await st.sources.lta(ds.path)
    except Exception as e:  # noqa: BLE001 - one bad source must not stop the rest
        log.warning("poll %s failed: %s", ds.key, e)
        return "error"
    st.last_poll[ds.key] = now
    changed = await st.cache.set(ds.key, {"fetched_at": int(time.time()), "data": data}, ds.ttl_s)
    return "changed" if changed else "unchanged"


@app.post("/internal/poll", dependencies=[Depends(verify_qstash)])
async def poll(request: Request) -> dict:
    """Called every ~2 min by QStash. Each dataset keeps its own interval."""
    result = {}
    for ds in NEA_DATASETS:
        result[ds.key] = await _poll_one(request, ds, "nea")
    for ds in LTA_DATASETS:
        if get_settings().lta_account_key:
            result[ds.key] = await _poll_one(request, ds, "lta")
    return result
