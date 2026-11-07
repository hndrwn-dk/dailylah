// Run: node --test web/tests/   (CI: .github/workflows/web.yml)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { CTA } from "../shared/cta.js";
import {
  commuteText,
  flatTypes,
  pillText,
  priceDetail,
  priceLine,
  quarterLabel,
  rank,
  reasonText,
  readQuery,
  routeDetail,
  shortPrice,
  timeBand,
  writeQuery,
} from "../where-to-live/logic.js";

const web = new URL("../", import.meta.url);
const read = (path) => readFileSync(new URL(path, web), "utf8");

const cell = (median, quarter = "2026-Q3") => ({ median, quarter });
const DATA = {
  generated_at: "2026-11-07T13:39:45Z",
  rent_quarter: "2026-Q3",
  resale_quarter: "2026-Q2",
  areas: [
    { id: "cbd", name: "CBD (Raffles Place)", station: "Raffles Place", lat: 1.28, lng: 103.85 },
    { id: "jurong-east", name: "Jurong East", station: "Jurong East", lat: 1.33, lng: 103.74 },
  ],
  towns: [
    {
      id: "bishan", name: "Bishan", station: "Bishan", lat: 1.35, lng: 103.85,
      rent: { "3-ROOM": cell(3000), "4-ROOM": cell(3700) },
      resale: { "4-ROOM": cell(700000, "2026-Q2") },
      commute: { cbd: { min: 20, transfers: 0 }, "jurong-east": { min: 40, transfers: 1 } },
    },
    {
      id: "punggol", name: "Punggol", station: "Punggol", lat: 1.4, lng: 103.9,
      rent: { "3-ROOM": cell(2850), "4-ROOM": cell(3300, "2026-Q1") },
      resale: { "4-ROOM": cell(610000, "2026-Q2") },
      commute: { cbd: { min: 45, transfers: 1 }, "jurong-east": { min: 70, transfers: 2 } },
    },
    {
      id: "jurong-east", name: "Jurong East", station: "Jurong East", lat: 1.33, lng: 103.74,
      rent: { "3-ROOM": cell(2700), "4-ROOM": null },
      resale: { "4-ROOM": cell(560000, "2026-Q2") },
      commute: { cbd: { min: 35, transfers: 0 }, "jurong-east": { min: null, transfers: null, same_area: true } },
    },
    {
      id: "central", name: "Central Area", station: "Tanjong Pagar", lat: 1.27, lng: 103.84,
      rent: { "3-ROOM": cell(3500), "4-ROOM": cell(4200) },
      resale: {},
      commute: { cbd: null, "jurong-east": { min: 30, transfers: 0 } },
    },
  ],
};
const state = (over = {}) => ({ area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null, ...over });
const ids = (rows) => rows.map((r) => r.town.id);

// ---------------------------------------------------------------- URL

test("readQuery keeps known values", () => {
  assert.deepEqual(readQuery("?area=jurong-east&mode=buy&flat=4-ROOM&budget=650000&max=45", DATA), {
    area: "jurong-east", mode: "buy", flat: "4-ROOM", budget: 650000, max: 45,
  });
});

test("readQuery replaces unknown or hostile values with defaults", () => {
  const s = readQuery(
    "?area=<script>&mode=steal&flat=9-ROOM&budget=-5&max=44&extra=1",
    DATA,
  );
  assert.deepEqual(s, { area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null });
  assert.equal(readQuery("?budget=1e9", DATA).budget, null);
  assert.equal(readQuery("?budget=3500abc", DATA).budget, null);
  assert.equal(readQuery("?budget=999999999", DATA).budget, null); // over the rent limit
});

test("readQuery picks a flat type that has prices for the mode", () => {
  // No 3-room resale prices in the data: buy mode falls back to 4-room.
  assert.equal(readQuery("?mode=buy&flat=3-ROOM", DATA).flat, "4-ROOM");
  assert.deepEqual(flatTypes(DATA, "rent"), ["3-ROOM", "4-ROOM"]);
  assert.deepEqual(flatTypes(DATA, "buy"), ["4-ROOM"]);
});

test("writeQuery leaves defaults out and round-trips", () => {
  assert.equal(writeQuery(state()), "");
  const s = state({ area: "jurong-east", budget: 3500, max: 60 });
  assert.equal(writeQuery(s), "?area=jurong-east&budget=3500&max=60");
  assert.deepEqual(readQuery(writeQuery(s), DATA), s);
});

// ---------------------------------------------------------------- labels

test("price labels use the quarter of each figure", () => {
  const punggol = DATA.towns[1];
  assert.equal(priceLine(state(), punggol.rent["4-ROOM"]), "4-room median rent $3,300/month (Q1 2026)");
  assert.equal(
    priceLine(state({ mode: "buy" }), punggol.resale["4-ROOM"]),
    "4-room median resale $610,000 (Q2 2026)",
  );
  assert.equal(priceLine(state(), null), "4-room median rent: not enough data");
  assert.equal(quarterLabel("2026-Q3"), "Q3 2026");
  assert.equal(quarterLabel("junk"), "");
});

test("board row: short price, details with station, transfers and the figure's own quarter", () => {
  const punggol = DATA.towns[1];
  assert.equal(shortPrice("rent", punggol.rent["4-ROOM"]), "$3,300/mo");
  assert.equal(shortPrice("buy", punggol.resale["4-ROOM"]), "$610,000");
  assert.equal(shortPrice("rent", null), "No data");
  const row = { town: punggol, commute: punggol.commute.cbd };
  assert.equal(routeDetail(row), "From Punggol MRT, 1 transfer");
  assert.equal(priceDetail(state(), punggol.rent["4-ROOM"]), "4-room median rent, Q1 2026");
  assert.equal(priceDetail(state({ mode: "buy" }), null), "4-room median resale price: not enough data");
  const je = DATA.towns[2];
  assert.equal(routeDetail({ town: je, commute: je.commute["jurong-east"] }), "In this area (Jurong East MRT)");
  assert.equal(routeDetail({ town: je, commute: null }), "No route data");
});

test("map pills: minutes, bands by travel time", () => {
  assert.equal(pillText({ min: 22, transfers: 0 }), "22′");
  assert.equal(pillText({ min: null, transfers: null, same_area: true }), "Here");
  assert.equal(pillText(null), "–");
  const band = (min) => timeBand({ min, transfers: 0 });
  assert.deepEqual([band(5), band(20), band(21), band(35), band(36), band(50), band(51), band(90)], [1, 1, 2, 2, 3, 3, 4, 4]);
  assert.equal(timeBand({ min: null, transfers: null, same_area: true }), 0);
  assert.equal(timeBand(null), null);
});

test("commute labels", () => {
  assert.equal(commuteText({ min: 38, transfers: 1 }), "38 min, 1 transfer");
  assert.equal(commuteText({ min: 20, transfers: 0 }), "20 min, no transfer");
  assert.equal(commuteText({ min: 55, transfers: 2 }), "55 min, 2 transfers");
  assert.equal(commuteText({ min: null, transfers: null, same_area: true }), "In this area");
  assert.equal(commuteText(null), "No route data");
});

// ---------------------------------------------------------------- ranking

test("no limits: every town with a route fits, sorted by time", () => {
  const g = rank(DATA, state());
  assert.deepEqual(ids(g.match), ["bishan", "jurong-east", "punggol"]);
  assert.deepEqual(ids(g.other), ["central"]); // no route data
  assert.deepEqual(g.noPrice, []);
});

test("same area comes first", () => {
  const g = rank(DATA, state({ area: "jurong-east", flat: "3-ROOM" }));
  assert.deepEqual(ids(g.match), ["jurong-east", "central", "bishan", "punggol"]);
  assert.equal(g.match[0].minutes, 0);
});

test("budget and travel time limits", () => {
  const g = rank(DATA, state({ budget: 3500, max: 40 }));
  assert.deepEqual(ids(g.match), []); // Bishan over budget, Punggol too far
  assert.deepEqual(ids(g.noPrice), ["jurong-east"]); // 4-room rent is null
  assert.deepEqual(ids(g.other), ["bishan", "punggol", "central"]);
  const g2 = rank(DATA, state({ budget: 3800, max: 45 }));
  assert.deepEqual(ids(g2.match), ["bishan", "punggol"]);
});

test("rows outside the choices say why", () => {
  const s = state({ budget: 3500, max: 40 });
  const g = rank(DATA, s);
  const why = Object.fromEntries(g.other.map((r) => [r.town.id, reasonText(r, s)]));
  assert.deepEqual(why, { bishan: "Over your budget", punggol: "Over 40 min", central: "No route data" });
  assert.equal(reasonText(g.noPrice[0], s), "");
});

test("a missing price never counts as within budget", () => {
  const g = rank(DATA, state({ mode: "buy", budget: 2_000_000 }));
  assert.ok(!ids(g.match).includes("central"));
});

// ---------------------------------------------------------------- the real file and the page

test("the published where-to-live.json ranks without errors", () => {
  const data = JSON.parse(read("data/where-to-live.json"));
  assert.equal(data.towns.length, 26);
  for (const area of data.areas) {
    const g = rank(data, { area: area.id, mode: "rent", flat: "4-ROOM", budget: null, max: null });
    assert.equal(g.match.length + g.noPrice.length + g.other.length, 26);
  }
});

test("page scripts never write HTML from strings", () => {
  for (const file of ["where-to-live/app.js", "where-to-live/logic.js", "shared/cta.js"]) {
    const src = read(file).replace(/^\s*\/\/.*$/gm, "");
    assert.doesNotMatch(src, /\.innerHTML|\.outerHTML|insertAdjacentHTML|document\.write/, file);
  }
});

test("the Play link and its steps live only in shared/cta.js", () => {
  assert.match(CTA.url, /^https:\/\/play\.google\.com\//);
  assert.ok(CTA.label.length > 0);
  for (const page of ["index.html", "where-to-live/index.html"]) {
    const html = read(page);
    assert.doesNotMatch(html, /play\.google\.com|groups\.google\.com/, page);
    assert.match(html, /data-cta/, page);
    assert.match(html, /src="\/shared\/cta\.js"/, page);
  }
});

test("the landing page hero and tagline stay as they are", () => {
  const html = read("index.html");
  assert.match(html, /<h1>Know before you go lah\.<\/h1>/);
  for (const line of [
    "Need umbrella meh? Hawker closed ah?",
    "Haze bad or not? Makan where?",
    "Bus coming? MRT delay? Alamak...",
  ]) {
    assert.ok(html.includes(`<li>${line}</li>`), line);
  }
  // The hero still comes first; the Where to live? teaser sits after the tabs.
  assert.ok(html.indexOf('class="hero"') < html.indexOf('class="tool sticker"'));
});

test("where-to-live keeps Singlish to the light copy", () => {
  const html = read("where-to-live/index.html");
  assert.match(html, /Stay where ah\? Pick your office and budget, we rank every HDB town by MRT time lah\./);
  assert.match(html, /<h2>Know before you go lah\.<\/h2>/);
  assert.match(read("where-to-live/app.js"), /Alamak, nothing fits\. Try a bigger budget or longer travel time\./);
  // Disclaimer stays standard English.
  assert.match(html, /Figures are indicative\./);
});

test("the page loads Leaflet from the vendored copy only", () => {
  const html = read("where-to-live/index.html");
  const srcs = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
  for (const s of srcs.filter((s) => /\.(js|css)$/.test(s))) assert.match(s, /^\//, s);
});
