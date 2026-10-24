from datetime import date

import httpx
import pytest
import respx

from app.events import EVENTFINDA, build_events, compact_eventbrite, compact_eventfinda

TODAY = date(2026, 10, 24)

EF_ROW = {
    "id": 1,
    "url": "https://www.eventfinda.sg/2026/x",
    "name": "Digital for Life Festival 2026",
    "datetime_start": "2026-10-24 09:00:00",
    "datetime_end": "2026-10-24 23:59:59",
    "datetime_summary": "Sat 24 Oct",
    "location_summary": "Vivocity, Marina Bay, Singapore",
    "is_free": True,
    "point": {"lat": 1.265, "lng": 103.8183},
    "category": {"name": "Festivals"},
    "location": {"name": "Vivocity"},
}


def test_compact_eventfinda_keeps_upcoming_with_point():
    old = {**EF_ROW, "datetime_start": "2026-01-01 09:00:00", "datetime_end": "2026-01-02 09:00:00"}
    far = {**EF_ROW, "datetime_start": "2027-03-01 09:00:00", "datetime_end": "2027-03-01 10:00:00"}
    cancelled = {**EF_ROW, "is_cancelled": True}
    nopoint = {**EF_ROW, "point": {}}
    out = compact_eventfinda([EF_ROW, old, far, cancelled, nopoint], TODAY)
    assert len(out) == 1
    e = out[0]
    assert e["n"] == "Digital for Life Festival 2026" and e["p"] == "Vivocity" and e["f"] is True
    assert e["s"] == "2026-10-24 09:00" and e["src"] == "Eventfinda"


def test_compact_eventbrite_needs_sg_venue():
    row = {
        "name": {"text": "Night Market"},
        "url": "https://www.eventbrite.sg/e/1",
        "start": {"local": "2026-10-25T18:00:00"},
        "end": {"local": "2026-10-25T23:00:00"},
        "is_free": True,
        "venue": {
            "name": "Somerset",
            "latitude": "1.30",
            "longitude": "103.84",
            "address": {"country": "SG"},
        },
    }
    abroad = {**row, "venue": {**row["venue"], "address": {"country": "MY"}}}
    out = compact_eventbrite([row, abroad], TODAY)
    assert [e["n"] for e in out] == ["Night Market"]


@pytest.mark.asyncio
@respx.mock
async def test_build_events_pages_eventfinda_and_skips_missing_keys():
    respx.get(url__startswith=EVENTFINDA).mock(
        return_value=httpx.Response(200, json={"@attributes": {"count": 1}, "events": [EF_ROW]})
    )
    async with httpx.AsyncClient() as c:
        out = await build_events(c, TODAY, "u", "p", None)
        none = await build_events(c, TODAY, None, None, None)
    assert len(out) == 1
    assert none == []
