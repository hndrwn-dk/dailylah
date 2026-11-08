import copy
import html
import itertools
import json
import re
import xml.etree.ElementTree as ET  # noqa: S405 - parses the sitemap we just wrote
from pathlib import Path

import pytest

from app import where_to_live_pages as p

WEB = Path(__file__).resolve().parents[2] / "web"
REAL = json.loads((WEB / "data" / "where-to-live.json").read_text())


def with_fares(data: dict) -> dict:
    """The real file, with fares as OneMap gives them (the first build after Phase 3 adds them)."""
    d = copy.deepcopy(data)
    for t in d["towns"]:
        for c in t["commute"].values():
            if c and not c.get("same_area"):
                c["fare"] = 100 + c["min"] * 3
    return d


def visible_words(page: str) -> list[str]:
    body = page[page.index("<main") : page.index('<section class="app')]
    return html.unescape(re.sub(r"<[^>]+>", " ", body)).split()


def test_monthly_fares_and_hours():
    assert p.monthly({"min": 36, "transfers": 1, "fare": 194}) == (194 * 44, 26)
    assert p.monthly({"min": 30, "transfers": 0, "fare": None}) == (None, 22)
    assert p.monthly({"min": None, "transfers": None, "same_area": True}) == (0, 0)
    assert p.monthly(None) == (None, None)


def test_build_writes_every_town_the_index_and_the_sitemap(tmp_path):
    data = with_fares(REAL)
    counts = p.build(data, tmp_path)
    pages = sorted((tmp_path / p.TOWNS_DIR).glob("*.html"))
    assert len(pages) == len(data["towns"]) + 1  # + index.html
    assert counts == {"written": len(pages) + 1, "unchanged": 0, "removed": 0}
    # A second build with the same data changes nothing (no weekly commit).
    assert p.build(data, tmp_path)["written"] == 0
    root = ET.fromstring((tmp_path / "sitemap.xml").read_text())  # noqa: S314 - our own output
    locs = [el.text for el in root.iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")]
    assert "https://dailylah.sg/where-to-live/punggol" in locs
    assert len(locs) == len(data["towns"]) + 3


def test_removed_town_page_is_deleted(tmp_path):
    data = with_fares(REAL)
    p.build(data, tmp_path)
    smaller = copy.deepcopy(data)
    smaller["towns"] = [t for t in smaller["towns"] if t["id"] != "punggol"]
    assert p.build(smaller, tmp_path)["removed"] == 1
    assert not (tmp_path / p.TOWNS_DIR / "punggol.html").exists()


def test_town_page_content():
    data = with_fares(REAL)
    punggol = next(t for t in data["towns"] if t["id"] == "punggol")
    page = p.town_page(data, punggol)
    text = " ".join(visible_words(page))
    assert "<title>Living in Punggol: commute and HDB prices | DailyLah</title>" in page
    assert '<link rel="canonical" href="https://dailylah.sg/where-to-live/punggol">' in page
    assert 'href="/where-to-live?town=punggol"' in page
    assert "quickest of 26 HDB towns" in text
    assert "(Q3 2026)" in text  # each price carries its own quarter
    assert "Compared with Sengkang" in text
    assert "<script" not in page.replace('<script type="module" src="/shared/cta.js"></script>', "")
    # Same area: Woodlands to the Woodlands office area.
    woodlands = next(t for t in data["towns"] if t["id"] == "woodlands")
    assert "In this area" in p.town_page(data, woodlands)


def test_every_value_from_the_json_is_escaped():
    data = with_fares(REAL)
    evil = copy.deepcopy(data)
    t = evil["towns"][0]
    t["name"] = '<img src=x onerror="alert(1)">Evil'
    t["station"] = "</caption><script>alert(2)</script>"
    t["id"] = 'x" onmouseover="alert(3)'
    evil["areas"][0]["name"] = "<b>CBD</b>"
    pages = [p.town_page(evil, t), p.index_page(evil), p.sitemap(evil)]
    for page in pages:
        assert "<img src=x" not in page
        assert "<script>alert" not in page
        assert '" onmouseover=' not in page
        assert "<b>CBD</b>" not in page
    assert "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;Evil" in pages[0]


def test_town_pages_are_not_near_duplicates():
    """5-word shingle Jaccard between any two town pages stays well under near-duplicate levels."""
    data = with_fares(REAL)

    def shingles(words: list[str]) -> set:
        return {tuple(words[i : i + 5]) for i in range(len(words) - 4)}

    pages = {t["id"]: shingles(visible_words(p.town_page(data, t))) for t in data["towns"]}
    worst = max(
        (len(a & b) / len(a | b), x, y)
        for (x, a), (y, b) in itertools.combinations(pages.items(), 2)
    )
    assert worst[0] < 0.5, worst


def test_committed_pages_match_the_committed_json():
    """web/where-to-live-towns/ is generated: it must match web/data/where-to-live.json."""
    for t in REAL["towns"]:
        committed = (WEB / p.TOWNS_DIR / f"{t['id']}.html").read_text()
        assert committed == p.town_page(REAL, t), t["id"]
    assert (WEB / p.TOWNS_DIR / "index.html").read_text() == p.index_page(REAL)
    assert (WEB / "sitemap.xml").read_text() == p.sitemap(REAL)


def test_town_without_any_price_says_so():
    town = {"rent": {"3-ROOM": None}, "resale": {}}
    rows = p.price_rows(town)
    assert rows.count("<tr>") == 1
    assert 'colspan="3"' in rows and "no median rent or resale price" in rows


def test_dates_are_singapore_dates():
    # 20:00 UTC on 7 Nov is 04:00 on 8 Nov in Singapore.
    data = {**REAL, "generated_at": "2026-11-07T20:00:00Z"}
    assert "Updated 8 Nov 2026." in p.tail(data)
    assert "<lastmod>2026-11-08</lastmod>" in p.sitemap(data)
    assert "Updated" not in p.tail({**REAL, "generated_at": "not a date"})


def test_bad_town_ids_write_nothing(tmp_path):
    for bad in ["../evil", "/abs/x", "Punggol", "index", "a.b", 7]:
        data = copy.deepcopy(REAL)
        data["towns"][0]["id"] = bad
        with pytest.raises(ValueError, match="bad town id"):
            p.build(data, tmp_path)
        assert not any(tmp_path.rglob("*"))


def test_a_town_without_any_price_gets_one_sentence():
    data = copy.deepcopy(REAL)
    town = next(t for t in data["towns"] if t["id"] == "bukit-timah")
    town["rent"] = dict.fromkeys(town["rent"])
    town["resale"] = dict.fromkeys(town["resale"])
    _, prices = p.summary_parts(data, town)
    text = " ".join(prices)
    assert text.count("HDB published no median") == 1
    assert (
        "HDB published no median rent or resale price for Bukit Timah in the last four quarters."
        in prices
    )
    # Only one of the two missing: its own sentence, and the other figure is described.
    town["rent"]["4-ROOM"] = {"median": 3000, "quarter": "2026-Q3"}
    _, prices = p.summary_parts(data, town)
    assert "HDB published no median resale price for Bukit Timah in the last four quarters." in (
        prices
    )
    assert not any("rent or resale" in s for s in prices)


def png_size(path: Path) -> tuple[int, int]:
    head = path.read_bytes()[:24]
    assert head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR", path
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def test_every_town_has_a_share_image():
    """A town new to the data needs scripts/build_og_images.py run (docs/WHERE_TO_LIVE.md)."""
    folder = WEB / p.OG_DIR
    ids = {t["id"] for t in REAL["towns"]}
    assert {f.stem for f in folder.glob("*.png")} == ids
    for town_id in ids:
        assert png_size(folder / f"{town_id}.png") == (1200, 630), town_id


def test_every_town_page_points_at_its_share_image():
    for t in REAL["towns"]:
        page = (WEB / p.TOWNS_DIR / f"{t['id']}.html").read_text()
        src = f"/og/where-to-live/{t['id']}.png"
        assert f'<meta property="og:image" content="https://dailylah.sg{src}">' in page, t["id"]
        assert (WEB / src.lstrip("/")).is_file()
        assert '<meta property="og:image:width" content="1200">' in page
        assert '<meta property="og:image:height" content="630">' in page
        assert '<meta name="twitter:card" content="summary_large_image">' in page


def test_a_town_without_a_share_image_gets_the_site_image(tmp_path):
    p.build(REAL, tmp_path)
    page = (tmp_path / p.TOWNS_DIR / "punggol.html").read_text()
    assert '<meta property="og:image" content="https://dailylah.sg/brand/og.jpg">' in page
    assert '<meta property="og:image:width" content="1024">' in page
