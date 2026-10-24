from datetime import date

import httpx
import pytest
import respx

from app.events import EVENTFINDA, build_events, compact_eventfinda

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


@pytest.mark.asyncio
@respx.mock
async def test_build_events_pages_eventfinda_and_skips_missing_keys():
    respx.get(url__startswith=EVENTFINDA).mock(
        return_value=httpx.Response(200, json={"@attributes": {"count": 1}, "events": [EF_ROW]})
    )
    async with httpx.AsyncClient() as c:
        out = await build_events(c, TODAY, "u", "p")
        none = await build_events(c, TODAY, None, None)
    assert len(out) == 1
    assert none == []


def test_compact_eventfinda_reads_string_flags():
    free = {**EF_ROW, "is_free": "1", "is_cancelled": "0"}
    paid = {**EF_ROW, "id": 2, "url": "https://www.eventfinda.sg/2026/y", "is_free": "0"}
    out = compact_eventfinda([free, paid], TODAY)
    assert [e["f"] for e in out] == [True, False]


@pytest.mark.asyncio
@respx.mock
async def test_eventfinda_keeps_paging_without_count():
    rows = [
        {**EF_ROW, "id": i, "url": f"https://www.eventfinda.sg/2026/e{i}", "name": f"Event {i}"}
        for i in range(25)
    ]

    def page(request):
        offset = int(request.url.params["offset"])
        return httpx.Response(200, json={"events": rows[offset : offset + 20]})

    route = respx.get(url__startswith=EVENTFINDA).mock(side_effect=page)
    async with httpx.AsyncClient() as c:
        out = await build_events(c, TODAY, "u", "p")
    assert route.call_count == 2
    assert len(out) == 25
