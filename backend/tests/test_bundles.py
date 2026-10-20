import json
from datetime import date

import httpx
import pytest
import respx

from app import build_static
from app import bundles as b
from app.config import get_settings

LTA = "https://datamall2.mytransport.sg/ltaodataservice"


def test_compact_hawkers_parses_closures():
    rows = [
        {
            "serial_no": "1",
            "name": "Adam Road Food Centre",
            "q1_cleaningstartdate": "30/3/2026",
            "q1_cleaningenddate": "31/3/2026",
            "q2_cleaningstartdate": "NA",
            "q2_cleaningenddate": "NA",
            "other_works_startdate": "1/11/2026",
            "other_works_enddate": "30/11/2026",
            "latitude_hc": "1.324131966",
            "longitude_hc": "103.8141632",
            "address_myenv": "2, Adam Road, Singapore 289876",
            "status": "Existing",
        },
        {
            "serial_no": "2",
            "name": "Gone",
            "status": "Under Renovation",
            "latitude_hc": "1",
            "longitude_hc": "1",
        },
        {
            "serial_no": "3",
            "name": "No coords",
            "status": "Existing",
            "latitude_hc": "",
            "longitude_hc": "",
        },
    ]
    out = b.compact_hawkers(rows)
    assert len(out) == 1
    assert out[0]["c"] == [
        ["2026-03-30", "2026-03-31", "cleaning"],
        ["2026-11-01", "2026-11-30", "works"],
    ]
    assert out[0]["la"] == 1.32413


def test_dengue_centroid_and_radius():
    square = [[103.94, 1.35], [103.942, 1.35], [103.942, 1.352], [103.94, 1.352], [103.94, 1.35]]
    geo = {
        "features": [
            {
                "properties": {"LOCALITY": "Tampines St 81", "CASE_SIZE": 12},
                "geometry": {"type": "Polygon", "coordinates": [square]},
            },
            {"properties": {"LOCALITY": "Bad"}, "geometry": None},
        ]
    }
    out = b.compact_dengue(geo)["clusters"]
    assert out[0]["loc"] == "Tampines St 81"
    assert out[0]["n"] == 12
    assert 100 < out[0]["r"] < 200
    assert abs(out[0]["la"] - 1.3508) < 0.001


def test_points_from_html_description_and_mrt_dedupe():
    geo = {
        "features": [
            {
                "properties": {
                    "Name": "kml_1",
                    "Description": "<table><tr><th>NAME</th> "
                    "<td>Tampines Regional Library</td></tr></table>",
                },
                "geometry": {"type": "Point", "coordinates": [103.9446, 1.3529, 0]},
            }
        ]
    }
    assert b.compact_points(geo)[0]["n"] == "Tampines Regional Library"
    exits = {
        "features": [
            {
                "properties": {"STATION_NA": "TAMPINES MRT STATION"},
                "geometry": {"type": "Point", "coordinates": [103.944, 1.353]},
            },
            {
                "properties": {"STATION_NA": "TAMPINES MRT STATION"},
                "geometry": {"type": "Point", "coordinates": [103.946, 1.355]},
            },
        ]
    }
    mrt = b.compact_mrt(exits)
    assert mrt == [{"n": "Tampines MRT Station", "la": 1.354, "lo": 103.945}]


def test_sports_filter():
    rows = [
        {
            "VenueName": "TAMPINES SPORTS CENTRE",
            "SportsFacility": "Swimming Pool",
            "Latitude": "1.35",
            "Longitude": "103.94",
        },
        {
            "VenueName": "TAMPINES SPORTS CENTRE",
            "SportsFacility": "Sports Hall",
            "Latitude": "1.35",
            "Longitude": "103.94",
        },
        {
            "VenueName": "ECO Condominium",
            "SportsFacility": "Swimming Pool",
            "Latitude": "1.3",
            "Longitude": "103.9",
        },
        {
            "VenueName": "Some Park",
            "SportsFacility": "Fitness Corner",
            "Latitude": "1.3",
            "Longitude": "103.9",
        },
    ]
    out = b.compact_sports(rows)
    assert len(out) == 1
    assert out[0]["d"] == "Sports Hall, Swimming Pool"


def test_carparks_convert_svy21():
    out = b.compact_carparks(
        [
            {
                "car_park_no": "ACB",
                "address": "BLK 270/271 ALBERT CENTRE BASEMENT CAR PARK",
                "x_coord": "30314.7936",
                "y_coord": "31490.4942",
                "car_park_type": "BASEMENT CAR PARK",
                "free_parking": "NO",
                "night_parking": "YES",
            }
        ]
    )
    assert out[0]["id"] == "ACB"
    assert abs(out[0]["la"] - 1.3011) < 0.001 and abs(out[0]["lo"] - 103.8541) < 0.001


def test_resale_and_rent_summaries():
    rows = [
        {
            "month": "2026-09",
            "town": "BEDOK",
            "flat_type": "4 ROOM",
            "block": "123",
            "street_name": "BEDOK NTH ST 2",
            "resale_price": "500000",
        },
        {
            "month": "2026-01",
            "town": "BEDOK",
            "flat_type": "4 ROOM",
            "block": "123",
            "street_name": "BEDOK NTH ST 2",
            "resale_price": "460000",
        },
        {
            "month": "2025-06",
            "town": "BEDOK",
            "flat_type": "4 ROOM",
            "block": "123",
            "street_name": "BEDOK NTH ST 2",
            "resale_price": "480000",
        },
        {
            "month": "2023-01",
            "town": "BEDOK",
            "flat_type": "4 ROOM",
            "block": "123",
            "street_name": "BEDOK NTH ST 2",
            "resale_price": "1",
        },
    ]
    s = b.summarise_resale(rows, "2024-10")
    assert s["blocks"]["123|BEDOK NTH ST 2"]["4 ROOM"] == [480000, 3, "2026-09", 500000]
    assert s["towns"]["BEDOK"]["4 ROOM"] == 480000
    assert s["block_town"]["123|BEDOK NTH ST 2"] == "BEDOK"
    assert (s["from"], s["to"]) == ("2025-06", "2026-09")

    rent = b.summarise_rent(
        [
            {
                "rent_approval_date": "2026-09",
                "town": "BEDOK",
                "flat_type": "4-ROOM",
                "monthly_rent": str(v),
            }
            for v in (2800, 3000, 3200)
        ]
        + [
            {
                "rent_approval_date": "2026-09",
                "town": "BEDOK",
                "flat_type": "1-ROOM",
                "monthly_rent": "900",
            }
        ],
        "2026-04",
    )
    assert rent["towns"] == {"BEDOK": {"4-ROOM": 3000}}
    assert b.months_back(date(2026, 10, 20), 24) == "2024-10"
    assert b.months_back(date(2026, 1, 5), 1) == "2025-12"


def test_residential_blocks_and_prayer():
    rows = [
        {
            "blk_no": "123",
            "street": "BEDOK NTH ST 2",
            "residential": "Y",
            "bldg_contract_town": "BD",
            "year_completed": "1980",
            "max_floor_lvl": "12",
        },
        {"blk_no": "1", "street": "X", "residential": "N"},
    ]
    assert b.residential_blocks(rows, {}) == [
        {"b": "123", "s": "BEDOK NTH ST 2", "t": "BEDOK", "y": 1980, "f": 12}
    ]
    p = b.compact_prayer(
        [
            {
                "Date": "2024-01-01",
                "Subuh": "05:44",
                "Syuruk": "07:07",
                "Zohor": "01:10",
                "Asar": "04:34",
                "Maghrib": "07:10",
                "Isyak": "08:25",
            },
            {
                "Date": "2026-01-01",
                "Subuh": "05:44",
                "Syuruk": "07:08",
                "Zohor": "13:10",
                "Asar": "16:34",
                "Maghrib": "19:11",
                "Isyak": "20:25",
            },
        ]
    )
    assert p["days"]["2024-01-01"] == ["05:44", "07:07", "13:10", "16:34", "19:10", "20:25"]
    assert p["days"]["2026-01-01"][5] == "20:25"


@respx.mock
async def test_datastore_pages_until_stop_and_retries_429():
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(429)
        offset = int(request.url.params["offset"])
        rows = [{"month": "2026-09" if offset == 0 else "2020-01"}] * b.PAGE
        return httpx.Response(200, json={"result": {"records": rows}})

    respx.get(b.DATASTORE_URL).mock(side_effect=handler)
    async with httpx.AsyncClient() as c:
        rows = await b.DataGov(c, pause=0).rows(
            "x", sort="month desc", stop=lambda r: r["month"] < "2024-10"
        )
    assert len(rows) == b.PAGE
    assert calls["n"] == 3


@respx.mock
async def test_geocoder_caches_and_matches_block(tmp_path):
    route = respx.get(b.ONEMAP_SEARCH_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {"BLK_NO": "12", "LATITUDE": "1.1", "LONGITUDE": "103.1"},
                    {"BLK_NO": "123", "LATITUDE": "1.33", "LONGITUDE": "103.93"},
                ]
            },
        )
    )
    cache = tmp_path / "geo.json"
    async with httpx.AsyncClient() as c:
        g = b.Geocoder(c, cache)
        assert await g.find("123 BEDOK NTH ST 2", block="123") == (1.33, 103.93)
        assert await g.find("123 bedok nth st 2", block="123") == (1.33, 103.93)
        g.save()
    assert route.call_count == 1
    assert json.loads(cache.read_text())["123 BEDOK NTH ST 2"] == [1.33, 103.93]


@respx.mock
async def test_build_keeps_previous_bundle_when_upstream_fails(tmp_path, monkeypatch):
    monkeypatch.setenv("LTA_ACCOUNT_KEY", "test-key")
    get_settings.cache_clear()
    stops = [
        {
            "BusStopCode": f"{i:05d}",
            "Description": "S",
            "RoadName": "R",
            "Latitude": 1.3,
            "Longitude": 103.8,
        }
        for i in range(4100)
    ]
    respx.get(f"{LTA}/BusStops").mock(
        side_effect=lambda r: httpx.Response(
            200,
            json={"value": stops[int(r.url.params["$skip"]) : int(r.url.params["$skip"]) + 500]},
        )
    )
    respx.get(b.DATASTORE_URL).mock(return_value=httpx.Response(500))
    respx.get(url__startswith="https://api-open.data.gov.sg/v1/public/api/datasets/").mock(
        return_value=httpx.Response(500)
    )
    respx.get(b.ONEMAP_SEARCH_URL).mock(return_value=httpx.Response(200, json={"results": []}))
    (tmp_path / "hawkers.json").write_text('[{"id":"1"}]')

    async with httpx.AsyncClient() as c:
        manifest = await build_static.build(
            tmp_path, c, geocode_cache=None, pause=0, today=date(2026, 10, 20)
        )
    assert manifest["files"]["bus_stops"]["count"] == 4100
    assert manifest["files"]["hawkers"]["count"] == 1  # kept from the previous run
    assert "dengue" not in manifest["files"]
    get_settings.cache_clear()


@pytest.mark.parametrize("value", ["", "31/02/2026", "2026-01-01"])
def test_bad_dates_are_ignored(value):
    assert b._dmy(value) is None


def test_match_blocks_uses_street_codes_and_prefix():
    blocks = [
        {"b": "1", "s": "BEDOK STH AVE 1", "t": "BEDOK", "y": 1975, "f": 14},
        {"b": "2", "s": "BEDOK STH AVE 1", "t": "BEDOK", "y": 1975, "f": 14},
        {"b": "1", "s": "BEACH RD", "t": "KALLANG/WHAMPOA", "y": 1970, "f": 16},
        {"b": "9", "s": "NOWHERE ST", "t": "X", "y": 1990, "f": 10},
    ]
    buildings = b.compact_buildings(
        {
            "features": [
                {
                    "properties": {"BLK_NO": blk, "ST_COD": code, "POSTAL_COD": pc},
                    "geometry": {"type": "Point", "coordinates": [lng, lat]},
                }
                for blk, code, pc, lat, lng in [
                    ("1", "BED05S", "460001", 1.321, 103.94),
                    ("2", "BED05S", "460002", 1.322, 103.94),
                    ("1", "BEA01R", "190001", 1.30, 103.86),
                ]
            ]
        }
    )
    out = {(x["b"], x["s"]): x for x in b.match_blocks(blocks, buildings)}
    assert out[("1", "BEDOK STH AVE 1")]["p"] == "460001"
    assert out[("1", "BEACH RD")]["p"] == "190001"
    assert ("9", "NOWHERE ST") not in out


def test_emergency_layers():
    aeds = b.compact_aeds(
        {
            "features": [
                {
                    "properties": {
                        "HOUSE_NUMBER": "22",
                        "ROAD_NAME": "Sentosa Gateway",
                        "BUILDING_NAME": "SEA Aquarium",
                        "AED_LOCATION_DESCRIPTION": "Open Ocean Habitat",
                        "AED_LOCATION_FLOOR_LEVEL": "B1M",
                        "OPERATING_HOURS": "Mon - Sun 00:00-23:59;",
                        "LATITUDE": 1.258654,
                        "LONGITUDE": 103.8183899,
                    },
                    "geometry": {"type": "Point", "coordinates": [103.81839, 1.25865]},
                }
            ]
        }
    )
    assert aeds == [
        {
            "n": "SEA Aquarium",
            "la": 1.25865,
            "lo": 103.81839,
            "d": "Level B1M · Open Ocean Habitat",
            "h": "Mon - Sun 00:00-23:59",
        }
    ]
    fire = b.compact_fire_stations(
        {
            "features": [
                {
                    "properties": {
                        "NAME": "Jurong Fire Station",
                        "ADDRESS": "22 Jurong West st 26 Singapore 648126",
                        "DESCRIPTION": "Tel: 6267 4700/1 Fax: 6261 5614",
                    },
                    "geometry": {"type": "Point", "coordinates": [103.7, 1.35]},
                }
            ]
        }
    )
    assert fire[0]["t"] == "62674700"
    desc = (
        "<table><tr> <th>HCI_NAME</th> <td>Acumed Medical Group</td> </tr>"
        "<tr> <th>HCI_TEL</th> <td>68615755</td> </tr>"
        "<tr> <th>BLK_HSE_NO</th> <td>1</td> </tr>"
        "<tr> <th>STREET_NAME</th> <td>JOO KOON CIRCLE</td> </tr></table>"
    )
    clinics = b.compact_clinics(
        {
            "features": [
                {
                    "properties": {"Description": desc},
                    "geometry": {"type": "Point", "coordinates": [103.68, 1.33]},
                }
            ]
        }
    )
    assert clinics[0] == {
        "n": "Acumed Medical Group",
        "a": "1 Joo Koon Circle",
        "la": 1.33,
        "lo": 103.68,
        "t": "68615755",
    }
