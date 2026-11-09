"""Geoapify Autocomplete: place names (shops, restaurants, malls) for Plan a trip.

OneMap finds addresses, blocks and buildings but not most shop names, so /v1/places asks
Geoapify (OpenStreetMap data) instead. The key (env GEOAPIFY_API_KEY) only lives on the
server. Geoapify takes it as a URL parameter, so the request URL holds the key: errors are
re-raised without the httpx exception (whose text names the URL), and the httpx request log
line is redacted (key and typed text). Only the typed text and the Singapore filter are sent,
never a location.
"""

import logging
import re

import httpx

log = logging.getLogger("dailylah.geoapify")

AUTOCOMPLETE_URL = "https://api.geoapify.com/v1/geocode/autocomplete"
LIMIT = 6

_SECRET_PARAMS = re.compile(r"\b(apiKey=|text=)[^&\s'\"]+")


class GeoapifyError(Exception):
    """Geoapify did not answer with results. The message never holds the key or the URL."""


class _RedactKey(logging.Filter):
    """httpx logs every request URL at INFO; mask the key and the typed text (Geoapify's
    `apiKey` and `text` parameters) wherever they appear."""

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        redacted = _SECRET_PARAMS.sub(r"\1***", msg)
        if redacted != msg:
            record.msg = redacted
            record.args = ()
        return True


for _name in ("httpx", "httpcore"):
    logging.getLogger(_name).addFilter(_RedactKey())


def _num(v: object) -> float | None:
    return float(v) if isinstance(v, int | float) and not isinstance(v, bool) else None


def _text(v: object) -> str:
    return v.strip() if isinstance(v, str) else ""


def compact_places(body: object) -> list[dict]:
    """What the app reads from an autocomplete answer; results without a position are dropped."""
    results = body.get("results") if isinstance(body, dict) else None
    out: list[dict] = []
    for r in results if isinstance(results, list) else []:
        if not isinstance(r, dict):
            continue
        lat, lng = _num(r.get("lat")), _num(r.get("lon"))
        name = _text(r.get("name")) or _text(r.get("address_line1"))
        if lat is None or lng is None or not name:
            continue
        out.append(
            {
                "name": name,
                "address": _text(r.get("address_line2")),
                "postal": _text(r.get("postcode")),
                "lat": lat,
                "lng": lng,
                "type": _text(r.get("result_type")),
            }
        )
    return out


class Geoapify:
    def __init__(self, client: httpx.AsyncClient, api_key: str | None) -> None:
        self.client = client
        self.api_key = api_key

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    async def autocomplete(self, text: str) -> list[dict]:
        params = {
            "text": text,
            "filter": "countrycode:sg",
            "limit": LIMIT,
            "lang": "en",
            "format": "json",
            "apiKey": self.api_key,
        }
        try:
            r = await self.client.get(AUTOCOMPLETE_URL, params=params)
            r.raise_for_status()
            body = r.json()
        except (httpx.HTTPError, ValueError) as e:
            # str(e) of an httpx error names the URL, key included: keep only the type and status.
            status = e.response.status_code if isinstance(e, httpx.HTTPStatusError) else None
            name = type(e).__name__
            log.warning("Geoapify autocomplete failed: %s %s", name, status or "")
            raise GeoapifyError(f"{name} {status or ''}".strip()) from None
        return compact_places(body)
