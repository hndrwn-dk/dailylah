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
from .sources import CEA_REG_RE, LTA_DATASETS, NEA_DATASETS, TRAIN_LINES, Dataset, Sources

log = logging.getLogger("dailylah")
STOP_RE = re.compile(r"^\d{5}$")
WEATHER_KEYS = {
    "forecast": "nea:two-hr-forecast",
    "rainfall": "nea:rainfall",
    "psi": "nea:psi",
    "pm25": "nea:pm25",
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


@app.get("/v1/crowd/{line}")
async def crowd(
    line: str,
    kind: str = "realtime",
    c: Cache = Depends(cache),
    src: Sources = Depends(sources),
) -> dict:
    """Platform crowd density per line, on demand. LTA refreshes realtime every 10 min."""
    line = line.upper()
    if line not in TRAIN_LINES:
        raise HTTPException(404, f"unknown train line: {line}")
    if kind not in ("realtime", "forecast"):
        raise HTTPException(422, "kind must be realtime or forecast")
    key = f"lta:crowd:{kind}:{line}"
    hit = await c.get(key)
    if hit is not None:
        return hit
    try:
        data = await src.crowd(line, kind)
    except httpx.HTTPError as e:
        raise HTTPException(502, "upstream LTA error") from e
    data = {"fetched_at": int(time.time()), "data": data}
    c.set_memory_only(key, data, 600 if kind == "realtime" else 1800)
    return data


CARPARK_KEY = "dg:carpark"
TAXI_KEY = "lta:taxi"
PARKING_KEY = "lta:parking"
INCIDENTS_KEY = "lta:incidents"


@app.get("/v1/carpark")
async def carpark(c: Cache = Depends(cache)) -> dict:
    """All HDB car parks: {"data": {"ACB": [total, available]}}. Polled every 3 min."""
    data = await c.get(CARPARK_KEY)
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/taxi")
async def taxi(c: Cache = Depends(cache)) -> dict:
    """Available taxi positions [[lat, lng]], rounded. Polled every 5 min."""
    data = await c.get(TAXI_KEY)
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/parking")
async def parking(c: Cache = Depends(cache)) -> dict:
    """Live lots for LTA/URA/HDB car parks: [[id, agency, lat, lng, lot_type, available, name]].
    lot_type C is cars, Y is motorcycles. Polled every 3 min."""
    data = await c.get(PARKING_KEY)
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/traffic-incidents")
async def traffic_incidents(c: Cache = Depends(cache)) -> dict:
    """Current traffic incidents: [[type, lat, lng, message]]. Polled every 5 min."""
    data = await c.get(INCIDENTS_KEY)
    if data is None:
        raise HTTPException(503, "data not polled yet")
    return data


@app.get("/v1/agent/{reg_no}")
async def agent(
    reg_no: str,
    c: Cache = Depends(cache),
    src: Sources = Depends(sources),
    s: Settings = Depends(get_settings),
) -> dict:
    """CEA salesperson register lookup. Public register data, cached for a day."""
    reg = reg_no.strip().upper()
    if not CEA_REG_RE.match(reg):
        raise HTTPException(422, "registration number looks like R012345A")
    key = f"cea:{reg}"
    hit = await c.get(key)
    if hit is not None:
        return hit
    try:
        rows = await src.cea_agent(reg)
    except httpx.HTTPError as e:
        raise HTTPException(502, "upstream data.gov.sg error") from e
    data = {"fetched_at": int(time.time()), "data": rows}
    c.set_memory_only(key, data, s.agent_ttl)
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


async def _poll_key(request: Request, key: str, every_s: int, ttl_s: int, fetch) -> str:
    """Runs fetch() if [key] is due, and caches its result. One bad source never stops the rest."""
    st = request.app.state
    now = time.monotonic()
    if now - st.last_poll.get(key, -1e9) < every_s:
        return "skipped"
    try:
        data = await fetch()
    except Exception as e:  # noqa: BLE001
        log.warning("poll %s failed: %s", key, e)
        return "error"
    st.last_poll[key] = now
    changed = await st.cache.set(key, {"fetched_at": int(time.time()), "data": data}, ttl_s)
    return "changed" if changed else "unchanged"


async def _poll_one(request: Request, ds: Dataset, kind: str) -> str:
    src = request.app.state.sources
    fetch = (lambda: src.datagov(ds)) if kind == "nea" else (lambda: src.lta(ds.path))
    return await _poll_key(request, ds.key, ds.every_s, ds.ttl_s, fetch)


@app.post("/internal/poll", dependencies=[Depends(verify_qstash)])
async def poll(request: Request) -> dict:
    """Called every ~2 min by QStash. Each dataset keeps its own interval."""
    result = {}
    for ds in NEA_DATASETS:
        result[ds.key] = await _poll_one(request, ds, "nea")
    src = request.app.state.sources
    result[CARPARK_KEY] = await _poll_key(request, CARPARK_KEY, 180, 900, src.carpark_availability)
    if get_settings().lta_account_key:
        for ds in LTA_DATASETS:
            result[ds.key] = await _poll_one(request, ds, "lta")
        result[TAXI_KEY] = await _poll_key(request, TAXI_KEY, 300, 900, src.taxis)
        result[PARKING_KEY] = await _poll_key(request, PARKING_KEY, 180, 900, src.parking)
        result[INCIDENTS_KEY] = await _poll_key(
            request, INCIDENTS_KEY, 300, 900, src.traffic_incidents
        )
    return result
