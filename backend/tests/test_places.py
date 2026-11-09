"""Place name search for Plan a trip: /v1/places on Geoapify Autocomplete (docs/PLACE_SEARCH.md)."""

import logging

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import get_settings
from app.geoapify import AUTOCOMPLETE_URL, Geoapify, GeoapifyError, compact_places
from app.main import app

KEY = "geo-secret-123"

RESULTS = {
    "results": [
        {
            "name": "Putra Minang",
            "address_line1": "Putra Minang",
            "address_line2": "51 Bencoolen Street, Singapore 189630, Singapore",
            "postcode": "189630",
            "lat": 1.29942,
            "lon": 103.85051,
            "result_type": "amenity",
            "place_id": "abc",
        },
        {
            # No name: address_line1 is used.
            "address_line1": "Jewel Changi Airport",
            "address_line2": "78 Airport Boulevard, Singapore 819666, Singapore",
            "lat": 1.3604,
            "lon": 103.9897,
            "result_type": "building",
        },
        {"name": "Nowhere", "result_type": "amenity"},  # no coordinates: dropped
    ],
    "query": {"text": "putra minang"},
}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("GEOAPIFY_API_KEY", KEY)
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    get_settings.cache_clear()


def test_compact_places_keeps_what_the_app_reads():
    out = compact_places(RESULTS)
    assert out == [
        {
            "name": "Putra Minang",
            "address": "51 Bencoolen Street, Singapore 189630, Singapore",
            "postal": "189630",
            "lat": 1.29942,
            "lng": 103.85051,
            "type": "amenity",
        },
        {
            "name": "Jewel Changi Airport",
            "address": "78 Airport Boulevard, Singapore 819666, Singapore",
            "postal": "",
            "lat": 1.3604,
            "lng": 103.9897,
            "type": "building",
        },
    ]


def test_compact_places_survives_odd_bodies():
    assert compact_places({}) == []
    assert compact_places({"results": "x"}) == []
    assert compact_places({"results": [None, {"lat": "1.3", "lon": 103.8}]}) == []


@respx.mock
async def test_client_sends_singapore_filter_and_key():
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=httpx.Response(200, json=RESULTS))
    async with httpx.AsyncClient() as http:
        out = await Geoapify(http, KEY).autocomplete("putra minang")
    assert [p["name"] for p in out] == ["Putra Minang", "Jewel Changi Airport"]
    params = route.calls[0].request.url.params
    assert params["text"] == "putra minang"
    assert params["filter"] == "countrycode:sg"
    assert params["limit"] == "6"
    assert params["lang"] == "en"
    assert params["format"] == "json"
    assert params["apiKey"] == KEY
    assert "bias" not in params  # the user's location is never sent


@pytest.mark.parametrize(
    "answer",
    [
        httpx.Response(429, json={"message": f"limit for {KEY}"}),
        httpx.Response(500, text="oops"),
        httpx.Response(200, text="not json"),
        httpx.TimeoutException("slow"),
        httpx.ConnectError("down"),
    ],
)
@respx.mock
async def test_client_errors_never_carry_the_key(answer):
    route = respx.get(AUTOCOMPLETE_URL)
    if isinstance(answer, Exception):
        route.mock(side_effect=answer)
    else:
        route.mock(return_value=answer)
    async with httpx.AsyncClient() as http:
        with pytest.raises(GeoapifyError) as err:
            await Geoapify(http, KEY).autocomplete("jewel")
    assert KEY not in str(err.value)
    assert err.value.__cause__ is None
    assert err.value.__suppress_context__


@respx.mock
def test_places_endpoint_answers_and_caches(client):
    route = respx.get(AUTOCOMPLETE_URL).mock(return_value=httpx.Response(200, json=RESULTS))
    r = client.get("/v1/places", params={"q": "  Putra   Minang "})
    assert r.status_code == 200
    body = r.json()
    assert isinstance(body["fetched_at"], int)
    assert [p["name"] for p in body["data"]] == ["Putra Minang", "Jewel Changi Airport"]
    assert route.calls[0].request.url.params["text"] == "Putra Minang"
    assert KEY not in r.text
    assert "query" not in body["data"]  # the raw body is never passed on

    assert client.get("/v1/places", params={"q": "putra minang"}).status_code == 200
    assert route.call_count == 1  # served from memory, same key whatever the case


@pytest.mark.parametrize("q", ["x", " a ", "y" * 81])
@respx.mock
def test_places_rejects_bad_length(client, q):
    route = respx.get(AUTOCOMPLETE_URL)
    assert client.get("/v1/places", params={"q": q}).status_code == 422
    assert not route.called


@pytest.mark.parametrize("status", [401, 429, 500])
@respx.mock
def test_places_upstream_error_is_502_without_the_key(client, status, caplog):
    respx.get(AUTOCOMPLETE_URL).mock(return_value=httpx.Response(status, text=f"bad key {KEY}"))
    with caplog.at_level(logging.DEBUG):
        r = client.get("/v1/places", params={"q": "jewel changi"})
    assert r.status_code == 502
    assert r.json() == {"detail": "upstream Geoapify error"}
    assert KEY not in caplog.text
    # The query is not logged (the test client's own request line aside).
    ours = [m for m in caplog.messages if "testserver" not in m]
    assert ours and not any("jewel" in m.lower() for m in ours)


@respx.mock
def test_places_timeout_is_502(client):
    respx.get(AUTOCOMPLETE_URL).mock(side_effect=httpx.ReadTimeout("slow"))
    r = client.get("/v1/places", params={"q": "jewel"})
    assert r.status_code == 502
    assert KEY not in r.text


@respx.mock
def test_places_errors_are_not_cached(client):
    respx.get(AUTOCOMPLETE_URL).mock(
        side_effect=[httpx.Response(500), httpx.Response(200, json=RESULTS)]
    )
    assert client.get("/v1/places", params={"q": "jewel"}).status_code == 502
    assert client.get("/v1/places", params={"q": "jewel"}).status_code == 200


@respx.mock
def test_places_without_key_is_503(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.delenv("GEOAPIFY_API_KEY", raising=False)
    monkeypatch.setenv("GEOAPIFY_API_KEY", "")
    get_settings.cache_clear()
    route = respx.get(AUTOCOMPLETE_URL)
    with TestClient(app) as c:
        r = c.get("/v1/places", params={"q": "jewel"})
    get_settings.cache_clear()
    assert r.status_code == 503
    assert r.json() == {"detail": "place search not configured"}
    assert not route.called


@respx.mock
def test_httpx_request_log_hides_the_key(client, caplog):
    respx.get(AUTOCOMPLETE_URL).mock(return_value=httpx.Response(200, json=RESULTS))
    with caplog.at_level(logging.DEBUG, logger="httpx"):
        client.get("/v1/places", params={"q": "jewel"})
    line = next(m for m in caplog.messages if "api.geoapify.com" in m)
    assert "apiKey=***" in line and "text=***" in line
    assert KEY not in caplog.text
