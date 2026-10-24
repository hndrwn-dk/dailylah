import httpx
import pytest
import respx

from app import bundles as b
from app.datagov import DataGovKey

URL = "https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast"


@pytest.mark.asyncio
@respx.mock
async def test_rejected_key_falls_back_without_it(caplog):
    def handler(request):
        if request.headers.get("x-api-key"):
            return httpx.Response(401)
        return httpx.Response(200, json={"ok": 1})

    route = respx.get(URL).mock(side_effect=handler)
    key = DataGovKey("expired")
    async with httpx.AsyncClient() as c:
        first = await key.get(c, URL)
        second = await key.get(c, URL)
    assert first.json() == {"ok": 1} and second.json() == {"ok": 1}
    assert key.rejected
    # One retry for the first call; the second call goes straight without the key.
    assert route.call_count == 3
    assert "x-api-key" not in route.calls.last.request.headers
    assert "DATAGOV_API_KEY rejected" in caplog.text


@pytest.mark.asyncio
@respx.mock
async def test_dataset_403_keeps_the_key():
    respx.get(URL).mock(return_value=httpx.Response(403))
    key = DataGovKey("good")
    async with httpx.AsyncClient() as c:
        resp = await key.get(c, URL)
    assert resp.status_code == 403
    assert not key.rejected
    assert key.headers() == {"x-api-key": "good"}


@pytest.mark.asyncio
@respx.mock
async def test_no_key_sends_no_header():
    route = respx.get(URL).mock(return_value=httpx.Response(200, json={}))
    async with httpx.AsyncClient() as c:
        await DataGovKey(None).get(c, URL)
    assert route.call_count == 1
    assert "x-api-key" not in route.calls.last.request.headers


@pytest.mark.asyncio
@respx.mock
async def test_bundle_rows_survive_an_expired_key():
    def handler(request):
        if request.headers.get("x-api-key"):
            return httpx.Response(403)
        return httpx.Response(200, json={"result": {"records": [{"a": 1}]}})

    respx.get(url__startswith=b.DATASTORE_URL).mock(side_effect=handler)
    async with httpx.AsyncClient() as c:
        dg = b.DataGov(c, "expired", pause=0)
        rows = await dg.rows("d_x")
    assert rows == [{"a": 1}]
    assert dg.key.rejected
