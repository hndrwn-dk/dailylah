"""Public events for the weekend card: Eventfinda (search by area) and Eventbrite (events of
organizers listed in data/eventbrite_organizers.json; Eventbrite has no public search).
Built once a day into events.json; the API keys stay in CI secrets and never reach the app."""

import json
import logging
from datetime import date, datetime, timedelta
from pathlib import Path

import httpx

log = logging.getLogger("dailylah.events")

EVENTFINDA = "https://api.eventfinda.sg/v2/events.json"
EVENTBRITE = "https://www.eventbriteapi.com/v3"
ORGANIZERS = Path(__file__).resolve().parent.parent / "data" / "eventbrite_organizers.json"
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


def compact_eventbrite(rows: list[dict], today: date, days: int = 30) -> list[dict]:
    """Eventbrite events (expand=venue) in Singapore with a venue point."""
    until = today + timedelta(days=days)
    out = []
    for e in rows:
        start = (e.get("start") or {}).get("local", "")
        end = (e.get("end") or {}).get("local", "")
        v = e.get("venue") or {}
        addr = v.get("address") or {}
        lat, lng = (
            v.get("latitude") or addr.get("latitude"),
            v.get("longitude") or addr.get("longitude"),
        )
        d0, d1 = _day(start), _day(end)
        if not lat or not lng or d0 is None or (d1 or d0) < today or d0 > until:
            continue
        if addr.get("country") not in (None, "", "SG"):
            continue
        out.append(
            {
                "n": str((e.get("name") or {}).get("text", "")).strip(),
                "u": str(e.get("url", "")),
                "s": start.replace("T", " ")[:16],
                "e": end.replace("T", " ")[:16],
                "w": "",
                "p": str(v.get("name", "")),
                "la": round(float(lat), 5),
                "lo": round(float(lng), 5),
                "f": bool(e.get("is_free")),
                "c": "",
                "src": "Eventbrite",
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


async def eventbrite(client: httpx.AsyncClient, token: str, today: date) -> list[dict]:
    try:
        organizers = json.loads(ORGANIZERS.read_text())
    except (OSError, ValueError):
        organizers = []
    rows: list[dict] = []
    for org in organizers:
        r = await client.get(
            f"{EVENTBRITE}/organizers/{org}/events/",
            params={"status": "live", "expand": "venue", "order_by": "start_asc"},
            headers={"Authorization": f"Bearer {token}"},
        )
        if r.status_code != 200:
            log.warning("eventbrite organizer %s: %s", org, r.status_code)
            continue
        rows.extend(r.json().get("events") or [])
    return compact_eventbrite(rows, today)


async def build_events(
    client: httpx.AsyncClient,
    today: date,
    ef_user: str | None,
    ef_password: str | None,
    eb_token: str | None,
) -> list[dict]:
    out: list[dict] = []
    if ef_user and ef_password:
        out += await eventfinda(client, ef_user, ef_password, today)
    if eb_token:
        try:
            out += await eventbrite(client, eb_token, today)
        except httpx.HTTPError as e:  # one source down should not drop the other
            log.warning("eventbrite failed: %s", e)
    seen: set[tuple[str, str]] = set()
    uniq = []
    for e in sorted(out, key=lambda x: x["s"]):
        k = (e["n"].lower(), e["s"][:10])
        if k not in seen:
            seen.add(k)
            uniq.append(e)
    return uniq
