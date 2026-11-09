"""Contract between the backend and the app (docs/QA.md, "Contract tests").

Each file in contracts/v1 holds a request, the upstream answer it is built from, and the
response the app reads. The same files feed app/test/contract_test.dart, so the server and the
app parsers are checked against one example.

Here the upstream is mocked with the file's "upstream", the endpoint is called, and the
response must have the structure of the file's "response": every key and type in the file
must be there (values may differ, extra keys are allowed). After a deliberate change of a
response, rewrite the examples with: UPDATE_CONTRACTS=1 pytest tests/test_contracts.py
"""

import json
import os
from pathlib import Path

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts" / "v1"
DATAGOV = "https://api-open.data.gov.sg/v2/real-time/api"
LTA = "https://datamall2.mytransport.sg/ltaodataservice"
ONEMAP_TOKEN = "https://www.onemap.gov.sg/api/auth/post/getToken"
ONEMAP_SEARCH = "https://www.onemap.gov.sg/api/common/elastic/search"
FETCHED_AT = 1793850000  # fixed in the examples so an update only shows real changes

# Upstream URL (and query) each example is fetched from.
UPSTREAM = {
    "weather_forecast": (f"{DATAGOV}/two-hr-forecast", None),
    "weather_rainfall": (f"{DATAGOV}/rainfall", None),
    "weather_psi": (f"{DATAGOV}/psi", None),
    "weather_pm25": (f"{DATAGOV}/pm25", None),
    "weather_uv": (f"{DATAGOV}/uv", None),
    "weather_wbgt": (f"{DATAGOV}/weather", {"api": "wbgt"}),
    "weather_lightning": (f"{DATAGOV}/weather", {"api": "lightning"}),
    "train_alerts": (f"{LTA}/TrainServiceAlerts", None),
    "bus_arrival": (f"{LTA}/v3/BusArrival", None),
    "ev": (f"{LTA}/EVChargingPoints", None),
    "crowd": (f"{LTA}/PCDRealTime", None),
    "carpark": ("https://api.data.gov.sg/v1/transport/carpark-availability", None),
    "taxi": (f"{LTA}/Taxi-Availability", None),
    "parking": (f"{LTA}/CarParkAvailabilityv2", None),
    "traffic_incidents": (f"{LTA}/TrafficIncidents", None),
    "search": (ONEMAP_SEARCH, None),
    "places": ("https://api.geoapify.com/v1/geocode/autocomplete", None),
    "agent": ("https://data.gov.sg/api/action/datastore_search", None),
}
NAMES = sorted(p.stem for p in CONTRACTS.glob("*.json"))


def shape(v: object) -> object:
    """Structure of a JSON value: dict keys, list items and value types, not the values."""
    if isinstance(v, dict):
        return {k: shape(x) for k, x in v.items()}
    if isinstance(v, list):
        items = [shape(x) for x in v]
        # A list of alike items (records) has one item shape; mixed items are a fixed row.
        if all(i == items[0] for i in items[1:]):
            return [items[0]] if items else []
        return ("row", items)
    if v is None:
        return None
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, int | float):
        return "number"
    return type(v).__name__


def mismatches(want: object, got: object, path: str = "$") -> list[str]:
    """Where [got] lacks the structure of [want]. None in [want] accepts anything."""
    if want is None:
        return []
    if isinstance(want, dict):
        if not isinstance(got, dict):
            return [f"{path}: want an object, got {got!r}"]
        out = []
        for k, w in want.items():
            if k not in got:
                out.append(f"{path}.{k}: missing")
            else:
                out += mismatches(w, got[k], f"{path}.{k}")
        return out
    if isinstance(want, tuple):  # fixed row: same position, same type
        if not (isinstance(got, tuple) and len(got[1]) >= len(want[1])):
            return [f"{path}: want a row of {len(want[1])}, got {got!r}"]
        out = []
        for i, w in enumerate(want[1]):
            out += mismatches(w, got[1][i], f"{path}[{i}]")
        return out
    if isinstance(want, list):
        if isinstance(got, tuple):  # mixed records: each must still match
            return [m for g in got[1] for m in mismatches(want[0], g, f"{path}[]")] if want else []
        if not isinstance(got, list):
            return [f"{path}: want a list, got {got!r}"]
        if not want or not got:
            return [] if not want else [f"{path}: empty, the example has items"]
        return mismatches(want[0], got[0], f"{path}[]")
    if want != got:
        return [f"{path}: want {want}, got {got}"]
    return []


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    monkeypatch.setenv("ONEMAP_EMAIL", "dev@example.com")
    monkeypatch.setenv("ONEMAP_PASSWORD", "x")
    monkeypatch.setenv("GEOAPIFY_API_KEY", "test-key")
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    with TestClient(app) as c:
        yield c
    get_settings.cache_clear()


def test_every_example_has_an_upstream():
    assert NAMES, f"no examples in {CONTRACTS}"
    assert set(NAMES) == set(UPSTREAM)


def test_shape_compares_structure_not_values():
    assert mismatches(shape({"a": [1, 2]}), shape({"a": [3], "b": "new"})) == []
    assert mismatches(shape({"a": "x"}), shape({})) == ["$.a: missing"]
    assert mismatches(shape([["x", 1.5]]), shape([["y", 2]])) == []
    assert mismatches(shape([["x", 1.5]]), shape([["y", "2"]])) != []


@pytest.mark.parametrize("name", NAMES)
@respx.mock
def test_response_matches_example(client, name):
    path = CONTRACTS / f"{name}.json"
    example = json.loads(path.read_text())
    url, params = UPSTREAM[name]
    token = {"access_token": "T", "expiry_timestamp": "9999999999"}
    respx.post(ONEMAP_TOKEN).mock(return_value=httpx.Response(200, json=token))
    route = respx.get(url, params=params) if params else respx.get(url)
    route.mock(return_value=httpx.Response(200, json=example["upstream"]))

    r = client.get(example["request"])
    assert r.status_code == 200, r.text
    got = r.json()
    assert route.called

    if os.environ.get("UPDATE_CONTRACTS"):
        example["response"] = {**got, "fetched_at": FETCHED_AT}
        path.write_text(json.dumps(example, indent=2, ensure_ascii=False) + "\n")
        return
    assert example["response"] is not None, f"run UPDATE_CONTRACTS=1 pytest for {name}"
    problems = mismatches(shape(example["response"]), shape(got))
    head = f"{name}: response no longer matches contracts/v1/{name}.json"
    assert not problems, "\n".join([head, *problems])
