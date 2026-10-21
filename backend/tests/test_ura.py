from datetime import date

import httpx
import pytest
import respx

from app import ura


def test_last_quarters():
    assert ura.last_quarters(date(2026, 10, 21)) == ["26q3", "26q2", "26q1", "25q4"]
    assert ura.last_quarters(date(2026, 2, 1), 2) == ["25q4", "25q3"]


def test_compact_private_summarises_a_project():
    tx = [
        {
            "project": "TAIPAN GRAND",
            "street": "MARINE PARADE ROAD",
            "x": "39140.90324",
            "y": "32655.63524",
            "transaction": [
                {
                    "area": "100",
                    "floorRange": "06-10",
                    "noOfUnits": "1",
                    "contractDate": "0826",
                    "price": "1076390",
                    "propertyType": "Condominium",
                    "tenure": "Freehold",
                },
                {
                    "area": "100",
                    "floorRange": "01-05",
                    "noOfUnits": "1",
                    "contractDate": "0326",
                    "price": "1291668",
                    "propertyType": "Condominium",
                    "tenure": "Freehold",
                },
                {
                    "area": "300",
                    "floorRange": "-",
                    "noOfUnits": "3",
                    "contractDate": "0526",
                    "price": "9000000",
                    "propertyType": "Condominium",
                    "tenure": "Freehold",
                },
            ],
        }
    ]
    rents = [
        {
            "project": "TAIPAN GRAND",
            "street": "MARINE PARADE ROAD",
            "x": "39140.9",
            "y": "32655.6",
            "rental": [
                {"noOfBedRoom": "3", "rent": 4500},
                {"noOfBedRoom": "3", "rent": 4700},
                {"noOfBedRoom": "2", "rent": 3600},
            ],
        }
    ]
    out = ura.compact_private(tx, rents, date(2026, 10, 21))
    assert len(out) == 1
    p = out[0]
    assert p["n"] == "Taipan Grand" and p["s"] == "Marine Parade Road"
    assert 1.29 < p["la"] < 1.33 and 103.89 < p["lo"] < 103.95
    assert p["psf"] == 1100 and p["pc"] == 2  # bulk sale left out
    assert p["tx"][0] == ["2026-08", 1076390, 100, "06-10"]
    assert p["rent"] == {"2": 3600, "3": 4600} and p["rc"] == 3
    assert p["ten"] == "Freehold"


@respx.mock
async def test_build_private_logs_in_and_reads_batches():
    respx.get(ura.TOKEN_URL).mock(
        return_value=httpx.Response(200, json={"Status": "Success", "Result": "TOK"})
    )
    data = respx.get(ura.DATA_URL).mock(
        return_value=httpx.Response(200, json={"Status": "Success", "Result": []})
    )
    async with httpx.AsyncClient() as c:
        out = await ura.build_private(c, "KEY", date(2026, 10, 21))
    assert out == []
    assert data.calls[0].request.headers["Token"] == "TOK"
    assert data.call_count == 8  # 4 transaction batches + 4 rental quarters


async def test_build_private_needs_key():
    async with httpx.AsyncClient() as c:
        with pytest.raises(RuntimeError):
            await ura.build_private(c, None, date(2026, 10, 21))
