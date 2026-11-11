"""/v1/trip-extras: a short, filtered answer per travel mode from LTA DataMall."""

import logging

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app import trip_extras as tx
from app.config import get_settings
from app.main import app, redact_access_path

LTA = "https://datamall2.mytransport.sg/ltaodataservice"
KEY = "secret-account-key"
# Ang Mo Kio: the destination of the examples.
LAT, LNG = 1.3691, 103.8454


def lot(cp: str, where: str, lots: int, lot_type: str, agency: str = "HDB") -> dict:
    return {
        "CarParkID": cp,
        "Area": "",
        "Development": f"BLK {cp}",
        "Location": where,
        "AvailableLots": lots,
        "LotType": lot_type,
        "Agency": agency,
    }


PARKING = [
    lot("NEAR", "1.36920 103.84550", 40, "C"),
    lot("NEAR", "1.36920 103.84550", 6, "Y"),
    lot("MID", "1.37100 103.84700", 0, "C", "URA"),
    lot("EDGE", "1.37600 103.84540", 12, "C", "LTA"),  # about 770 m
    lot("FOURTH", "1.37700 103.84540", 99, "C"),  # about 880 m: inside, but only 3 are returned
    lot("FAR", "1.39000 103.84540", 500, "C"),  # about 2.3 km
    lot("HEAVY", "1.36915 103.84545", 9, "H"),
    {"CarParkID": "BROKEN", "Location": "", "AvailableLots": "x", "LotType": "C"},
]


def rack(name: str, lat: float, lng: float, count: int = 10, shelter: str = "Y") -> dict:
    return {
        "Description": name,
        "Latitude": lat,
        "Longitude": lng,
        "RackType": "Yellow Box",
        "RackCount": count,
        "ShelterIndicator": shelter,
    }


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("LTA_ACCOUNT_KEY", KEY)
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    get_settings.cache_clear()


def get(client, mode: str, lat: float = LAT, lng: float = LNG):
    return client.get("/v1/trip-extras", params={"mode": mode, "lat": lat, "lng": lng})


@respx.mock
def test_car_nearest_three_within_the_radius_with_car_lots_only(client):
    route = respx.get(f"{LTA}/CarParkAvailabilityv2").mock(
        return_value=httpx.Response(200, json={"value": PARKING})
    )
    r = get(client, "car")
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body["fetched_at"], int)
    data = body["data"]
    assert data["mode"] == "car" and data["radius"] == 1000
    assert [i["id"] for i in data["items"]] == ["NEAR", "MID", "EDGE"]
    first = data["items"][0]
    assert first == {
        "id": "NEAR",
        "name": "BLK NEAR",
        "agency": "HDB",
        "lots": 40,
        "m": first["m"],
        "la": 1.3692,
        "lo": 103.8455,
    }
    assert 0 < first["m"] < 50
    assert [i["m"] for i in data["items"]] == sorted(i["m"] for i in data["items"])
    assert data["items"][1]["lots"] == 0 and data["items"][1]["agency"] == "URA"
    # Never the dataset: the far and the fourth car park are not in the answer.
    assert "FAR" not in r.text and "FOURTH" not in r.text and "HEAVY" not in r.text

    # Motorcycle lots come from the same cached dataset: no second call to LTA.
    m = get(client, "motorcycle").json()["data"]
    assert [(i["id"], i["lots"]) for i in m["items"]] == [("NEAR", 6)]
    assert route.call_count == 1


@respx.mock
def test_motorcycle_with_no_lots_nearby_is_an_empty_list(client):
    respx.get(f"{LTA}/CarParkAvailabilityv2").mock(
        return_value=httpx.Response(200, json={"value": [lot("A", "1.3692 103.8455", 5, "C")]})
    )
    r = get(client, "motorcycle")
    assert r.status_code == 200
    assert r.json()["data"]["items"] == []


@respx.mock
def test_parking_pages_until_a_short_page(client):
    full = [lot(f"P{i}", "1.39000 103.84540", 1, "C") for i in range(500)]
    pages = {"0": full, "500": [lot("LAST", "1.36920 103.84550", 7, "C")]}

    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"value": pages[request.url.params.get("$skip", "0")]})

    route = respx.get(f"{LTA}/CarParkAvailabilityv2").mock(side_effect=answer)
    items = get(client, "car").json()["data"]["items"]
    assert [i["id"] for i in items] == ["LAST"]
    assert route.call_count == 2


@respx.mock
def test_taxi_counts_free_taxis_within_500_m(client):
    taxis = [
        {"Latitude": 1.3692, "Longitude": 103.8455},
        {"Latitude": 1.3720, "Longitude": 103.8454},  # about 320 m
        {"Latitude": 1.3745, "Longitude": 103.8454},  # about 600 m
        {"Latitude": "x", "Longitude": None},
    ]
    route = respx.get(f"{LTA}/Taxi-Availability").mock(
        return_value=httpx.Response(200, json={"value": taxis})
    )
    r = get(client, "taxi")
    assert r.status_code == 200, r.text
    assert r.json()["data"] == {"mode": "taxi", "radius": 500, "count": 2}
    get(client, "taxi", 1.30, 103.80)
    assert route.call_count == 1  # shared across users and places


@respx.mock
def test_bicycle_asks_lta_per_area_once_and_filters_per_point(client):
    racks = [
        rack("AMK HUB", 1.3693, 103.8456, 24, "Y"),
        rack("BLK 208", 1.3712, 103.8454, 10, "N"),  # about 230 m
        rack("PARK", 1.3660, 103.8454, 6, "N"),  # about 345 m
        rack("FOURTH", 1.3731, 103.8454, 8, "Y"),  # about 445 m: inside, but only 3 are returned
        rack("OUTSIDE", 1.3760, 103.8454),  # about 770 m
        {"Description": "NO POINT", "RackCount": 3},
    ]
    route = respx.get(f"{LTA}/BicycleParkingv2").mock(
        return_value=httpx.Response(200, json={"value": racks})
    )
    r = get(client, "bicycle")
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    assert data["mode"] == "bicycle" and data["radius"] == 500
    assert [i["name"] for i in data["items"]] == ["AMK HUB", "BLK 208", "PARK"]
    first = data["items"][0]
    assert first["type"] == "Yellow Box" and first["racks"] == 24 and first["sheltered"] is True
    assert data["items"][1]["sheltered"] is False
    assert 0 < first["m"] < 60

    # LTA was asked for the area (a 0.01 degree cell), not the user's point.
    sent = route.calls.last.request.url.params
    assert (sent["Lat"], sent["Long"], sent["Dist"]) == ("1.37", "103.85", "1.4")
    assert sent["$skip"] == "0"

    # Another point in the same area: answered from memory, filtered for that point.
    again = get(client, "bicycle", 1.3729, 103.8455).json()["data"]
    assert again["items"][0]["name"] == "FOURTH"
    assert route.call_count == 1
    # A point in another area asks LTA again.
    get(client, "bicycle", 1.3000, 103.8000)
    assert route.call_count == 2


def test_the_area_radius_covers_every_point_of_the_cell():
    # The far corner of a cell is half a diagonal from its centre; the radius asked from LTA
    # must still reach BICYCLE_RADIUS_M beyond it.
    centre = tx.area(1.3749, 103.8549)
    assert centre == (1.37, 103.85)
    corner = tx.metres(*centre, centre[0] + tx.BICYCLE_GRID / 2, centre[1] + tx.BICYCLE_GRID / 2)
    assert corner + tx.BICYCLE_RADIUS_M <= tx.BICYCLE_DIST_KM * 1000


@pytest.mark.parametrize("mode", ["bicycle", "car", "taxi"])
@respx.mock
def test_lta_down_is_a_502_without_the_key(client, mode, caplog):
    respx.get(url__startswith=LTA).mock(return_value=httpx.Response(500, text="boom"))
    with caplog.at_level(logging.DEBUG):
        r = get(client, mode)
    assert r.status_code == 502
    assert KEY not in r.text
    assert KEY not in caplog.text
    # The server's own log lines (the test client logs its request to "testserver" itself).
    server = "\n".join(r.getMessage() for r in caplog.records if "testserver" not in r.getMessage())
    assert str(LAT) not in server and str(LNG) not in server
    assert "Lat=1" not in server and "Long=1" not in server
    if mode == "bicycle":
        assert "Lat=***" in server and "Long=***" in server


@pytest.mark.parametrize(
    "answer",
    [
        httpx.Response(200, text="<html>maintenance</html>"),
        httpx.Response(200, json={"value": None}),
        httpx.Response(200, json={"fault": "quota"}),
        httpx.Response(200, json={"value": "none"}),
        httpx.Response(200, json=["x"]),
    ],
)
@respx.mock
def test_a_bicycle_answer_that_is_not_the_documented_list_is_a_502(client, answer):
    respx.get(f"{LTA}/BicycleParkingv2").mock(return_value=answer)
    r = get(client, "bicycle")
    assert r.status_code == 502
    assert "maintenance" not in r.text
    # Not kept: the next request asks LTA again instead of answering "none here" for a day.
    respx.get(f"{LTA}/BicycleParkingv2").mock(
        return_value=httpx.Response(200, json={"value": [rack("AMK HUB", 1.3693, 103.8456)]})
    )
    assert get(client, "bicycle").json()["data"]["items"][0]["name"] == "AMK HUB"


def test_a_malformed_row_in_the_parking_dataset_is_skipped():
    rows = [
        ["A", "HDB", 1.3692, 103.8455, "C", "n/a", "BLK A"],
        ["B", "HDB", 1.3692, 103.8455, "C", 3, "BLK B"],
    ]
    assert [i["id"] for i in tx.nearest_parking(rows, LAT, LNG, "C")] == ["B"]


@respx.mock
def test_lta_empty_is_an_empty_answer_not_an_error(client):
    respx.get(url__startswith=LTA).mock(return_value=httpx.Response(200, json={"value": []}))
    assert get(client, "bicycle").json()["data"]["items"] == []
    assert get(client, "car").json()["data"]["items"] == []
    assert get(client, "taxi").json()["data"]["count"] == 0


def test_bad_input_is_refused_before_any_upstream_call(client):
    assert get(client, "walk").status_code == 422
    assert get(client, "car", 51.5, -0.12).status_code == 422  # not in Singapore
    assert (
        client.get("/v1/trip-extras", params={"mode": "car", "lat": "nan", "lng": LNG}).status_code
        == 422
    )
    assert client.get("/v1/trip-extras", params={"mode": "car"}).status_code == 422


def test_without_the_lta_key_the_answer_is_503(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.delenv("LTA_ACCOUNT_KEY", raising=False)
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        assert get(c, "bicycle").status_code == 503
    get_settings.cache_clear()


@respx.mock
def test_new_bicycle_areas_are_rate_limited(client, monkeypatch):
    respx.get(f"{LTA}/BicycleParkingv2").mock(return_value=httpx.Response(200, json={"value": []}))
    per_second = get_settings().bicycle_per_second
    codes = [
        get(client, "bicycle", 1.20 + i * 0.02, 103.80).status_code for i in range(per_second + 2)
    ]
    assert codes[:per_second] == [200] * per_second
    assert 503 in codes[per_second:]


def test_the_point_is_rounded_and_never_in_the_access_log():
    assert tx.point(1.36912345, 103.84541234) == (1.3691, 103.8454)
    assert tx.point(float("inf"), 103.8) is None
    logged = redact_access_path("/v1/trip-extras?mode=car&lat=1.3691&lng=103.8454")
    assert logged == "/v1/trip-extras"
