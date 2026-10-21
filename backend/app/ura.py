"""URA Data Service: private residential transactions and rentals.

Needs URA_ACCESS_KEY (GitHub secret). A daily token is requested from the access key at
the start of each build; neither is stored.
"""

import json
import logging
import re
import statistics
from datetime import date

import httpx

from .svy21 import to_latlon

log = logging.getLogger(__name__)

TOKEN_URL = "https://eservice.ura.gov.sg/uraDataService/insertNewToken/v1"
DATA_URL = "https://eservice.ura.gov.sg/uraDataService/invokeUraDS/v1"
# URA's gateway rejects requests without a browser-like agent.
UA = {"User-Agent": "Mozilla/5.0 (compatible; DailyLah data build)"}
SQM_TO_SQFT = 10.7639


class Ura:
    def __init__(self, client: httpx.AsyncClient, access_key: str | None) -> None:
        self.client = client
        self.key = access_key
        self.token: str | None = None

    async def login(self) -> None:
        if not self.key:
            raise RuntimeError("URA_ACCESS_KEY not set")
        r = await self.client.get(TOKEN_URL, headers={**UA, "AccessKey": self.key})
        r.raise_for_status()
        body = r.json()
        if body.get("Status") != "Success" or not body.get("Result"):
            raise RuntimeError(f"URA token: {body.get('Message')}")
        self.token = body["Result"]

    async def service(self, name: str, **params) -> list[dict]:
        if self.token is None:
            await self.login()
        r = await self.client.get(
            DATA_URL,
            params={"service": name, **params},
            headers={**UA, "AccessKey": self.key or "", "Token": self.token or ""},
        )
        r.raise_for_status()
        body = json.loads(r.text, strict=False)  # some names carry control characters
        if body.get("Status") != "Success":
            raise RuntimeError(f"URA {name}: {body.get('Message')}")
        return body.get("Result") or []


def _mmyy(v: str) -> tuple[int, int] | None:
    m = re.fullmatch(r"(\d{2})(\d{2})", str(v or ""))
    return (2000 + int(m.group(2)), int(m.group(1))) if m else None


def last_quarters(today: date, n: int = 4) -> list[str]:
    """URA refPeriod codes for the n quarters before today's, newest first ('26q2', ...)."""
    y, q = today.year, (today.month - 1) // 3  # previous quarter
    out = []
    for _ in range(n):
        if q == 0:
            y, q = y - 1, 4
        out.append(f"{y % 100:02d}q{q}")
        q -= 1
    return out


def _title(s: str) -> str:
    return " ".join(w.capitalize() for w in str(s or "").strip().split())


def compact_private(tx_rows: list[dict], rent_rows: list[dict], today: date) -> list[dict]:
    """Per project: {"n","s","la","lo","ten","pt","psf","pc","tx":[[ym,price,sqm,floor]],
    "rent":{"2":median,...},"rc"}. psf = median price per sq ft over the last 12 months
    (36 when there were no sales in the last year)."""
    projects: dict[tuple[str, str], dict] = {}

    def entry(row: dict) -> dict | None:
        try:
            lat, lng = to_latlon(float(row["y"]), float(row["x"]))
        except (KeyError, TypeError, ValueError):
            return None
        key = (str(row.get("project", "")).upper(), str(row.get("street", "")).upper())
        return projects.setdefault(
            key,
            {
                "n": _title(row.get("project")),
                "s": _title(row.get("street")),
                "la": round(lat, 5),
                "lo": round(lng, 5),
                "_tx": [],
                "_rent": [],
            },
        )

    for row in tx_rows:
        p = entry(row)
        if p is None:
            continue
        for t in row.get("transaction") or []:
            ym = _mmyy(t.get("contractDate"))
            try:
                price, sqm = float(t["price"]), float(t["area"])
            except (KeyError, TypeError, ValueError):
                continue
            if not ym or sqm <= 0 or int(t.get("noOfUnits") or 1) != 1:
                continue
            p["_tx"].append((ym, price, sqm, t.get("floorRange", "-"), t))

    for row in rent_rows:
        p = entry(row)
        if p is None:
            continue
        for r in row.get("rental") or []:
            try:
                rent = float(r["rent"])
            except (KeyError, TypeError, ValueError):
                continue
            beds = str(r.get("noOfBedRoom") or "NA")
            p["_rent"].append((beds, rent))

    now = (today.year, today.month)

    def months_ago(ym: tuple[int, int]) -> int:
        return (now[0] - ym[0]) * 12 + now[1] - ym[1]

    out = []
    for p in projects.values():
        tx = sorted(p.pop("_tx"), key=lambda x: x[0], reverse=True)
        rents = p.pop("_rent")
        if not tx and not rents:
            continue
        if tx:
            recent = [x for x in tx if months_ago(x[0]) <= 12] or [
                x for x in tx if months_ago(x[0]) <= 36
            ]
            if recent:
                p["psf"] = round(statistics.median(x[1] / (x[2] * SQM_TO_SQFT) for x in recent))
                p["pc"] = len(recent)
            last = tx[0][4]
            p["ten"] = str(last.get("tenure", ""))
            p["pt"] = str(last.get("propertyType", ""))
            p["tx"] = [
                [f"{ym[0]}-{ym[1]:02d}", int(price), round(sqm), floor]
                for ym, price, sqm, floor, _ in tx[:5]
            ]
        if rents:
            by_beds: dict[str, list[float]] = {}
            for beds, rent in rents:
                by_beds.setdefault(beds, []).append(rent)
            p["rent"] = {b: round(statistics.median(v)) for b, v in sorted(by_beds.items())}
            p["rc"] = len(rents)
        out.append(p)
    return out


async def build_private(client: httpx.AsyncClient, access_key: str | None, today: date) -> list:
    ura = Ura(client, access_key)
    await ura.login()
    tx: list[dict] = []
    for batch in (1, 2, 3, 4):
        tx += await ura.service("PMI_Resi_Transaction", batch=batch)
    rents: list[dict] = []
    for q in last_quarters(today):
        try:
            rents += await ura.service("PMI_Resi_Rental", refPeriod=q)
        except (httpx.HTTPError, RuntimeError) as e:  # a quarter may not be published yet
            log.warning("URA rental %s: %s", q, e)
    return compact_private(tx, rents, today)
