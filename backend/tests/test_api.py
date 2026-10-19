import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

DATAGOV = "https://api-open.data.gov.sg/v2/real-time/api"
LTA = "https://datamall2.mytransport.sg/ltaodataservice"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    get_settings.cache_clear()


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_weather_not_polled_yet(client):
    assert client.get("/v1/weather/forecast").status_code == 503
    assert client.get("/v1/weather/nope").status_code == 404


@respx.mock
def test_poll_then_read(client):
    respx.get(url__startswith=DATAGOV).mock(
        return_value=httpx.Response(200, json={"code": 0, "data": {"items": []}})
    )
    respx.get(f"{LTA}/TrainServiceAlerts").mock(
        return_value=httpx.Response(200, json={"value": {"Status": 1}})
    )
    first = client.post("/internal/poll").json()
    assert first["nea:two-hr-forecast"] == "changed"
    assert first["lta:train-alerts"] == "changed"
    # second call inside the interval is skipped, no upstream hit
    assert client.post("/internal/poll").json()["nea:two-hr-forecast"] == "skipped"
    body = client.get("/v1/weather/forecast").json()
    assert body["data"]["code"] == 0
    assert client.get("/v1/train-alerts").json()["data"]["value"]["Status"] == 1


@respx.mock
def test_bus_arrival_cached(client):
    route = respx.get(f"{LTA}/v3/BusArrival").mock(
        return_value=httpx.Response(200, json={"BusStopCode": "83139", "Services": []})
    )
    assert client.get("/v1/bus-arrival/83139").json()["data"]["BusStopCode"] == "83139"
    client.get("/v1/bus-arrival/83139")
    assert route.call_count == 1  # second request served from memory
    assert route.calls[0].request.headers["AccountKey"] == "test-key"


def test_bus_arrival_validates(client):
    assert client.get("/v1/bus-arrival/12ab").status_code == 422


def test_poll_requires_signature_in_prod(monkeypatch):
    monkeypatch.setenv("ENV", "prod")
    monkeypatch.setenv("QSTASH_CURRENT_SIGNING_KEY", "x")
    monkeypatch.setenv("QSTASH_NEXT_SIGNING_KEY", "y")
    get_settings.cache_clear()
    with TestClient(app) as c:
        assert c.post("/internal/poll").status_code == 401
    get_settings.cache_clear()
