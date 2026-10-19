import json

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app import build_static
from app.config import get_settings
from app.main import app
from app.sources import compact_bus_stops

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


@respx.mock
def test_crowd_realtime_cached_per_line(client):
    route = respx.get(f"{LTA}/PCDRealTime").mock(
        return_value=httpx.Response(200, json={"value": [{"Station": "NS1", "CrowdLevel": "l"}]})
    )
    body = client.get("/v1/crowd/nsl").json()
    assert body["data"]["value"][0]["CrowdLevel"] == "l"
    client.get("/v1/crowd/NSL")
    assert route.call_count == 1
    assert route.calls[0].request.url.params["TrainLine"] == "NSL"


@respx.mock
def test_crowd_forecast(client):
    respx.get(f"{LTA}/PCDForecast").mock(return_value=httpx.Response(200, json={"value": []}))
    assert client.get("/v1/crowd/EWL?kind=forecast").status_code == 200


def test_crowd_validation(client):
    assert client.get("/v1/crowd/XYZ").status_code == 404
    assert client.get("/v1/crowd/NSL?kind=weekly").status_code == 422


def _stop(i: int) -> dict:
    return {
        "BusStopCode": f"{i:05d}",
        "RoadName": "Road",
        "Description": f"Stop {i}",
        "Latitude": 1.3 + i * 1e-5,
        "Longitude": 103.8,
    }


def test_compact_bus_stops_skips_bad_rows():
    rows = [_stop(2), {"BusStopCode": "x"}, _stop(1)]
    out = compact_bus_stops(rows)
    assert [s["c"] for s in out] == ["00001", "00002"]
    assert set(out[0]) == {"c", "n", "r", "la", "lo"}


@respx.mock
async def test_build_static_paginates_and_writes(tmp_path, monkeypatch):
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    get_settings.cache_clear()
    all_stops = [_stop(i) for i in range(4200)]

    def page(request):
        skip = int(request.url.params["$skip"])
        return httpx.Response(200, json={"value": all_stops[skip : skip + 500]})

    route = respx.get(f"{LTA}/BusStops").mock(side_effect=page)
    async with httpx.AsyncClient() as c:
        manifest = await build_static.build(tmp_path, c)
    assert route.call_count == 9  # 8 full pages + 1 partial
    assert manifest["files"]["bus_stops"]["count"] == 4200
    stops = json.loads((tmp_path / "bus_stops.json").read_text())
    assert len(stops) == 4200
    assert json.loads((tmp_path / "manifest.json").read_text())["version"] == manifest["version"]
    get_settings.cache_clear()


@respx.mock
async def test_build_static_refuses_tiny_result(tmp_path, monkeypatch):
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    get_settings.cache_clear()
    respx.get(f"{LTA}/BusStops").mock(return_value=httpx.Response(200, json={"value": [_stop(1)]}))
    async with httpx.AsyncClient() as c:
        with pytest.raises(RuntimeError):
            await build_static.build(tmp_path, c)
    assert not (tmp_path / "bus_stops.json").exists()
    get_settings.cache_clear()
