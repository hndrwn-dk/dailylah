"""Guards on /v1/places so DailyLah cannot use up the Geoapify credits it shares with another
app: a daily budget, a per-second cap and a pause after Geoapify refuses (docs/PLACE_SEARCH.md)."""

import logging

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.cache import Cache
from app.config import get_settings
from app.geoapify import AUTOCOMPLETE_URL
from app.limits import Breaker, RateGate, budget_key
from app.main import _HideQuery, app

ROW = {"name": "Lau Pa Sat", "address_line2": "18 Raffles Quay", "lat": 1.28, "lon": 103.85}
OK = httpx.Response(200, json={"results": [ROW]})


class Clock:
    def __init__(self) -> None:
        self.t = 1000.0

    def __call__(self) -> float:
        return self.t


@pytest.fixture
def make_client(monkeypatch):
    def make(**env):
        monkeypatch.setenv("ENV", "dev")
        monkeypatch.setenv("GEOAPIFY_API_KEY", "k")
        monkeypatch.delenv("REDIS_URL", raising=False)
        for k, v in env.items():
            monkeypatch.setenv(k, str(v))
        get_settings.cache_clear()
        return TestClient(app)

    yield make
    get_settings.cache_clear()


# ------------------------------------------------------------------ building blocks


def test_rate_gate_allows_n_per_second():
    clock = Clock()
    gate = RateGate(2, clock=clock)
    assert gate.take() and gate.take()
    assert not gate.take()
    clock.t += 1.01
    assert gate.take()


def test_breaker_pauses_then_reopens():
    clock = Clock()
    b = Breaker(clock=clock)
    assert not b.paused()
    b.pause(60)
    assert b.paused()
    b.pause(5)  # a shorter pause never cuts a longer one
    clock.t += 59
    assert b.paused()
    clock.t += 2
    assert not b.paused()


def test_budget_key_is_per_utc_day():
    assert budget_key("2026-11-09") == "geoapify:budget:2026-11-09"


async def test_cache_incr_counts_in_memory_without_redis():
    c = Cache(None)
    assert [await c.incr("k", 60) for _ in range(3)] == [1, 2, 3]
    assert await c.incr("other", 60) == 1


class FakeRedis:
    def __init__(self, fail: bool = False) -> None:
        self.n: dict[str, int] = {}
        self.expires: dict[str, int] = {}
        self.fail = fail
        self.calls = 0

    async def incr(self, key):
        self.calls += 1
        if self.fail:
            raise ConnectionError("down")
        self.n[key] = self.n.get(key, 0) + 1
        return self.n[key]

    async def expire(self, key, ttl):
        self.calls += 1
        self.expires[key] = ttl


async def test_cache_incr_uses_redis_and_sets_expiry_once():
    c = Cache(None)
    c._redis = FakeRedis()
    assert await c.incr("k", 172800) == 1
    assert await c.incr("k", 172800) == 2
    assert c._redis.expires == {"k": 172800}
    assert c._redis.calls == 3  # INCR, EXPIRE, INCR: one command per call after the first


async def test_cache_incr_falls_back_to_memory_when_redis_fails():
    c = Cache(None)
    c._redis = FakeRedis(fail=True)
    assert await c.incr("k", 60) == 1
    assert await c.incr("k", 60) == 2


# ------------------------------------------------------------------ the endpoint


@respx.mock
def test_daily_budget_stops_geoapify_and_keeps_cached_answers(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(PLACES_DAILY_BUDGET=2, PLACES_PER_SECOND=100) as client:
        assert client.get("/v1/places", params={"q": "lau pa sat"}).status_code == 200
        assert client.get("/v1/places", params={"q": "jewel"}).status_code == 200
        r = client.get("/v1/places", params={"q": "haidilao"})
        assert r.status_code == 503
        assert r.json() == {"detail": "place search daily limit reached"}
        assert route.call_count == 2
        # A query already answered today is still served from memory.
        assert client.get("/v1/places", params={"q": "Lau Pa Sat"}).status_code == 200
        assert route.call_count == 2


@respx.mock
def test_per_second_cap(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(PLACES_PER_SECOND=1) as client:
        assert client.get("/v1/places", params={"q": "lau pa sat"}).status_code == 200
        r = client.get("/v1/places", params={"q": "jewel"})
        assert r.status_code == 503
        assert r.json() == {"detail": "place search busy"}
        assert route.call_count == 1


@pytest.mark.parametrize("status,seconds", [(429, 60), (401, 600), (403, 600)])
@respx.mock
def test_refusal_pauses_place_search(make_client, status, seconds):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=httpx.Response(status))
    with make_client() as client:
        assert client.get("/v1/places", params={"q": "lau pa sat"}).status_code == 502
        r = client.get("/v1/places", params={"q": "jewel"})
        assert r.status_code == 503
        assert r.json() == {"detail": "place search paused"}
        assert route.call_count == 1  # no call while paused
        breaker = client.app.state.places_breaker
        assert seconds - 5 < breaker.until - breaker.clock() <= seconds


@respx.mock
def test_server_error_does_not_pause(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(side_effect=[httpx.Response(500), OK])
    with make_client() as client:
        assert client.get("/v1/places", params={"q": "lau pa sat"}).status_code == 502
        assert client.get("/v1/places", params={"q": "jewel"}).status_code == 200
        assert route.call_count == 2


# ------------------------------------------------------------------ access log


def access_record(path: str) -> logging.LogRecord:
    return logging.LogRecord(
        "uvicorn.access",
        logging.INFO,
        "",
        0,
        '%s - "%s %s HTTP/%s" %d',
        ("1.2.3.4:5", "GET", path, "1.1", 200),
        None,
    )


def test_access_log_keeps_path_but_not_query():
    rec = access_record("/v1/places?q=my+home+address")
    assert _HideQuery().filter(rec)
    assert rec.getMessage() == '1.2.3.4:5 - "GET /v1/places HTTP/1.1" 200'
    rec = access_record("/v1/search?q=560201")
    _HideQuery().filter(rec)
    assert "560201" not in rec.getMessage()
    rec = access_record("/health")
    _HideQuery().filter(rec)
    assert rec.getMessage() == '1.2.3.4:5 - "GET /health HTTP/1.1" 200'


def test_access_log_filter_is_installed():
    assert any(isinstance(f, _HideQuery) for f in logging.getLogger("uvicorn.access").filters)
