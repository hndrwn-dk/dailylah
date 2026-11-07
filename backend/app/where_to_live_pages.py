"""Static "Living in <town>" pages for dailylah.sg, from web/data/where-to-live.json.

Run weekly by the push job of .github/workflows/where-to-live.yml (scripts/push_data.sh
--generate, main's own copy of this file, the runner's python3: stdlib only, keep it so):
    cd backend && python3 -m app.where_to_live_pages ../web

Writes, only when the content changed:
    web/where-to-live-towns/<town id>.html   one page per HDB town (served at /where-to-live/<id>)
    web/where-to-live-towns/index.html       all towns (served at /where-to-live/towns)
    web/sitemap.xml
The rewrites from /where-to-live/... live in web/vercel.json, so the pages share the tool's CSP.
The folder holds generated HTML only: the build job's patch may not touch it or the sitemap
(scripts/push_data.sh allowlist); only this generator, run in the push job, writes them. Every value from the JSON goes through html.escape,
and no page has a script of its own (only /shared/cta.js).
"""

import html
import json
import math
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

SITE = "https://dailylah.sg"
TOWNS_DIR = "where-to-live-towns"
WORKDAYS = 22  # working days in a month, there and back each day
FLAT_ORDER = ["1-ROOM", "2-ROOM", "3-ROOM", "4-ROOM", "5-ROOM", "EXECUTIVE"]
FLAT_LABEL = {
    "1-ROOM": "1-room",
    "2-ROOM": "2-room",
    "3-ROOM": "3-room",
    "4-ROOM": "4-room",
    "5-ROOM": "5-room",
    "EXECUTIVE": "Executive",
}
ORDINAL = {1: "st", 2: "nd", 3: "rd"}


def e(value: Any) -> str:
    return html.escape(str(value), quote=True)


def ordinal(n: int) -> str:
    suffix = "th" if 10 <= n % 100 <= 20 else ORDINAL.get(n % 10, "th")
    return f"{n}{suffix}"


def money(cents_or_dollars: int, cents: bool = False) -> str:
    if cents:
        return f"${cents_or_dollars / 100:,.2f}"
    return f"${cents_or_dollars:,}"


def quarter(q: Any) -> str:
    s = str(q or "")
    return f"Q{s[-1]} {s[:4]}" if len(s) == 7 and s[4:6] == "-Q" else ""


def monthly(commute: dict | None) -> tuple[int | None, int | None]:
    """(fare per month in cents, hours on the road per month) for a weekday return trip.
    Same area counts as 0 and 0; unknown parts are None."""
    if not commute:
        return None, None
    if commute.get("same_area"):
        return 0, 0
    fare = commute.get("fare")
    fares = fare * 2 * WORKDAYS if isinstance(fare, int) else None
    hours = (
        round(commute["min"] * 2 * WORKDAYS / 60) if isinstance(commute.get("min"), int) else None
    )
    return fares, hours


def distance_km(a: dict, b: dict) -> float:
    p = math.pi / 180
    h = (
        math.sin((b["lat"] - a["lat"]) * p / 2) ** 2
        + math.cos(a["lat"] * p)
        * math.cos(b["lat"] * p)
        * math.sin((b["lng"] - a["lng"]) * p / 2) ** 2
    )
    return 12742 * math.asin(math.sqrt(h))


def nearest(towns: list[dict], town: dict, k: int = 3) -> list[dict]:
    others = [t for t in towns if t["id"] != town["id"]]
    return sorted(others, key=lambda t: (distance_km(town, t), t["id"]))[:k]


def median(values: list[float]) -> float | None:
    v = sorted(values)
    if not v:
        return None
    mid = len(v) // 2
    return v[mid] if len(v) % 2 else (v[mid - 1] + v[mid]) / 2


def main_flat(town: dict, kind: str) -> str | None:
    """4-room if the town has a figure for it, else the most common type with one."""
    for flat in ("4-ROOM", "3-ROOM", "5-ROOM", "EXECUTIVE", "2-ROOM", "1-ROOM"):
        if (town.get(kind) or {}).get(flat):
            return flat
    return None


def rank_words(rank: int, of: int) -> str:
    if rank == 1:
        return "the quickest"
    if rank == of:
        return "the slowest"
    return f"the {ordinal(rank)} quickest"


def cbd_area(data: dict) -> dict:
    return next((a for a in data["areas"] if a["id"] == "cbd"), data["areas"][0])


def cbd_rank(data: dict, town: dict) -> tuple[int, int] | None:
    """(rank, of how many) of the town's minutes to the CBD; same area counts as 0."""
    area = cbd_area(data)["id"]

    def minutes(t: dict) -> float | None:
        c = (t.get("commute") or {}).get(area)
        if not c:
            return None
        return 0 if c.get("same_area") else c.get("min")

    known = sorted(m for t in data["towns"] if (m := minutes(t)) is not None)
    mine = minutes(town)
    if mine is None:
        return None
    return known.index(mine) + 1, len(known)


# ---------------------------------------------------------------- text


def summary_sentences(data: dict, town: dict) -> list[str]:
    """Plain sentences built from this town's own figures (escaped later)."""
    move, prices = summary_parts(data, town)
    return move + prices


def summary_parts(data: dict, town: dict) -> tuple[list[str], list[str]]:
    """(sentences about getting around, sentences about prices), from this town's figures."""
    name = town["name"]
    out = []
    area = cbd_area(data)
    c = (town.get("commute") or {}).get(area["id"])
    rank = cbd_rank(data, town)
    if c and c.get("same_area"):
        out.append(f"{name} is itself the {area['name']} office area.")
    elif c and rank:
        transfers = (
            "no transfer"
            if c["transfers"] == 0
            else ("1 transfer" if c["transfers"] == 1 else f"{c['transfers']} transfers")
        )
        out.append(
            f"From {town['station']} MRT, {area['name']} is {c['min']} minutes away on a weekday "
            f"morning with {transfers}, {rank_words(*rank)} of {rank[1]} HDB towns."
        )
    trips = [
        (a, (town.get("commute") or {}).get(a["id"]))
        for a in data["areas"]
        if a["id"] != area["id"]
    ]
    trips = [(a, t) for a, t in trips if t]
    same = [a for a, t in trips if t.get("same_area")]
    timed = sorted(((t["min"], a["name"]) for a, t in trips if not t.get("same_area")))
    if same:
        out.append(f"It is itself the {same[0]['name']} office area.")
    elif timed:
        out.append(
            f"Of the other office areas, {timed[0][1]} is the closest at {timed[0][0]} minutes."
        )
    fares, hours = monthly(c)
    if hours:
        cost = f" and about {money(round(fares / 100))} in fares" if fares else ""
        out.append(
            f"A weekday commute to {area['name']} adds up to about {hours} hours a month "
            f"on the road{cost}."
        )
    move, out = out, []
    rents = [(cell["median"], flat) for flat, cell in (town.get("rent") or {}).items() if cell]
    if len(rents) > 1:
        low, flat = min(rents)
        out.append(
            f"The lowest median rent here is for a {FLAT_LABEL[flat]} flat, {money(low)} a month."
        )
    out.extend(neighbour_sentence(data, town))
    for kind, what in (("rent", "rent"), ("resale", "resale price")):
        flat = main_flat(town, kind)
        if not flat:
            out.append(f"HDB published no median {what} for {name} in the last four quarters.")
            continue
        cell = town[kind][flat]
        others = [t[kind][flat]["median"] for t in data["towns"] if (t.get(kind) or {}).get(flat)]
        mid = median(others)
        unit = " a month" if kind == "rent" else ""
        sentence = (
            f"The {FLAT_LABEL[flat]} median {what} is {money(cell['median'])}{unit} "
            f"({quarter(cell['quarter'])})"
        )
        if mid is not None and len(others) > 1:
            diff = round(cell["median"] - mid)
            if diff == 0:
                sentence += f", the same as the median of {len(others)} towns"
            else:
                side = "above" if diff > 0 else "below"
                sentence += f", {money(abs(diff))} {side} the median of {len(others)} towns"
        out.append(sentence + ".")
    return move, out


def summary_paragraphs(data: dict, town: dict) -> tuple[list[str], list[str]]:
    """The summary in two paragraphs: getting around (minutes, hours) and prices."""
    move, prices = summary_parts(data, town)
    return move, prices


def neighbour_sentence(data: dict, town: dict) -> list[str]:
    """How the nearest town compares: minutes to the CBD and the main flat type's rent."""
    near = nearest(data["towns"], town, 1)
    if not near:
        return []
    other = near[0]
    area = cbd_area(data)["id"]
    parts = []
    mine, theirs = (town.get("commute") or {}).get(area), (other.get("commute") or {}).get(area)
    if mine and theirs and not mine.get("same_area") and not theirs.get("same_area"):
        d = mine["min"] - theirs["min"]
        if d:
            parts.append(f"{abs(d)} minutes {'longer' if d > 0 else 'shorter'} to the CBD")
        else:
            parts.append("the same time to the CBD")
    flat = main_flat(town, "rent")
    if flat and (other.get("rent") or {}).get(flat):
        d = town["rent"][flat]["median"] - other["rent"][flat]["median"]
        if d:
            parts.append(
                f"{FLAT_LABEL[flat]} rent {money(abs(d))} {'higher' if d > 0 else 'lower'}"
            )
        else:
            parts.append(f"the same {FLAT_LABEL[flat]} rent")
    if not parts:
        return []
    km = distance_km(town, other)
    return [f"Compared with {other['name']}, {km:.1f} km away: " + " and ".join(parts) + "."]


# ---------------------------------------------------------------- html


def head(title: str, description: str, path: str) -> str:
    url = f"{SITE}{path}"
    return f"""<!doctype html>
<html lang="en-SG">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title>
<meta name="description" content="{e(description)}">
<meta name="theme-color" content="#E8F3F6" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0B1214" media="(prefers-color-scheme: dark)">
<meta name="color-scheme" content="light dark">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(description)}">
<meta property="og:url" content="{e(url)}">
<meta property="og:image" content="{SITE}/brand/og.jpg">
<link rel="canonical" href="{e(url)}">
<link rel="icon" href="/favicon.png" sizes="32x32">
<link rel="apple-touch-icon" href="/brand/apple-touch-icon.png">
<link rel="preload" href="/fonts/BarlowCondensed-Bold.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/where-to-live/app.css">
<script type="module" src="/shared/cta.js"></script>
</head>
<body>
<main class="wrap town-page">
  <header class="top">
    <a class="home" href="/"><img src="/brand/wordmark.png" width="383" height="266" alt="DailyLah home"></a>
  </header>
"""


def tail(data: dict) -> str:
    updated = ""
    try:
        when = datetime.fromisoformat(str(data["generated_at"]).replace("Z", "+00:00"))
        updated = f" Updated {when.day} {when.strftime('%b %Y')}."
    except (KeyError, ValueError):
        pass
    return f"""  <section class="app sticker">
    <h2>Know before you go lah.</h2>
    <p>DailyLah, our free Android app, shows bus arrivals, MRT delays and the weather for your own trip to work.</p>
    <div class="cta" data-cta>
      <noscript><p>Turn on JavaScript to see how to get DailyLah on Google Play.</p></noscript>
    </div>
  </section>

  <footer class="notes">
    <p id="sources">Indicative figures from HDB via data.gov.sg (Singapore Open Data Licence) and planned trips from OneMap (Singapore Land Authority).{e(updated)}</p>
    <nav aria-label="Legal">
      <a href="/">DailyLah</a>
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
    </nav>
  </footer>
</main>
</body>
</html>
"""


def commute_rows(data: dict, town: dict) -> str:
    rows = []
    for area in data["areas"]:
        c = (town.get("commute") or {}).get(area["id"])
        fares, hours = monthly(c)
        if not c:
            time, fare, month = "No route data", "–", "–"
        elif c.get("same_area"):
            time, fare, month = "In this area", "–", "–"
        else:
            t = c["transfers"]
            time = f"{c['min']} min, " + (
                "no transfer" if t == 0 else "1 transfer" if t == 1 else f"{t} transfers"
            )
            fare = money(c["fare"], cents=True) if isinstance(c.get("fare"), int) else "–"
            month = f"{hours} h" + (f", {money(round(fares / 100))}" if fares else "")
        rows.append(
            f'        <tr><th scope="row">{e(area["name"])}</th><td>{e(time)}</td>'
            f"<td>{e(fare)}</td><td>{e(month)}</td></tr>"
        )
    return "\n".join(rows)


def price_rows(town: dict) -> str:
    rows = []
    for flat in FLAT_ORDER:
        rent, resale = (town.get("rent") or {}).get(flat), (town.get("resale") or {}).get(flat)
        if not rent and not resale:
            continue

        def cell(c: dict | None, unit: str = "") -> str:
            return (
                f"{money(c['median'])}{unit} ({quarter(c['quarter'])})" if c else "Not enough data"
            )

        rows.append(
            f'        <tr><th scope="row">{e(FLAT_LABEL[flat])}</th>'
            f"<td>{e(cell(rent, '/month'))}</td><td>{e(cell(resale))}</td></tr>"
        )
    return "\n".join(rows)


def link_list(towns: list[dict], origin: dict | None = None) -> str:
    links = [
        f'<a href="/where-to-live/{e(t["id"])}">{e(t["name"])}</a>'
        + (f" ({distance_km(origin, t):.1f} km)" if origin else "")
        for t in towns
    ]
    if len(links) <= 1:
        return "".join(links)
    return ", ".join(links[:-1]) + " and " + links[-1]


def town_page(data: dict, town: dict) -> str:
    name = town["name"]
    area = cbd_area(data)
    c = (town.get("commute") or {}).get(area["id"])
    flat = main_flat(town, "rent")
    bits = []
    if c and c.get("same_area"):
        bits.append(f"in the {area['name']} office area")
    elif c:
        bits.append(f"{c['min']} min to {area['name']} by MRT and bus")
    if flat:
        cell = town["rent"][flat]
        bits.append(
            f"{FLAT_LABEL[flat]} median rent {money(cell['median'])}/month ({quarter(cell['quarter'])})"
        )
    description = (
        f"{name}, Singapore: {', '.join(bits) or 'HDB town'}. Travel times to six office areas and "
        "HDB median rent and resale prices by flat type."
    )
    title = f"Living in {name}: commute and HDB prices | DailyLah"
    getting_around, prices = summary_paragraphs(data, town)
    nearby = nearest(data["towns"], town)
    return (
        head(title, description, f"/where-to-live/{town['id']}")
        + f"""
  <section class="intro">
    <h1>Living in {e(name)}</h1>
    <p class="lead">{" ".join(e(s) for s in getting_around)}</p>
    <p class="lead">{" ".join(e(s) for s in prices)}</p>
    <p><a class="go-tool" href="/where-to-live?town={e(town["id"])}">Compare {e(name)} with other towns</a></p>
  </section>

  <section class="sticker facts" aria-labelledby="commute-title">
    <h2 id="commute-title">Getting to work from {e(name)}</h2>
    <div class="table-wrap">
    <table>
      <caption>From {e(town["station"])} MRT, weekday 08:30</caption>
      <thead><tr><th scope="col">Office area</th><th scope="col">Time</th><th scope="col">Fare</th><th scope="col">A month</th></tr></thead>
      <tbody>
{commute_rows(data, town)}
      </tbody>
    </table>
    </div>
    <p class="note">Fare: adult card fare per trip. A month: hours on the road and fares, {WORKDAYS} working days there and back.</p>
  </section>

  <section class="sticker facts" aria-labelledby="price-title">
    <h2 id="price-title">HDB prices in {e(name)}</h2>
    <div class="table-wrap">
    <table>
      <caption>By flat type, with the quarter of each figure</caption>
      <thead><tr><th scope="col">Flat type</th><th scope="col">Median rent</th><th scope="col">Median resale</th></tr></thead>
      <tbody>
{price_rows(town)}
      </tbody>
    </table>
    </div>
  </section>

  <section class="nearby">
    <h2>Towns near {e(name)}</h2>
    <p>{link_list(nearby, town)}. <a href="/where-to-live/towns">All HDB towns</a>.</p>
  </section>

"""
        + tail(data)
    )


def index_page(data: dict) -> str:
    area = cbd_area(data)
    items = []
    for town in sorted(data["towns"], key=lambda t: t["name"]):
        c = (town.get("commute") or {}).get(area["id"])
        flat = main_flat(town, "rent")
        bits = []
        if c and c.get("same_area"):
            bits.append(f"in {area['name']}")
        elif c:
            bits.append(f"{c['min']} min to {area['name']}")
        if flat:
            bits.append(f"{FLAT_LABEL[flat]} rent {money(town['rent'][flat]['median'])}/month")
        items.append(
            f'      <li><a href="/where-to-live/{e(town["id"])}">{e(town["name"])}</a>'
            f"<span>{e(', '.join(bits))}</span></li>"
        )
    description = (
        f"All {len(data['towns'])} HDB towns in Singapore with MRT and bus time to "
        f"{area['name']} and HDB median rent."
    )
    return (
        head(
            "HDB towns in Singapore: commute and prices | DailyLah",
            description,
            "/where-to-live/towns",
        )
        + f"""
  <section class="intro">
    <h1>HDB towns</h1>
    <p class="lead">Every HDB town with its MRT and bus time to {e(area["name"])} and its HDB median rent. Open a town for all six office areas and every flat type.</p>
    <p><a class="go-tool" href="/where-to-live">Rank towns for your office and budget</a></p>
  </section>

  <section class="sticker facts">
    <ul class="town-list">
{chr(10).join(items)}
    </ul>
  </section>

"""
        + tail(data)
    )


def sitemap(data: dict) -> str:
    try:
        lastmod = str(data["generated_at"])[:10]
    except KeyError:
        lastmod = ""
    paths = ["/", "/where-to-live", "/where-to-live/towns"] + [
        f"/where-to-live/{t['id']}" for t in sorted(data["towns"], key=lambda t: t["id"])
    ]
    mod = f"<lastmod>{e(lastmod)}</lastmod>" if lastmod else ""
    urls = "\n".join(f"  <url><loc>{e(SITE + p)}</loc>{mod}</url>" for p in paths)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{urls}\n</urlset>\n"
    )


# ---------------------------------------------------------------- write


def _write(path: Path, text: str) -> bool:
    try:
        if path.read_text() == text:
            return False
    except OSError:
        pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return True


def build(data: dict, web_dir: Path) -> dict[str, int]:
    """Writes the pages and the sitemap; returns counts of written, unchanged and removed files."""
    out_dir = web_dir / TOWNS_DIR
    files = {out_dir / f"{t['id']}.html": town_page(data, t) for t in data["towns"]}
    files[out_dir / "index.html"] = index_page(data)
    files[web_dir / "sitemap.xml"] = sitemap(data)
    written = sum(_write(p, text) for p, text in files.items())
    removed = 0
    for old in out_dir.glob("*.html"):
        if old not in files:
            old.unlink()
            removed += 1
    return {"written": written, "unchanged": len(files) - written, "removed": removed}


def main(web_dir: Path) -> int:
    data = json.loads((web_dir / "data" / "where-to-live.json").read_text())
    counts = build(data, web_dir)
    print(f"where-to-live pages: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "../web")))
