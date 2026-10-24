"""Public events for the weekend card, from Eventfinda (search by area). Built once a day into
events.json; the API key stays in CI secrets and never reaches the app."""

import logging
from datetime import date, datetime, timedelta

import httpx

log = logging.getLogger("dailylah.events")

EVENTFINDA = "https://api.eventfinda.sg/v2/events.json"
SG_CENTRE = "1.3521,103.8198"
FIELDS = (
    "event:(id,url,name,datetime_start,datetime_end,datetime_summary,location_summary,"
    "point,is_free,is_cancelled,category,location:(name))"
)


def _day(s: str) -> date | None:
    try:
        return datetime.fromisoformat(s.replace(" ", "T")[:19]).date()
    except (ValueError, AttributeError):
        return None


def compact_eventfinda(rows: list[dict], today: date, days: int = 30) -> list[dict]:
    """Upcoming or running events within [days], with a point: compact rows for the app."""
    until = today + timedelta(days=days)
    out = []
    for e in rows:
        start, end = _day(str(e.get("datetime_start", ""))), _day(str(e.get("datetime_end", "")))
        p = e.get("point") or {}
        if e.get("is_cancelled") or start is None or not p.get("lat") or not p.get("lng"):
            continue
        if (end or start) < today or start > until:
            continue
        out.append(
            {
                "n": str(e.get("name", "")).strip(),
                "u": str(e.get("url", "")),
                "s": str(e.get("datetime_start", ""))[:16],
                "e": str(e.get("datetime_end", ""))[:16],
                "w": str(e.get("datetime_summary", "")),
                "p": str((e.get("location") or {}).get("name") or e.get("location_summary", "")),
                "la": round(float(p["lat"]), 5),
                "lo": round(float(p["lng"]), 5),
                "f": bool(e.get("is_free")),
                "c": str((e.get("category") or {}).get("name", "")),
                "src": "Eventfinda",
            }
        )
    return out


async def eventfinda(
    client: httpx.AsyncClient, user: str, password: str, today: date
) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while offset < 500:
        r = await client.get(
            EVENTFINDA,
            params={
                "rows": 20,
                "offset": offset,
                "point": SG_CENTRE,
                "radius": 40,
                "order": "date",
                "fields": FIELDS,
            },
            auth=(user, password),
        )
        r.raise_for_status()
        body = r.json()
        page = body.get("events") or []
        rows.extend(page)
        total = int((body.get("@attributes") or {}).get("count", 0))
        offset += 20
        if not page or offset >= total:
            break
    return compact_eventfinda(rows, today)


async def build_events(
    client: httpx.AsyncClient,
    today: date,
    ef_user: str | None,
    ef_password: str | None,
) -> list[dict]:
    out: list[dict] = []
    if ef_user and ef_password:
        out += await eventfinda(client, ef_user, ef_password, today)
    seen: set[tuple[str, str]] = set()
    uniq = []
    for e in sorted(out, key=lambda x: x["s"]):
        k = (e["n"].lower(), e["s"][:10])
        if k not in seen:
            seen.add(k)
            uniq.append(e)
    return uniq
