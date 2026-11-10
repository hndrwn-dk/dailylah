"""Guards on /v1/places so DailyLah cannot use up the Geoapify credits it shares with another
app: a daily budget, a per-second cap, one client's share and a pause after Geoapify refuses."""

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.cache import Cache
from app.config import get_settings
from app.geoapify import AUTOCOMPLETE_URL
from app.limits import Blocked, Breaker, RateGate, budget_key, client_address, client_key
from app.main import app

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


def test_memory_counter_counts_per_key():
    c = Cache(None)
    assert [c.incr_memory("k", 60) for _ in range(3)] == [1, 2, 3]
    assert c.incr_memory("other", 60) == 1


def test_memory_counters_stay_bounded(monkeypatch):
    monkeypatch.setattr("app.cache.MAX_MEMORY_KEYS", 3)
    c = Cache(None)
    c.incr_memory("day", 172800)
    for i in range(10):
        c.incr_memory(f"client{i}", 60)
    assert len(c._counts) == 3
    assert c.incr_memory("day", 172800) == 2  # the long-lived count is kept


async def test_shared_counter_needs_redis():
    assert await Cache(None).incr_shared("k", 60) is None


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

    async def aclose(self):
        pass


async def test_shared_counter_uses_redis_and_sets_expiry_once():
    c = Cache(None)
    c._redis = FakeRedis()
    assert await c.incr_shared("k", 172800) == 1
    assert await c.incr_shared("k", 172800) == 2
    assert c._redis.expires == {"k": 172800}
    assert c._redis.calls == 3  # INCR, EXPIRE, INCR: one command per call after the first


async def test_shared_counter_gives_no_count_when_redis_fails_and_waits_before_retrying():
    c = Cache(None)
    c._redis = FakeRedis(fail=True)
    assert await c.incr_shared("k", 60) is None
    assert await c.incr_shared("k", 60) is None
    assert c._redis.calls == 1  # the second call did not reach Redis
    c._redis.fail = False
    c._redis_down_until = 0.0  # the wait is over
    assert await c.incr_shared("k", 60) == 1


CF = "203.0.113.7"


@pytest.mark.parametrize(
    "cf,forwarded,peer,expected",
    [
        # Cloudflare's header wins; nothing a client can put in X-Forwarded-For matters.
        (CF, ["198.51.100.1, 203.0.113.7, 172.71.0.9"], "10.0.0.5", CF),
        (CF, ["1.2.3.4"], "10.0.0.5", CF),
        # Without it: the last public entry, never one further left.
        (None, ["1.2.3.4, 8.8.8.8, 10.1.2.3"], "10.0.0.5", "8.8.8.8"),
        (None, ["1.2.3.4", "8.8.4.4"], "10.0.0.5", "8.8.4.4"),
        (None, ["1.2.3.4, not-an-address"], "10.0.0.5", "10.0.0.5"),
        (None, ["10.1.2.3, 192.168.1.1"], "10.0.0.5", "10.0.0.5"),
        (None, [], "10.0.0.5", "10.0.0.5"),
        ("garbage", [], "", "unknown"),
        # IPv6: one /64 is one client; a mapped IPv4 address is that IPv4 address.
        ("2001:4860:4860::8888", [], "x", "2001:4860:4860::/64"),
        ("2001:4860:4860:0:1:2:3:4", [], "x", "2001:4860:4860::/64"),
        ("::ffff:8.8.8.8", [], "x", "8.8.8.8"),
    ],
)
def test_client_address(cf, forwarded, peer, expected):
    assert client_address(cf, forwarded, peer) == expected


def test_client_key_hides_the_address_and_changes_with_the_window():
    a = client_key("secret", "8.8.8.8", 3600, now=7200.0)
    assert a == client_key("secret", "8.8.8.8", 3600, now=7200.0 + 3599)
    assert a != client_key("secret", "8.8.8.8", 3600, now=7200.0 + 3600)
    assert a != client_key("secret", "8.8.4.4", 3600, now=7200.0)
    assert a != client_key("other", "8.8.8.8", 3600, now=7200.0)
    assert "8.8.8.8" not in a and a.startswith("geoapify:client:2:")


def test_blocked_forgets_after_the_window_and_stays_bounded():
    clock = Clock()
    b = Blocked(max_keys=2, clock=clock)
    b.add("a", 60)
    assert b.has("a") and not b.has("other")
    clock.t += 61
    assert not b.has("a")
    for k in ("x", "y", "z"):
        b.add(k, 60)
    assert len(b._until) == 2 and b.has("z")


def test_one_client_alone_cannot_spend_the_default_daily_budget():
    s = get_settings()
    assert s.places_client_limit * 86400 / s.places_client_window < s.places_daily_budget
    # Below the key's daily cap of 2,000, with room for the daily data build.
    assert s.places_daily_budget + s.places_memory_budget <= 1950


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


# ------------------------------------------------------------------ one client's share


def ask(client, q, ip=CF, forwarded=None):
    headers = {"CF-Connecting-IP": ip}
    if forwarded:
        headers["X-Forwarded-For"] = forwarded
    return client.get("/v1/places", params={"q": q}, headers=headers)


@respx.mock
def test_client_over_its_share_gets_429_and_others_are_served(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(PLACES_CLIENT_LIMIT=2, PLACES_PER_SECOND=100) as client:
        assert ask(client, "lau pa sat").status_code == 200
        assert ask(client, "jewel").status_code == 200
        r = ask(client, "haidilao")
        assert r.status_code == 429
        assert r.json() == {"detail": "too many place searches"}
        assert r.headers["retry-after"] == "3600"
        # A changing X-Forwarded-For does not make it a new client.
        assert ask(client, "ion", forwarded="198.51.100.9").status_code == 429
        assert route.call_count == 2
        # Answers already in memory are still served, and another client is not affected.
        assert ask(client, "Jewel").status_code == 200
        assert ask(client, "vivocity", ip="203.0.113.8").status_code == 200
        assert route.call_count == 3


@respx.mock
def test_client_over_its_share_costs_no_more_redis_commands(make_client):
    respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(PLACES_CLIENT_LIMIT=1, PLACES_PER_SECOND=100) as client:
        redis = FakeRedis()
        app.state.cache._redis = redis
        assert ask(client, "lau pa sat").status_code == 200
        assert ask(client, "jewel").status_code == 429
        calls = redis.calls
        for q in ("ion", "vivocity", "bugis"):
            assert ask(client, q).status_code == 429
        assert redis.calls == calls
        # The client's count is kept under a short expiry, the day's count for two days.
        assert sorted(redis.expires.values()) == [3600, 172800]
        assert not any(CF in key for key in redis.n)


# ------------------------------------------------------------------ without a shared count


@respx.mock
def test_without_redis_only_the_small_memory_budget_is_spent(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(PLACES_MEMORY_BUDGET=2, PLACES_PER_SECOND=100) as client:
        assert ask(client, "lau pa sat").status_code == 200
        assert ask(client, "jewel").status_code == 200
        r = ask(client, "haidilao")
        assert r.status_code == 503
        assert r.json() == {"detail": "place search daily limit reached"}
        assert route.call_count == 2


@respx.mock
def test_redis_failing_mid_day_does_not_restart_the_budget(make_client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=OK)
    with make_client(
        PLACES_DAILY_BUDGET=50, PLACES_MEMORY_BUDGET=1, PLACES_PER_SECOND=100
    ) as client:
        redis = FakeRedis()
        app.state.cache._redis = redis
        for q in ("lau pa sat", "jewel", "ion"):
            assert ask(client, q).status_code == 200
        redis.fail = True
        # One call on the memory budget, then closed: not another 50.
        assert ask(client, "vivocity").status_code == 200
        assert ask(client, "bugis").status_code == 503
        assert ask(client, "tampines mall").status_code == 503
        assert route.call_count == 4
        # Redis is back: the shared count carries on where it stopped.
        redis.fail = False
        app.state.cache._redis_down_until = 0.0
        assert ask(client, "nex").status_code == 200
        assert redis.n[budget_key()] == 4
