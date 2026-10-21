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


@respx.mock
def test_carpark_and_taxi_before_poll_upstream_down(client):
    respx.get(url__regex=r".*").mock(return_value=httpx.Response(500))
    assert client.get("/v1/carpark").status_code == 502
    assert client.get("/v1/taxi").status_code == 502


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


def test_compact_parking_incidents_routes():
    from app.sources import compact_bus_routes, compact_incidents, compact_parking

    rows = [
        {
            "CarParkID": "1",
            "Development": "Suntec City",
            "Location": "1.29375 103.85718",
            "AvailableLots": 2206,
            "LotType": "C",
            "Agency": "LTA",
        },
        {
            "CarParkID": "ACB",
            "Development": "BLK 270/271",
            "Location": "1.30 103.85",
            "AvailableLots": 12,
            "LotType": "Y",
            "Agency": "HDB",
        },
        {"CarParkID": "H1", "Location": "1.3 103.8", "AvailableLots": 3, "LotType": "H"},
        {"CarParkID": "bad", "Location": "", "AvailableLots": 1, "LotType": "C"},
    ]
    assert compact_parking(rows) == [
        ["1", "LTA", 1.29375, 103.85718, "C", 2206, "Suntec City"],
        ["ACB", "HDB", 1.3, 103.85, "Y", 12, "BLK 270/271"],
    ]
    assert compact_incidents(
        [
            {
                "Type": "Accident",
                "Latitude": 1.4264,
                "Longitude": 103.7818,
                "Message": "Accident on SLE",
            }
        ]
    ) == [["Accident", 1.4264, 103.7818, "Accident on SLE"]]
    routes = compact_bus_routes(
        [
            {
                "ServiceNo": "10",
                "Direction": 1,
                "StopSequence": 2,
                "BusStopCode": "76059",
                "Distance": 0.6,
            },
            {
                "ServiceNo": "10",
                "Direction": 1,
                "StopSequence": 1,
                "BusStopCode": "75009",
                "Distance": 0,
            },
            {
                "ServiceNo": "10",
                "Direction": 2,
                "StopSequence": 1,
                "BusStopCode": "10009",
                "Distance": 0,
            },
        ]
    )
    assert routes == {"10|1": [["75009", 0.0], ["76059", 0.6]], "10|2": [["10009", 0.0]]}


@respx.mock
def test_poll_fills_parking_and_incidents(client):
    respx.get(url__startswith="https://api-open.data.gov.sg").mock(
        return_value=httpx.Response(200, json={"code": 0, "data": {}})
    )
    respx.get(CARPARK).mock(return_value=httpx.Response(200, json=CARPARK_PAYLOAD))
    respx.get(f"{LTA}/TrainServiceAlerts").mock(
        return_value=httpx.Response(200, json={"value": {}})
    )
    respx.get(f"{LTA}/Taxi-Availability").mock(return_value=httpx.Response(200, json={"value": []}))
    respx.get(f"{LTA}/CarParkAvailabilityv2").mock(
        return_value=httpx.Response(
            200,
            json={
                "value": [
                    {
                        "CarParkID": "1",
                        "Location": "1.29 103.85",
                        "AvailableLots": 5,
                        "LotType": "C",
                        "Agency": "LTA",
                        "Development": "X",
                    }
                ]
            },
        )
    )
    respx.get(f"{LTA}/TrafficIncidents").mock(
        return_value=httpx.Response(
            200,
            json={
                "value": [{"Type": "Roadwork", "Latitude": 1.3, "Longitude": 103.8, "Message": "M"}]
            },
        )
    )
    result = client.post("/internal/poll").json()
    assert result["lta:parking"] == "changed"
    assert client.get("/v1/parking").json()["data"][0][0] == "1"
    assert client.get("/v1/traffic-incidents").json()["data"][0][0] == "Roadwork"


def test_compact_racks():
    from app import bundles as b

    desc = (
        "<table><tr> <th>SHLTR_IND</th> <td>Yes</td> </tr>"
        "<tr> <th>RACK_CNT</th> <td>12</td> </tr></table>"
    )
    out = b.compact_racks(
        {
            "features": [
                {
                    "properties": {"Description": desc},
                    "geometry": {"type": "Point", "coordinates": [103.8, 1.3]},
                }
            ]
        }
    )
    assert out == [{"n": "12 bicycle racks · sheltered", "la": 1.3, "lo": 103.8}]


ONEMAP_TOKEN = "https://www.onemap.gov.sg/api/auth/post/getToken"
ONEMAP_SEARCH = "https://www.onemap.gov.sg/api/common/elastic/search"


@respx.mock
def test_search_uses_onemap_token_and_caches(monkeypatch):
    monkeypatch.setenv("ONEMAP_EMAIL", "dev@example.com")
    monkeypatch.setenv("ONEMAP_PASSWORD", "x")
    get_settings.cache_clear()
    tok = respx.post(ONEMAP_TOKEN).mock(
        return_value=httpx.Response(
            200, json={"access_token": "T1", "expiry_timestamp": "9999999999"}
        )
    )
    hit = {
        "found": 1,
        "results": [{"POSTAL": "440066", "LATITUDE": "1.3039", "LONGITUDE": "103.9097"}],
    }
    search = respx.get(ONEMAP_SEARCH).mock(return_value=httpx.Response(200, json=hit))
    with TestClient(app) as client:
        r = client.get("/v1/search", params={"q": "440066"})
        assert r.status_code == 200
        assert r.json()["data"]["results"][0]["POSTAL"] == "440066"
        assert search.calls[0].request.headers["Authorization"] == "T1"
        client.get("/v1/search", params={"q": " 440066 "})
        assert search.call_count == 1  # served from memory
        assert tok.call_count == 1
        assert client.get("/v1/search", params={"q": "x"}).status_code == 422
    get_settings.cache_clear()


@respx.mock
def test_search_renews_token_when_rejected(monkeypatch):
    monkeypatch.setenv("ONEMAP_EMAIL", "dev@example.com")
    monkeypatch.setenv("ONEMAP_PASSWORD", "x")
    get_settings.cache_clear()
    respx.post(ONEMAP_TOKEN).mock(
        side_effect=[
            httpx.Response(200, json={"access_token": "OLD", "expiry_timestamp": "9999999999"}),
            httpx.Response(200, json={"access_token": "NEW", "expiry_timestamp": "9999999999"}),
        ]
    )
    respx.get(ONEMAP_SEARCH).mock(
        side_effect=[
            httpx.Response(401, json={}),
            httpx.Response(200, json={"found": 0, "results": []}),
        ]
    )
    with TestClient(app) as client:
        r = client.get("/v1/search", params={"q": "marine drive"})
        assert r.status_code == 200
    get_settings.cache_clear()
