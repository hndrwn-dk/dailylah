"""DailyLah API.

Public, read-only endpoints for the Flutter app (/v1/*) and one internal
endpoint (/internal/poll) called by an Upstash QStash schedule.
"""

import asyncio
import logging
import re
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request

from .cache import Cache
from .config import Settings, get_settings
from .onemap import OneMap
from .sources import CEA_REG_RE, LTA_DATASETS, NEA_DATASETS, TRAIN_LINES, Sources

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
    app.state.onemap = OneMap(app.state.http, s.onemap_email, s.onemap_password)
    app.state.last_poll: dict[str, float] = {}
    app.state.locks: dict[str, asyncio.Lock] = {}
    yield
    await app.state.http.aclose()
    await app.state.cache.close()


app = FastAPI(title="DailyLah API", version="0.1.0", lifespan=lifespan)


def cache(request: Request) -> Cache:
    return request.app.state.cache


def sources(request: Request) -> Sources:
    return request.app.state.sources


def onemap(request: Request) -> OneMap:
    return request.app.state.onemap


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/weather/{kind}")
async def weather(kind: str, request: Request) -> dict:
    key = WEATHER_KEYS.get(kind)
    if key is None:
        raise HTTPException(404, f"unknown weather kind: {kind}")
    return await _serve(request, key)


@app.get("/v1/train-alerts")
async def train_alerts(request: Request) -> dict:
    return await _serve(request, "lta:train-alerts")


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
async def carpark(request: Request) -> dict:
    """All HDB car parks: {"data": {"ACB": [total, available]}}. Polled every 3 min."""
    return await _serve(request, CARPARK_KEY)


@app.get("/v1/taxi")
async def taxi(request: Request) -> dict:
    """Available taxi positions [[lat, lng]], rounded. Polled every 5 min."""
    return await _serve(request, TAXI_KEY)


@app.get("/v1/parking")
async def parking(request: Request) -> dict:
    """Live lots for LTA/URA/HDB car parks: [[id, agency, lat, lng, lot_type, available, name]].
    lot_type C is cars, Y is motorcycles. Polled every 3 min."""
    return await _serve(request, PARKING_KEY)


@app.get("/v1/traffic-incidents")
async def traffic_incidents(request: Request) -> dict:
    """Current traffic incidents: [[type, lat, lng, message]]. Polled every 5 min."""
    return await _serve(request, INCIDENTS_KEY)


@app.get("/v1/search")
async def search(
    q: str,
    c: Cache = Depends(cache),
    om: OneMap = Depends(onemap),
    s: Settings = Depends(get_settings),
) -> dict:
    """Address and postal code search on OneMap, with our token. The query is not
    logged; results are kept in memory only for a day (same answer for everyone)."""
    query = " ".join(q.split())
    if not 2 <= len(query) <= 80:
        raise HTTPException(422, "query must be 2 to 80 characters")
    key = f"onemap:search:{query.upper()}"
    hit = c.get_memory(key)
    if hit is not None:
        return hit
    try:
        body = await om.search(query)
    except httpx.HTTPError as e:
        raise HTTPException(502, "upstream OneMap error") from e
    data = {"fetched_at": int(time.time()), "data": body}
    c.set_memory_only(key, data, s.search_ttl)
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


def _jobs(src: Sources, with_lta: bool) -> dict[str, tuple[int, int, object]]:
    """Every centrally polled key: (poll every s, cache ttl s, fetch)."""
    jobs: dict[str, tuple[int, int, object]] = {
        ds.key: (ds.every_s, ds.ttl_s, (lambda ds=ds: src.datagov(ds))) for ds in NEA_DATASETS
    }
    jobs[CARPARK_KEY] = (180, 900, src.carpark_availability)
    if with_lta:
        for ds in LTA_DATASETS:
            jobs[ds.key] = (ds.every_s, ds.ttl_s, (lambda ds=ds: src.lta(ds.path)))
        jobs[TAXI_KEY] = (300, 900, src.taxis)
        jobs[PARKING_KEY] = (180, 900, src.parking)
        jobs[INCIDENTS_KEY] = (300, 900, src.traffic_incidents)
    return jobs


async def _poll_key(
    request: Request, key: str, every_s: int, ttl_s: int, fetch, force: bool = False
) -> str:
    """Runs fetch() if [key] is due (or forced), and caches its result.
    One bad source never stops the rest."""
    st = request.app.state
    lock = st.locks.setdefault(key, asyncio.Lock())
    async with lock:
        now = time.monotonic()
        if not force and now - st.last_poll.get(key, -1e9) < every_s:
            return "skipped"
        if force and await st.cache.get(key) is not None:
            return "skipped"  # another request filled it while we waited
        try:
            data = await fetch()
        except Exception as e:  # noqa: BLE001
            log.warning("poll %s failed: %s", key, e)
            return "error"
        st.last_poll[key] = now
        changed = await st.cache.set(key, {"fetched_at": int(time.time()), "data": data}, ttl_s)
        return "changed" if changed else "unchanged"


async def _serve(request: Request, key: str) -> dict:
    """Cached value, or fetched now when the poller has not filled it (cold start,
    or the QStash schedule stopped). Concurrent misses share one upstream call."""
    c: Cache = request.app.state.cache
    data = await c.get(key)
    if data is not None:
        return data
    job = _jobs(request.app.state.sources, bool(get_settings().lta_account_key)).get(key)
    if job is None:
        raise HTTPException(503, "data not available")
    every_s, ttl_s, fetch = job
    await _poll_key(request, key, every_s, ttl_s, fetch, force=True)
    data = await c.get(key)
    if data is None:
        raise HTTPException(502, "upstream error")
    return data


@app.post("/internal/poll", dependencies=[Depends(verify_qstash)])
async def poll(request: Request) -> dict:
    """Called every ~2 min by QStash. Each dataset keeps its own interval."""
    jobs = _jobs(request.app.state.sources, bool(get_settings().lta_account_key))
    return {
        key: await _poll_key(request, key, every_s, ttl_s, fetch)
        for key, (every_s, ttl_s, fetch) in jobs.items()
    }
