import hashlib
import json
from datetime import UTC, date, datetime

import httpx
import pytest
import respx

from app import build_static
from app import where_to_live as w
from app.bundles import DataGov
from app.config import get_settings
from app.onemap import OneMap


async def no_sleep(_s: float) -> None:
    return None


def rows(*items: tuple[str, str, str, object]) -> list[dict]:
    return [
        {"_id": i, "quarter": q, "town": t, "flat_type": f, "median_rent": v}
        for i, (q, t, f, v) in enumerate(items)
    ]


# ---------------------------------------------------------------- parsing


def test_normalisers():
    assert w.norm_flat("3-RM") == "3-ROOM"
    assert w.norm_flat("4 ROOM") == "4-ROOM"
    assert w.norm_flat("5-room") == "5-ROOM"
    assert w.norm_flat("EXEC") == "EXECUTIVE"
    assert w.norm_flat("MULTI-GENERATION") is None
    assert w.norm_quarter("2026-Q3") == "2026-Q3"
    assert w.norm_quarter("2026 Q3") == "2026-Q3"
    assert w.norm_quarter("Q1 2025") == "2025-Q1"
    assert w.norm_quarter("2026-13") is None
    assert w.town_key("Kallang/Whampoa") == "KALLANGWHAMPOA"
    assert w.town_key("CENTRAL") == w.town_key("Central Area")


@pytest.mark.parametrize("raw", ["na", "NA", "-", "", None, "0", "n.a."])
def test_parse_price_not_enough_data(raw):
    assert w.parse_price(raw) is None


def test_parse_price_numbers():
    assert w.parse_price("2,850") == 2850
    assert w.parse_price("$610000") == 610000
    assert w.parse_price(3200.4) == 3200


def test_parse_medians_takes_latest_quarter_with_a_number():
    latest, towns, notes = w.parse_medians(
        rows(
            ("2026-Q2", "PUNGGOL", "4-RM", "3200"),
            ("2026-Q3", "PUNGGOL", "4-RM", "3300"),
            ("2026-Q3", "PUNGGOL", "3-RM", "na"),
            ("2026-Q2", "PUNGGOL", "3-RM", "2800"),
        )
    )
    assert latest == "2026-Q3"
    assert towns["PUNGGOL"]["4-ROOM"] == {"median": 3300, "quarter": "2026-Q3"}
    # 'na' in the latest quarter: the older number is shown with its own quarter.
    assert towns["PUNGGOL"]["3-ROOM"] == {"median": 2800, "quarter": "2026-Q2"}
    assert notes["fields"] == {
        "quarter": "quarter",
        "town": "town",
        "flat": "flat_type",
        "value": "median_rent",
    }


def test_parse_medians_missing_and_old_quarters_are_not_enough_data():
    _, towns, _ = w.parse_medians(
        rows(
            ("2026-Q3", "BISHAN", "4-RM", "3700"),
            ("2026-Q3", "BISHAN", "2-RM", "na"),
            ("2025-Q2", "BISHAN", "5-RM", "4000"),  # 5 quarters back: too old
            ("2026-Q3", "SENGKANG", "2-RM", "2300"),
        )
    )
    assert towns["BISHAN"]["2-ROOM"] is None
    assert towns["BISHAN"]["5-ROOM"] is None
    # A flat type the town never had still appears, as "not enough data".
    assert towns["SENGKANG"]["4-ROOM"] is None
    assert list(towns["SENGKANG"]) == ["2-ROOM", "4-ROOM", "5-ROOM"]


def test_parse_medians_other_column_names():
    data = [
        {"_id": 1, "quarter": "2026-Q3", "town": "YISHUN", "flat_type": "4-ROOM", "price": "560000"}
    ]
    latest, towns, notes = w.parse_medians(data)
    assert towns["YISHUN"]["4-ROOM"]["median"] == 560000
    assert notes["fields"]["value"] == "price"


def test_parse_medians_unknown_columns_fail():
    with pytest.raises(w.BuildError):
        w.parse_medians([{"_id": 1, "period": "2026-Q3", "area": "X", "kind": "4-RM", "v": 1}])
    with pytest.raises(w.BuildError):
        w.parse_medians([])


# ---------------------------------------------------------------- routes


ROUTE_BODY = {
    "requestParameters": {},
    "plan": {
        "itineraries": [
            {"duration": 3180, "transfers": 1, "legs": [{"mode": "BUS", "transitLeg": True}]},
            {
                "duration": 2700,
                "fare": "1.94",
                "legs": [
                    {"mode": "WALK", "transitLeg": False},
                    {"mode": "SUBWAY", "transitLeg": True},
                    {"mode": "SUBWAY", "transitLeg": True},
                ],
            },
        ]
    },
}


def test_parse_route_fastest_itinerary_and_counted_transfers():
    assert w.parse_route(ROUTE_BODY) == {"min": 45, "transfers": 1, "fare": 194}
    assert w.parse_route({"plan": {"itineraries": []}}) is None
    assert w.parse_route({"error": "x"}) is None
    assert w.parse_route([]) is None


def test_route_sample_is_short():
    s = w.route_sample(ROUTE_BODY)
    assert s["itineraries"] == 2
    assert s["first"] == {"duration": 3180, "transfers": 1}
    assert s["first_legs"][0]["mode"] == "BUS"


def test_depart_day_skips_weekend_and_holidays():
    # Sat 7 Nov 2026 -> Mon 9 Nov is Deepavali (observed) -> Tue 10 Nov.
    assert w.depart_day(date(2026, 11, 7), {"2026-11-09"}) == date(2026, 11, 10)
    assert w.depart_day(date(2026, 11, 10), set()) == date(2026, 11, 11)


def onemap(handler) -> tuple[OneMap, httpx.AsyncClient]:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OneMap(client, None, None), client


async def test_fetch_route_retries_then_succeeds():
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        if len(calls) < 3:
            return httpx.Response(503 if len(calls) == 1 else 429)
        return httpx.Response(200, json=ROUTE_BODY)

    om, client = onemap(handler)
    route, body = await w.fetch_route(
        om, (1.4, 103.9), (1.28, 103.85), date(2026, 11, 10), sleep=no_sleep
    )
    await client.aclose()
    assert route == {"min": 45, "transfers": 1, "fare": 194}
    assert len(calls) == 3
    p = calls[-1].url.params
    assert (p["routeType"], p["mode"], p["time"], p["date"]) == (
        "pt",
        "TRANSIT",
        "08:30:00",
        "11-10-2026",
    )


async def test_fetch_route_gives_up():
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        raise httpx.ConnectError("down")

    om, client = onemap(handler)
    assert await w.fetch_route(om, (1, 2), (3, 4), date(2026, 11, 10), sleep=no_sleep) == (
        None,
        None,
    )
    await client.aclose()
    assert len(calls) == 3


async def test_fetch_route_does_not_retry_a_bad_request():
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        return httpx.Response(400, json={"error": "bad"})

    om, client = onemap(handler)
    assert await w.fetch_route(om, (1, 2), (3, 4), date(2026, 11, 10), sleep=no_sleep) == (
        None,
        None,
    )
    await client.aclose()
    assert len(calls) == 1


TOWNS = [
    {
        "id": "punggol",
        "town": "PUNGGOL",
        "name": "Punggol",
        "station": "Punggol",
        "lat": 1.4,
        "lng": 103.9,
    },
    {
        "id": "bishan",
        "town": "BISHAN",
        "name": "Bishan",
        "station": "Bishan",
        "lat": 1.35,
        "lng": 103.85,
    },
]
AREAS = [{"id": "cbd", "name": "CBD", "station": "Raffles Place", "lat": 1.28, "lng": 103.85}]


async def test_build_routes_uses_fresh_cache_refetches_old_and_keeps_old_on_failure():
    today = date(2026, 11, 7)
    cache = {
        # fresh: not asked again
        "punggol|cbd": {
            "from": [1.4, 103.9],
            "to": [1.28, 103.85],
            "min": 50,
            "transfers": 1,
            "fare": 211,
            "at": "2026-11-01",
        },
        # 60 days old: asked again, OneMap fails, the old value stays
        "bishan|cbd": {
            "from": [1.35, 103.85],
            "to": [1.28, 103.85],
            "min": 25,
            "transfers": 0,
            "fare": None,
            "at": "2026-09-08",
        },
    }
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        return httpx.Response(500)

    om, client = onemap(handler)
    out, new_cache, notes = await w.build_routes(
        om, TOWNS, AREAS, cache, today, set(), sleep=no_sleep
    )
    await client.aclose()
    assert out == {
        "punggol": {"cbd": {"min": 50, "transfers": 1, "fare": 211}},
        "bishan": {"cbd": {"min": 25, "transfers": 0, "fare": None}},
    }
    assert new_cache == cache
    assert (notes["cached"], notes["failed_used_old"], notes["failed"]) == (1, 1, 0)
    assert len(calls) == 3  # one pair, three attempts


async def test_build_routes_moved_point_is_not_taken_from_cache():
    today = date(2026, 11, 7)
    cache = {
        "punggol|cbd": {
            "from": [1.0, 103.0],
            "to": [1.28, 103.85],
            "min": 99,
            "transfers": 3,
            "at": "2026-11-06",
        }
    }

    def handler(req: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=ROUTE_BODY)

    om, client = onemap(handler)
    out, new_cache, notes = await w.build_routes(
        om, TOWNS[:1], AREAS, cache, today, set(), sleep=no_sleep
    )
    await client.aclose()
    assert out["punggol"]["cbd"] == {"min": 45, "transfers": 1, "fare": 194}
    assert new_cache["punggol|cbd"]["at"] == "2026-11-07"
    assert notes["fetched"] == 1
    assert notes["sample"]["pair"] == "punggol|cbd"


async def test_build_routes_no_data_at_all_is_none():
    om, client = onemap(lambda req: httpx.Response(401))
    out, new_cache, notes = await w.build_routes(
        om, TOWNS[:1], AREAS, {}, date(2026, 11, 7), set(), sleep=no_sleep
    )
    await client.aclose()
    assert out == {"punggol": {"cbd": None}}
    assert new_cache == {}
    assert notes["failed"] == 1


# ---------------------------------------------------------------- assemble and publish


def priced(n: int) -> dict:
    return {f"T{i}": {"4-ROOM": {"median": 3000 + i, "quarter": "2026-Q3"}} for i in range(n)}


def points(n: int) -> dict:
    return {
        "towns": [
            {
                "id": f"t{i}",
                "town": f"T{i}",
                "name": f"T{i}",
                "station": "S",
                "lat": 1.3,
                "lng": 103.8,
            }
            for i in range(n)
        ],
        "areas": AREAS,
    }


def test_assemble_shape():
    commute = {f"t{i}": {"cbd": {"min": 30, "transfers": 1}} for i in range(22)}
    data = w.assemble(points(22), ("2026-Q3", priced(22)), ("2026-Q2", {}), commute)
    assert data["rent_quarter"] == "2026-Q3"
    assert data["resale_quarter"] == "2026-Q2"
    t = data["towns"][0]
    assert set(t) == {"id", "name", "station", "lat", "lng", "rent", "resale", "commute"}
    assert t["rent"]["4-ROOM"]["median"] == 3000
    assert t["resale"] == {}
    assert t["commute"]["cbd"] == {"min": 30, "transfers": 1}
    assert "data.gov.sg" in data["attribution"] and "OneMap" in data["attribution"]


def test_assemble_refuses_broken_data():
    commute = {f"t{i}": {"cbd": {"min": 30, "transfers": 1}} for i in range(22)}
    with pytest.raises(w.BuildError, match="prices"):
        w.assemble(points(22), ("2026-Q3", priced(5)), ("2026-Q3", {}), commute)
    half = {f"t{i}": {"cbd": None if i % 2 else {"min": 30, "transfers": 1}} for i in range(22)}
    with pytest.raises(w.BuildError, match="commutes"):
        w.assemble(points(22), ("2026-Q3", priced(22)), ("2026-Q3", {}), half)


def test_publish_ignores_generated_at(tmp_path):
    path = tmp_path / w.OUT_NAME
    data = {"rent_quarter": "2026-Q3", "towns": []}
    assert w.publish(path, data, datetime(2026, 11, 9, 1, 0, tzinfo=UTC))
    first = path.read_bytes()
    assert json.loads(first)["generated_at"] == "2026-11-09T01:00:00Z"
    # Same data a week later: the file (and its generated_at) stay as they were.
    assert not w.publish(path, dict(data), datetime(2026, 11, 16, 1, 0, tzinfo=UTC))
    assert path.read_bytes() == first
    # Changed data: rewritten with a new stamp.
    assert w.publish(
        path, {**data, "rent_quarter": "2026-Q4"}, datetime(2026, 11, 16, 1, 0, tzinfo=UTC)
    )
    assert json.loads(path.read_bytes())["generated_at"] == "2026-11-16T01:00:00Z"


def test_save_cache_only_when_changed(tmp_path):
    path = tmp_path / "routes.json"
    assert w.save_cache(path, {"a|b": {"min": 1}})
    assert not w.save_cache(path, {"a|b": {"min": 1}})
    assert w.save_cache(path, {"a|b": {"min": 2}})


def test_points_file_matches_mrt_stations():
    pts = json.loads(w.POINTS_FILE.read_text())
    stations = json.loads(
        (w.DATA_DIR.parent.parent / "web" / "data" / "mrt_stations.json").read_text()
    )
    by_name = {s["n"]: (s["la"], s["lo"]) for s in stations}
    assert len(pts["towns"]) == 26 and len(pts["areas"]) == 6
    for p in pts["towns"] + pts["areas"]:
        assert by_name[p["station"]] == (p["lat"], p["lng"]), p["id"]
    assert len({p["id"] for p in pts["towns"]}) == 26


async def test_build_end_to_end(tmp_path, monkeypatch):
    monkeypatch.setattr(w, "MIN_TOWNS_WITH_PRICES", 1)
    pts = json.loads(w.POINTS_FILE.read_text())
    rent_rows = rows(*[("2026-Q3", t["town"], "4-RM", "3000") for t in pts["towns"]])
    resale_rows = [
        {
            "_id": 1,
            "quarter": "2026-Q2",
            "town": "PUNGGOL",
            "flat_type": "4-ROOM",
            "price": "610000",
        }
    ]

    def handler(req: httpx.Request) -> httpx.Response:
        if "datastore_search" in str(req.url):
            rid = req.url.params["resource_id"]
            records = rent_rows if rid == w.RENT_MEDIANS else resale_rows
            return httpx.Response(200, json={"result": {"records": records}})
        return httpx.Response(200, json=ROUTE_BODY)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    dg = DataGov(client, None, pause=0)
    om = OneMap(client, None, None)
    data, cache, report = await w.build(dg, om, date(2026, 11, 7), tmp_path, {}, sleep=no_sleep)
    await client.aclose()
    assert len(data["towns"]) == 26
    punggol = next(t for t in data["towns"] if t["id"] == "punggol")
    assert punggol["resale"]["4-ROOM"] == {"median": 610000, "quarter": "2026-Q2"}
    assert punggol["commute"]["cbd"] == {"min": 45, "transfers": 1, "fare": 194}
    jurong = next(t for t in data["towns"] if t["id"] == "jurong-east")
    assert jurong["commute"]["jurong-east"] == {"min": None, "transfers": None, "same_area": True}
    assert jurong["commute"]["cbd"] == {"min": 45, "transfers": 1, "fare": 194}
    woodlands = next(t for t in data["towns"] if t["id"] == "woodlands")
    assert woodlands["commute"]["woodlands"]["same_area"] is True
    assert woodlands["commute"]["woodlands"]["min"] is None
    # Only the two same-area pairs carry the flag.
    flagged = [
        (t["id"], a) for t in data["towns"] for a, v in t["commute"].items() if v.get("same_area")
    ]
    assert sorted(flagged) == [("jurong-east", "jurong-east"), ("woodlands", "woodlands")]
    assert report["rent"]["points_without_data"] == []
    assert report["routes"]["fetched"] == 26 * 6 - 2  # two towns are office areas too
    assert len(cache) == 26 * 6 - 2


@respx.mock
async def test_where_to_live_is_in_the_app_manifest(tmp_path, monkeypatch):
    """The app loads where-to-live.json like any bundle, by its sha256 in the manifest."""
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    get_settings.cache_clear()
    stops = [
        {
            "BusStopCode": f"{i:05d}",
            "RoadName": "R",
            "Description": "D",
            "Latitude": 1.3,
            "Longitude": 103.8,
        }
        for i in range(4100)
    ]
    respx.get(url__startswith="https://datamall2.mytransport.sg/ltaodataservice/BusStops").mock(
        side_effect=lambda r: httpx.Response(
            200, json={"value": stops[int(r.url.params["$skip"]) :][:500]}
        )
    )
    # Written by the weekly where-to-live job, not by this build.
    payload = b'{"generated_at":"2026-11-08T00:00:00Z","areas":[],"towns":[{"id":"x"}]}'
    (tmp_path / "where-to-live.json").write_bytes(payload)
    try:
        async with httpx.AsyncClient() as c:
            manifest = await build_static.build(tmp_path, c, only_bus_stops=True)
    finally:
        get_settings.cache_clear()
    entry = manifest["files"]["where-to-live"]
    assert entry["path"] == "where-to-live.json"
    assert entry["sha256"] == hashlib.sha256(payload).hexdigest()


def test_parse_medians_real_row_shapes():
    # As seen in the first dry run (7 Nov 2026): rent uses "1-RM" and upper-case towns,
    # resale uses "1-room", title-case towns and both "na" and "-".
    rent = [
        {
            "_id": 1,
            "quarter": "2026-Q3",
            "town": "ANG MO KIO",
            "flat_type": "1-RM",
            "median_rent": "na",
        },
        {
            "_id": 2,
            "quarter": "2026-Q3",
            "town": "ANG MO KIO",
            "flat_type": "3-RM",
            "median_rent": "2800",
        },
    ]
    resale = [
        {"_id": 1, "quarter": "2026-Q2", "town": "Ang Mo Kio", "flat_type": "2-room", "price": "-"},
        {
            "_id": 2,
            "quarter": "2026-Q2",
            "town": "Ang Mo Kio",
            "flat_type": "3-room",
            "price": "425000",
        },
        {
            "_id": 3,
            "quarter": "2026-Q2",
            "town": "Central",
            "flat_type": "4-room",
            "price": "900000",
        },
    ]
    _, r, _ = w.parse_medians(rent)
    _, s, _ = w.parse_medians(resale)
    amk = w.town_key("ANG MO KIO")
    assert r[amk] == {"1-ROOM": None, "3-ROOM": {"median": 2800, "quarter": "2026-Q3"}}
    assert s[amk]["2-ROOM"] is None
    assert s[amk]["3-ROOM"] == {"median": 425000, "quarter": "2026-Q2"}
    assert s[w.town_key("CENTRAL AREA")]["4-ROOM"]["median"] == 900000


async def test_build_routes_same_area_is_flagged_and_not_asked():
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        return httpx.Response(200, json=ROUTE_BODY)

    om, client = onemap(handler)
    town = {
        "id": "woodlands",
        "town": "WOODLANDS",
        "name": "Woodlands",
        "station": "Woodlands",
        "lat": 1.43619,
        "lng": 103.78763,
    }
    area = {
        "id": "woodlands",
        "name": "Woodlands",
        "station": "Woodlands",
        "lat": 1.43619,
        "lng": 103.78763,
    }
    out, new_cache, notes = await w.build_routes(
        om, [town], [area], {}, date(2026, 11, 7), set(), sleep=no_sleep
    )
    await client.aclose()
    assert out == {"woodlands": {"woodlands": {"min": None, "transfers": None, "same_area": True}}}
    assert calls == [] and new_cache == {}
    assert notes["fetched"] == notes["failed"] == 0


def test_assemble_counts_same_area_as_known():
    commute = {f"t{i}": {"cbd": dict(w.SAME_AREA) if i < 6 else None} for i in range(22)}
    commute.update({f"t{i}": {"cbd": {"min": 30, "transfers": 1}} for i in range(6, 22)})
    data = w.assemble(points(22), ("2026-Q3", priced(22)), ("2026-Q3", {}), commute)
    assert data["towns"][0]["commute"]["cbd"]["same_area"] is True


def test_flat_types_from_both_datasets_share_one_key():
    # Real spellings: rent "4-RM", resale "4-room" (dry run, 7 Nov 2026).
    rent = [
        {
            "_id": 1,
            "quarter": "2026-Q3",
            "town": "PUNGGOL",
            "flat_type": "4-RM",
            "median_rent": "3300",
        },
        {
            "_id": 2,
            "quarter": "2026-Q3",
            "town": "PUNGGOL",
            "flat_type": "EXECUTIVE",
            "median_rent": "3600",
        },
    ]
    resale = [
        {
            "_id": 1,
            "quarter": "2026-Q2",
            "town": "Punggol",
            "flat_type": "4-room",
            "price": "610000",
        },
        {
            "_id": 2,
            "quarter": "2026-Q2",
            "town": "Punggol",
            "flat_type": "Executive",
            "price": "800000",
        },
    ]
    _, r, _ = w.parse_medians(rent)
    _, s, _ = w.parse_medians(resale)
    key = w.town_key("PUNGGOL")
    assert w.town_key("Punggol") == key
    assert list(r[key]) == list(s[key]) == ["4-ROOM", "EXECUTIVE"]
    assert r[key]["4-ROOM"]["median"] == 3300 and s[key]["4-ROOM"]["median"] == 610000
    for raw in (
        "1-RM",
        "2-RM",
        "3-RM",
        "4-RM",
        "5-RM",
        "1-room",
        "2-room",
        "3-room",
        "4-room",
        "5-room",
    ):
        assert w.norm_flat(raw) == f"{raw[0]}-ROOM"


def test_parse_fare():
    assert w.parse_fare("1.94") == 194
    assert w.parse_fare("$2.10") == 210
    assert w.parse_fare(1.5) == 150
    for bad in (None, "", "free", "0", "-1", "12.50", True):
        assert w.parse_fare(bad) is None, bad


def test_parse_route_fare_of_the_fastest_itinerary_or_none():
    assert w.parse_route(ROUTE_BODY)["fare"] == 194
    body = {"plan": {"itineraries": [{"duration": 600, "transfers": 0}]}}
    assert w.parse_route(body) == {"min": 10, "transfers": 0, "fare": None}


async def test_build_routes_asks_again_for_cached_routes_without_a_fare():
    today = date(2026, 11, 8)
    cache = {
        "punggol|cbd": {
            "from": [1.4, 103.9],
            "to": [1.28, 103.85],
            "min": 50,
            "transfers": 1,
            "at": "2026-11-07",
        }
    }
    calls = []

    def handler(req: httpx.Request) -> httpx.Response:
        calls.append(req)
        return httpx.Response(200, json=ROUTE_BODY)

    om, client = onemap(handler)
    out, new_cache, notes = await w.build_routes(
        om, TOWNS[:1], AREAS, cache, today, set(), sleep=no_sleep
    )
    await client.aclose()
    assert len(calls) == 1
    assert out["punggol"]["cbd"] == {"min": 45, "transfers": 1, "fare": 194}
    assert new_cache["punggol|cbd"]["fare"] == 194
    assert (notes["fetched"], notes["no_fare"]) == (1, 0)


async def test_build_routes_keeps_a_route_without_a_fare_when_onemap_fails():
    # Cached before fares were kept: asked again, and kept (fare None) when OneMap fails.
    old = {
        "from": [1.4, 103.9],
        "to": [1.28, 103.85],
        "min": 50,
        "transfers": 1,
        "at": "2026-11-07",
    }
    om, client = onemap(lambda req: httpx.Response(500))
    out, new_cache, notes = await w.build_routes(
        om, TOWNS[:1], AREAS, {"punggol|cbd": old}, date(2026, 11, 8), set(), sleep=no_sleep
    )
    await client.aclose()
    assert out["punggol"]["cbd"] == {"min": 50, "transfers": 1, "fare": None}
    assert new_cache["punggol|cbd"] == old
    assert (notes["failed_used_old"], notes["failed"]) == (1, 0)


async def test_build_routes_does_not_fall_back_on_a_cached_route_without_transfers():
    old = {"from": [1.4, 103.9], "to": [1.28, 103.85], "min": 50, "at": "2026-11-07"}
    om, client = onemap(lambda req: httpx.Response(500))
    out, new_cache, notes = await w.build_routes(
        om, TOWNS[:1], AREAS, {"punggol|cbd": old}, date(2026, 11, 8), set(), sleep=no_sleep
    )
    await client.aclose()
    assert out["punggol"]["cbd"] is None
    assert "punggol|cbd" not in new_cache
    assert notes["failed"] == 1
