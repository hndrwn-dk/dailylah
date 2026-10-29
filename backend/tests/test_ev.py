import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.sources import Settings, Sources, compact_ev_live, compact_ev_sites

LTA = "https://datamall2.mytransport.sg/ltaodataservice"

LOCATION = {
    "address": "65A MARINE DRIVE SINGAPORE 441065",
    "name": "BLK 65A MARINE DRIVE MULTI STOREY CAR PARK",
    "longitude": 103.9101,
    "latitude": 1.30215,
    "locationId": "441065001",
    "status": "1",
    "chargingPoints": [
        {
            "status": "1",
            "operator": "STRIDES YTL PTE. LTD.",
            "position": "L3 336",
            "name": "65A",
            "plugTypes": [
                {
                    "plugType": "Type 2",
                    "powerRating": "AC",
                    "chargingSpeed": 7.4,
                    "price": 0.698,
                    "priceType": "kWh",
                    "evIds": [{"evCpId": "A-1", "status": "1"}, {"evCpId": "A-2", "status": "0"}],
                }
            ],
        },
        {
            "status": "100",
            "operator": "SP MOBILITY",
            "position": "L1",
            "name": "65A fast",
            "plugTypes": [
                {
                    "plugType": "CCS2",
                    "powerRating": "DC",
                    "chargingSpeed": 50,
                    "price": 0.8,
                    "priceType": "kWh",
                    "evIds": [{"evCpId": "B-1", "status": None}],
                }
            ],
        },
    ],
}


def test_compact_ev_sites_keeps_plugs_without_status():
    out = compact_ev_sites({"value": {"evLocationsData": [LOCATION, {"address": "no coords"}]}})
    assert out == [
        {
            "id": "441065001",
            "n": "BLK 65A MARINE DRIVE MULTI STOREY CAR PARK",
            "a": "65A MARINE DRIVE SINGAPORE 441065",
            "pc": "441065",
            "la": 1.30215,
            "lo": 103.9101,
            "op": ["SP MOBILITY", "STRIDES YTL PTE. LTD."],
            "pl": [
                {"t": "CCS2", "c": "DC", "kw": 50.0, "p": 0.8, "pu": "kWh", "n": 1},
                {"t": "Type 2", "c": "AC", "kw": 7.4, "p": 0.698, "pu": "kWh", "n": 2},
            ],
        }
    ]
    # The batch file may come without the "value" wrapper.
    assert compact_ev_sites({"evLocationsData": [LOCATION]})[0]["pc"] == "441065"


def test_compact_ev_live_counts_free_chargers():
    out = compact_ev_live({"value": {"evLocationsData": [LOCATION]}})
    assert out[0]["id"] == "441065001"
    by_plug = {p["t"]: (p["a"], p["n"]) for p in out[0]["pl"]}
    assert by_plug == {"Type 2": (1, 2), "CCS2": (0, 1)}


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
def test_ev_endpoint_is_cached_per_postal_code(client):
    route = respx.get(f"{LTA}/EVChargingPoints").mock(
        return_value=httpx.Response(200, json={"value": {"evLocationsData": [LOCATION]}})
    )
    body = client.get("/v1/ev/441065").json()
    assert body["data"][0]["pl"][1]["a"] == 1
    assert body["fetched_at"] > 0
    client.get("/v1/ev/441065")
    assert route.call_count == 1  # second request served from memory
    assert route.calls[0].request.url.params["PostalCode"] == "441065"
    assert route.calls[0].request.headers["AccountKey"] == "test-key"


def test_ev_endpoint_validates_postal_code(client):
    assert client.get("/v1/ev/4410").status_code == 422
    assert client.get("/v1/ev/44106a").status_code == 422


@respx.mock
def test_ev_endpoint_upstream_error(client):
    respx.get(f"{LTA}/EVChargingPoints").mock(return_value=httpx.Response(500))
    assert client.get("/v1/ev/441065").status_code == 502


@respx.mock
async def test_ev_batch_follows_the_download_link():
    respx.get(f"{LTA}/EVCBatch").mock(
        return_value=httpx.Response(
            200, json={"value": [{"Link": "https://files.example/ev.json"}]}
        )
    )
    respx.get("https://files.example/ev.json").mock(
        return_value=httpx.Response(200, json={"evLocationsData": [LOCATION]})
    )
    async with httpx.AsyncClient() as http:
        body = await Sources(Settings(lta_account_key="k"), http).ev_batch()
    assert compact_ev_sites(body)[0]["n"].startswith("BLK 65A")


# Shapes seen from LTA on 29 Oct 2026 (they differ from the API guide and from each other).
REAL_BATCH = {
    "LastUpdatedTime": "2026-10-29 13:10:00",
    "evLocationsData": [
        {
            "address": "142A PASIR RIS STREET 11 SINGAPORE 511142",
            "name": "BLK 142A PASIR RIS STREET 11 MULTI STOREY CAR PARK",
            "longtitude": 103.959758,
            "latitude": 1.362839,
            "postalCode": "511142",
            "chargingPoints": [
                {
                    "status": "1",
                    "operatingHours": "",
                    "operator": "STRIDES YTL PTE. LTD.",
                    "position": "L3A 128",
                    "name": "BLK 142A PASIR RIS STREET 11 MULTI STOREY CAR PARK",
                    "plugTypes": [
                        {
                            "plugType": "Type 2",
                            "price": "0.6980",
                            "current": "AC",
                            "powerRating": "7.4",
                            "priceType": "kWh",
                            "evIds": [{"evCpId": "R122901R-001", "status": "1"}],
                        }
                    ],
                }
            ],
        }
    ],
}

REAL_LIVE = {
    "value": {
        "evLocationsData": [
            {
                "address": "65A MARINE DRIVE SINGAPORE 441065",
                "name": "BLK 65A MARINE DRIVE MULTI STOREY CAR PARK",
                "longitude": 103.909914,
                "latitude": 1.302967,
                "locationId": "909914441065",
                "status": "",
                "chargingPoints": [
                    {
                        "status": "1",
                        "operatingHours": "",
                        "operator": "STRIDES YTL PTE. LTD.",
                        "position": "L3 336",
                        "name": "BLK 65A MARINE DRIVE MULTI STOREY CAR PARK",
                        "id": "",
                        "plugTypes": [
                            {
                                "plugType": "Type 2",
                                "powerRating": "AC",
                                "chargingSpeed": "7.4",
                                "price": "0.6980",
                                "priceType": "kWh",
                                "evIds": [{"id": "", "evCpId": "R122996H-001", "status": ""}],
                            }
                        ],
                    },
                    {
                        "status": "100",
                        "operator": "STRIDES YTL PTE. LTD.",
                        "plugTypes": [
                            {
                                "plugType": "Type 2",
                                "powerRating": "AC",
                                "chargingSpeed": "7.4",
                                "price": "0.6980",
                                "priceType": "kWh",
                                "evIds": [{"evCpId": "R122996H-002", "status": ""}],
                            }
                        ],
                    },
                ],
            }
        ]
    }
}


def test_real_batch_file_is_read():
    [site] = compact_ev_sites(REAL_BATCH)
    assert site["pc"] == "511142"
    assert site["lo"] == 103.95976  # "longtitude" in the batch file
    assert site["id"] == ""  # the batch file has no locationId
    assert site["pl"] == [{"t": "Type 2", "c": "AC", "kw": 7.4, "p": 0.698, "pu": "kWh", "n": 1}]


def test_real_live_answer_uses_charger_status_when_connector_status_is_empty():
    [loc] = compact_ev_live(REAL_LIVE)
    assert loc["id"] == "909914441065"
    assert loc["n"] == "BLK 65A MARINE DRIVE MULTI STOREY CAR PARK"
    assert loc["pl"] == [
        {"t": "Type 2", "c": "AC", "kw": 7.4, "p": 0.698, "pu": "kWh", "n": 2, "a": 1}
    ]
