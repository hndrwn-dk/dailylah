import json

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.sources import compact_carparks, compact_taxi_stands, compact_taxis

LTA = "https://datamall2.mytransport.sg/ltaodataservice"
CARPARK = "https://api.data.gov.sg/v1/transport/carpark-availability"
DATASTORE = "https://data.gov.sg/api/action/datastore_search"

CARPARK_PAYLOAD = {
    "items": [
        {
            "timestamp": "2026-10-20T11:56:36+08:00",
            "carpark_data": [
                {
                    "carpark_info": [
                        {"lot_type": "C", "lots_available": "102", "total_lots": "105"}
                    ],
                    "carpark_number": "HE12",
                },
                {
                    "carpark_info": [
                        {"lot_type": "Y", "lots_available": "5", "total_lots": "10"},
                        {"lot_type": "C", "lots_available": "0", "total_lots": "583"},
                    ],
                    "carpark_number": "HLM",
                },
                {
                    "carpark_info": [{"lot_type": "C", "lots_available": "x"}],
                    "carpark_number": "BAD",
                },
            ],
        }
    ]
}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    get_settings.cache_clear()


def test_compact_carparks_keeps_car_lots_only():
    assert compact_carparks(CARPARK_PAYLOAD) == {"HE12": [105, 102], "HLM": [583, 0]}
    assert compact_carparks({}) == {}


def test_compact_taxis_rounds():
    pts = [{"Latitude": 1.3768498722, "Longitude": 103.9324467257}, {"Latitude": "x"}]
    assert compact_taxis(pts) == [[1.3768, 103.9324]]


@respx.mock
def test_poll_fills_carpark_and_taxi(client):
    respx.get(url__startswith="https://api-open.data.gov.sg").mock(
        return_value=httpx.Response(200, json={"code": 0, "data": {}})
    )
    respx.get(f"{LTA}/TrainServiceAlerts").mock(
        return_value=httpx.Response(200, json={"value": {}})
    )
    respx.get(CARPARK).mock(return_value=httpx.Response(200, json=CARPARK_PAYLOAD))

    def taxi_page(request):
        skip = int(request.url.params["$skip"])
        rows = [{"Latitude": 1.3, "Longitude": 103.8}] * (500 if skip == 0 else 3)
        return httpx.Response(200, json={"value": rows})

    taxi_route = respx.get(f"{LTA}/Taxi-Availability").mock(side_effect=taxi_page)

    result = client.post("/internal/poll").json()
    assert result["dg:carpark"] == "changed"
    assert result["lta:taxi"] == "changed"
    assert taxi_route.call_count == 2

    assert client.get("/v1/carpark").json()["data"]["HE12"] == [105, 102]
    assert len(client.get("/v1/taxi").json()["data"]) == 503


def test_carpark_and_taxi_before_poll(client):
    assert client.get("/v1/carpark").status_code == 503
    assert client.get("/v1/taxi").status_code == 503


@respx.mock
def test_agent_lookup_cached(client):
    route = respx.get(DATASTORE).mock(
        return_value=httpx.Response(
            200,
            json={
                "result": {
                    "records": [
                        {
                            "salesperson_name": "TAN AH KOW",
                            "registration_no": "R012345A",
                            "registration_start_date": "2015-01-01",
                            "registration_end_date": "2027-12-31",
                            "estate_agent_name": "SOME REALTY",
                            "estate_agent_license_no": "L3001234A",
                        }
                    ]
                }
            },
        )
    )
    body = client.get("/v1/agent/r012345a").json()
    assert body["data"][0]["name"] == "TAN AH KOW"
    assert body["data"][0]["agency"] == "SOME REALTY"
    client.get("/v1/agent/R012345A")
    assert route.call_count == 1
    params = route.calls[0].request.url.params
    assert json.loads(params["filters"]) == {"registration_no": "R012345A"}


@respx.mock
def test_agent_not_found_returns_empty(client):
    respx.get(DATASTORE).mock(return_value=httpx.Response(200, json={"result": {"records": []}}))
    assert client.get("/v1/agent/R999999Z").json()["data"] == []


def test_agent_validates_format(client):
    assert client.get("/v1/agent/12345").status_code == 422


def test_compact_taxi_stands():
    rows = [
        {
            "TaxiCode": "A01",
            "Latitude": 1.30365,
            "Longitude": 103.83253,
            "Bfa": "Yes",
            "Ownership": "LTA",
            "Type": "Stand",
            "Name": "Orchard Rd along Ion Orchard",
        },
        {"TaxiCode": "B02", "Latitude": "x", "Longitude": 103.8},
    ]
    assert compact_taxi_stands(rows) == [
        {
            "n": "Orchard Rd along Ion Orchard",
            "la": 1.30365,
            "lo": 103.83253,
            "d": "Taxi stand · Barrier-free",
        }
    ]
