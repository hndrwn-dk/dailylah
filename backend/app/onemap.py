"""OneMap (Singapore Land Authority) with token handling.

OneMap's search needs a token since 2026. Tokens last about three days and are
requested with the account's email and password (env vars ONEMAP_EMAIL and
ONEMAP_PASSWORD), so the token itself is never stored anywhere but memory.
"""

import asyncio
import logging
import re
import time

import httpx

log = logging.getLogger("dailylah.onemap")

TOKEN_URL = "https://www.onemap.gov.sg/api/auth/post/getToken"  # noqa: S105 (an endpoint URL, not a secret)
SEARCH_URL = "https://www.onemap.gov.sg/api/common/elastic/search"
THEME_URL = "https://www.onemap.gov.sg/api/public/themesvc/retrieveTheme"

# A OneMap error message that may go in the log (see OneMap.why_failed).
_PLAIN_WORDS = re.compile(r"[A-Za-z .,'…]{1,80}")

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
        # Whether the last request went out with a token (for the log, see why_failed).
        self._sent_token = False

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
        headers = await self.headers()
        self._sent_token = bool(headers)
        r = await self.client.get(url, params=params, headers=headers)
        if r.status_code in (401, 403) and self.configured:
            tok = await self.token(force=True)
            if tok:
                self._sent_token = True
                r = await self.client.get(url, params=params, headers={"Authorization": tok})
        return r

    def why_failed(self, e: Exception, query: str) -> str:
        """Why a OneMap call failed, for the log: OneMap's status, or the kind of network error,
        and whether the request went out with a token. OneMap's own message is added only when it
        refused the token or the rate (401, 403, 429), with the text searched for cut out, and
        only if what is left is plain words (letters, spaces and . , '): no digits, so no postal
        code or token, and no control characters, so no forged log line. Any other message is
        left out: it could echo the search text in a form that cannot be recognised."""
        sent = "with token" if self._sent_token else "no token"
        if not isinstance(e, httpx.HTTPStatusError):
            return f"{type(e).__name__} ({sent})"
        status = e.response.status_code
        said = ""
        if status in (401, 403, 429):
            try:
                body = e.response.json()
                if isinstance(body, dict):
                    said = str(body.get("message") or body.get("error") or "")
            except ValueError:
                pass
            # The whole query and each word of it, in any case.
            for part in sorted({query, *query.split()}, key=len, reverse=True):
                if part:
                    said = re.sub(re.escape(part), "…", said, flags=re.IGNORECASE)
            if not _PLAIN_WORDS.fullmatch(said):
                said = ""
        return f"HTTP {status} ({sent}) {said}".rstrip()

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
