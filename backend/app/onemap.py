"""OneMap (Singapore Land Authority) with token handling.

OneMap's search needs a token since 2026. Tokens last about three days and are
requested with the account's email and password (env vars ONEMAP_EMAIL and
ONEMAP_PASSWORD), so the token itself is never stored anywhere but memory.
"""

import asyncio
import logging
import time

import httpx

log = logging.getLogger("dailylah.onemap")

TOKEN_URL = "https://www.onemap.gov.sg/api/auth/post/getToken"
SEARCH_URL = "https://www.onemap.gov.sg/api/common/elastic/search"
THEME_URL = "https://www.onemap.gov.sg/api/public/themesvc/retrieveTheme"

# Renew this long before the token expires.
RENEW_MARGIN_S = 6 * 3600


class OneMap:
    def __init__(self, client: httpx.AsyncClient, email: str | None, password: str | None) -> None:
        self.client = client
        self.email = email
        self.password = password
        self._token: str | None = None
        self._expires = 0.0
        self._lock = asyncio.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.email and self.password)

    async def token(self, force: bool = False) -> str | None:
        """A valid token, or None when no account is configured or login fails."""
        if not self.configured:
            return None
        if not force and self._token and time.time() < self._expires - RENEW_MARGIN_S:
            return self._token
        async with self._lock:
            if not force and self._token and time.time() < self._expires - RENEW_MARGIN_S:
                return self._token
            try:
                r = await self.client.post(
                    TOKEN_URL, json={"email": self.email, "password": self.password}
                )
                r.raise_for_status()
                body = r.json()
                self._token = body["access_token"]
                self._expires = float(body.get("expiry_timestamp") or time.time() + 3 * 86400)
            except (httpx.HTTPError, KeyError, ValueError) as e:
                # Never log the response body: it may echo account details.
                log.warning("OneMap token request failed: %s", type(e).__name__)
                self._token = None
                return None
        return self._token

    async def headers(self) -> dict[str, str]:
        tok = await self.token()
        return {"Authorization": tok} if tok else {}

    async def get(self, url: str, params: dict) -> httpx.Response:
        """GET with the token; renews it once when OneMap says it is no longer valid."""
        r = await self.client.get(url, params=params, headers=await self.headers())
        if r.status_code in (401, 403) and self.configured:
            tok = await self.token(force=True)
            if tok:
                r = await self.client.get(url, params=params, headers={"Authorization": tok})
        return r

    async def search(self, query: str, page: int = 1) -> dict:
        r = await self.get(
            SEARCH_URL,
            {"searchVal": query, "returnGeom": "Y", "getAddrDetails": "Y", "pageNum": page},
        )
        r.raise_for_status()
        return r.json()

    async def theme(self, query_name: str) -> dict:
        r = await self.get(THEME_URL, {"queryName": query_name})
        r.raise_for_status()
        return r.json()
