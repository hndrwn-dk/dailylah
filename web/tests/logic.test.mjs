// Run: node --test 'web/tests/*.test.mjs'   (CI: .github/workflows/web.yml)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { CTA } from "../shared/cta.js";
import {
  changeChoices,
  commuteText,
  flatTypes,
  allInText,
  highlightText,
  monthlyCost,
  IN_AREA,
  MAX_COMPARE,
  compareBarText,
  compareIds,
  compareTable,
  namesText,
  toggleCompare,
  highlights,
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
const state = (over = {}) => ({
  area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null, town: null, compare: [], ...over,
});
const ids = (rows) => rows.map((r) => r.town.id);

// ---------------------------------------------------------------- URL

test("readQuery keeps known values", () => {
  assert.deepEqual(readQuery("?area=jurong-east&mode=buy&flat=4-ROOM&budget=650000&max=45", DATA), {
    area: "jurong-east", mode: "buy", flat: "4-ROOM", budget: 650000, max: 45, town: null, compare: [],
  });
});

test("?town= opens a town from the data only", () => {
  assert.equal(readQuery("?town=punggol", DATA).town, "punggol");
  assert.equal(readQuery("?town=nowhere", DATA).town, null);
  assert.equal(readQuery("?town=<img>", DATA).town, null);
  assert.equal(writeQuery(state({ town: "punggol" })), "?town=punggol");
});

test("readQuery replaces unknown or hostile values with defaults", () => {
  const s = readQuery(
    "?area=<script>&mode=steal&flat=9-ROOM&budget=-5&max=44&extra=1",
    DATA,
  );
  assert.deepEqual(s, { area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null, town: null, compare: [] });
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

test("changing rent/buy drops the budget; other changes keep it", () => {
  const rent = state({ budget: 3500 });
  assert.equal(changeChoices(rent, "?mode=buy&flat=4-ROOM&budget=3500", DATA).budget, null);
  assert.equal(changeChoices(rent, "?mode=rent&flat=3-ROOM&budget=3500", DATA).budget, 3500);
  const buy = state({ mode: "buy", budget: 650000 });
  assert.equal(changeChoices(buy, "?mode=rent&budget=650000", DATA).budget, null);
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

test("summary card: fastest and best value among towns that fit", () => {
  // CBD, 4-room rent, no limits: Bishan 20 min $3,700; Jurong East 35 min (no price); Punggol 45 min $3,300.
  const g = rank(DATA, state());
  const p = highlights(g);
  assert.equal(p.fastest.town.id, "bishan");
  assert.equal(highlightText(p.fastest, "rent"), "Bishan — 20 min, $3,700/mo");
  // Priced candidates: Bishan 20, Punggol 45 -> median 32.5, so only Bishan is at or under it.
  assert.equal(p.value.town.id, "bishan");
  // 3-room rent: Bishan 20 $3,000, Jurong East 35 $2,700, Punggol 45 $2,850 -> median 35:
  // Bishan and Jurong East qualify; Jurong East is cheaper.
  const p3 = highlights(rank(DATA, state({ flat: "3-ROOM" })));
  assert.equal(p3.fastest.town.id, "bishan");
  assert.equal(highlightText(p3.value, "rent"), "Jurong East — 35 min, $2,700/mo");
});

test("summary card: same area, resale wording, and hidden when nothing fits", () => {
  const p = highlights(rank(DATA, state({ area: "jurong-east", flat: "3-ROOM" })));
  assert.equal(highlightText(p.fastest, "rent"), "Jurong East — in this area, $2,700/mo");
  const buy = highlights(rank(DATA, state({ mode: "buy" })));
  assert.equal(highlightText(buy.fastest, "buy"), "Bishan — 20 min, $700,000");
  assert.equal(highlights(rank(DATA, state({ budget: 1000 }))), null);
  assert.equal(highlights(rank(DATA, state({ max: 30, flat: "4-ROOM", area: "jurong-east" })))?.fastest.town.id, "central");
});

test("monthly cost: rent plus fares there and back on 22 working days, and hours", () => {
  const row = { commute: { min: 36, transfers: 1, fare: 194 }, price: cell(3250) };
  // 194 cents x 2 x 22 = $85.36 -> $85; 36 min x 2 x 22 / 60 = 26.4 -> 26 h
  assert.deepEqual(monthlyCost(state(), row), { fares: 85, hours: 26, total: 3335, same: false });
  assert.equal(allInText(state(), row), "≈ $3,335/mo all-in with fares, 26 h on the road a month (estimate)");
  // Buy: fares and hours only.
  assert.equal(monthlyCost(state({ mode: "buy" }), row).total, null);
  assert.equal(allInText(state({ mode: "buy" }), row), "≈ $85/mo in fares, 26 h on the road a month (estimate)");
  // No fare from OneMap: hours only; no route: nothing.
  const noFare = { commute: { min: 30, transfers: 0, fare: null }, price: cell(3000) };
  assert.equal(allInText(state(), noFare), "22 h on the road a month (estimate)");
  assert.equal(allInText(state(), { commute: null, price: cell(3000) }), "");
  // Same area: no commute.
  const same = { commute: { min: null, transfers: null, same_area: true }, price: cell(3500) };
  assert.deepEqual(monthlyCost(state(), same), { fares: 0, hours: 0, total: 3500, same: true });
  assert.equal(allInText(state(), same), "In this area: no commute to pay for (estimate)");
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
  // Short label on the button (fits a 360 px phone), the full name for screen readers.
  assert.equal(CTA.label, "Join the beta");
  assert.ok(CTA.label.length <= 16, "button label must stay short");
  assert.equal(CTA.ariaLabel, "Join the beta on Google Play");
  assert.ok(CTA.ariaLabel.startsWith(CTA.label));
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
  // Each question may be wrapped in a <span class="q"> for the hero animation; the words stay.
  const asks = html.slice(html.indexOf('<ul class="asks">'), html.indexOf("</ul>", html.indexOf('<ul class="asks">')));
  const lines = [...asks.matchAll(/<li>(.*?)<\/li>/g)].map((m) => m[1].replace(/<[^>]+>/g, ""));
  assert.deepEqual(lines, [
    "Need umbrella meh? Hawker closed ah?",
    "Haze bad or not? Makan where?",
    "Bus coming? MRT delay? Alamak...",
  ]);
  // The hero still comes first; the Where to live? teaser sits after the tabs.
  assert.ok(html.indexOf('class="hero"') < html.indexOf('class="tool sticker"'));
});

test("where-to-live keeps Singlish to the light copy", () => {
  const html = read("where-to-live/index.html");
  assert.match(html, /Stay where ah\? Pick your office and budget, we rank every HDB town by MRT time lah\./);
  assert.match(html, /<h2>Know before you go lah\.<\/h2>/);
  assert.match(read("where-to-live/app.js"), /Alamak, nothing fits\. Try a bigger budget or longer travel time\./);
  // Footer and data notes stay standard English.
  assert.match(html, /Indicative figures from HDB via data\.gov\.sg \(Singapore Open Data Licence\)\./);
  assert.match(html, /<summary>About the data<\/summary>/);
  assert.match(html, /not affiliated with HDB or the Singapore Land Authority/);
});

test("footers are short and the full sources live in the Terms", () => {
  const home = read("index.html");
  const footer = home.slice(home.indexOf("<footer>"), home.indexOf("</footer>"));
  assert.match(footer, /Open data from data\.gov\.sg, LTA DataMall, OneMap and URA\. Not affiliated with the Singapore Government\./);
  assert.doesNotMatch(footer, /Muslim\.sg|MUIS/);
  const terms = readFileSync(new URL("../docs/legal/terms.md", web), "utf8");
  assert.match(terms, /Muslim\.sg: halal listings\. DailyLah is not affiliated with MUIS/);
  const wtl = read("where-to-live/index.html");
  const wtlFooter = wtl.slice(wtl.indexOf('<footer class="notes">'), wtl.indexOf("</footer>"));
  assert.doesNotMatch(wtlFooter, /OneMap.*Singapore Land Authority.*contributors/);
  assert.equal((wtlFooter.match(/<a /g) ?? []).length, 3);
});

test("home: one real screenshot per tab with size and alt, the day timeline and the questions", () => {
  const html = read("index.html");
  const imgs = [...html.matchAll(/<img src="\/brand\/screens\/([a-z-]+\.webp)"([^>]*)>/g)];
  assert.deepEqual(imgs.map((m) => m[1]), ["today.webp", "nearby.webp", "home.webp", "history.webp"]);
  const tabs = [...html.matchAll(/<figcaption><h3>([^<]+)<\/h3>/g)].map((m) => m[1]);
  assert.deepEqual(tabs, ["Today", "Nearby", "Home", "History"]);
  for (const [, file, attrs] of imgs) {
    assert.match(attrs, /width="540" height="960"/, file);
    assert.match(attrs, /alt="[^"]{20,}"/, file);
    const bytes = readFileSync(new URL(`brand/screens/${file}`, web));
    assert.equal(bytes.subarray(8, 12).toString(), "WEBP", file);
  }
  const day = html.slice(html.indexOf('class="timeline"'), html.indexOf("</ol>", html.indexOf('class="timeline"')));
  assert.equal((day.match(/<li>/g) ?? []).length, 8);
  // Questions in three groups; privacy answers keep the policy's limits (docs/legal/privacy.md).
  const faq = html.slice(html.indexOf('class="faq"'), html.indexOf("</section>", html.indexOf('class="faq"')));
  assert.deepEqual([...faq.matchAll(/<h3[^>]*>([^<]+)<\/h3>/g)].map((m) => m[1]), ["Getting DailyLah", "Privacy and safety", "Using it"]);
  assert.ok((faq.match(/<details>/g) ?? []).length >= 12);
  assert.match(faq, /bus stop code/);
  assert.match(faq, /Android backup/);
  assert.match(faq, /No contacts, photos, microphone or camera/);
  // The privacy card links to the privacy questions.
  assert.match(html, /<a href="#privacy">/);
  assert.match(faq, /<h3 id="privacy">Privacy and safety<\/h3>/);
  // History: only categories the app has (trips, parking, meals), and fares are called estimates.
  assert.match(html, /<h3>History<\/h3><p>[^<]*trips, parking and meals[^<]*estimated/);
  assert.doesNotMatch(html, /<span>MRT<\/span>|<span>Bus<\/span>/);
});

test("privacy and terms are English only, like the app", () => {
  for (const name of ["privacy", "terms"]) {
    const doc = readFileSync(new URL(`../docs/legal/${name}.md`, web), "utf8");
    assert.match(doc, /^\*\*Last updated: \d{1,2} [A-Z][a-z]+ \d{4}\*\*$/m, name);
    assert.doesNotMatch(doc, /Bahasa Indonesia|#bahasa-indonesia|Kebijakan|Ketentuan|Cakupan/, name);
    assert.match(doc, /^## 1\. Scope$/m, name);
  }
});

test("the page loads Leaflet from the vendored copy only", () => {
  const html = read("where-to-live/index.html");
  const srcs = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
  for (const s of srcs.filter((s) => /\.(js|css)$/.test(s))) assert.match(s, /^\//, s);
});

// ---------------------------------------------------------------- compare

test("?compare= keeps towns from the data, each once, in order, at most three", () => {
  assert.deepEqual(readQuery("?compare=punggol,bishan", DATA).compare, ["punggol", "bishan"]);
  assert.deepEqual(compareIds("punggol,punggol,nowhere,<img>,bishan", DATA), ["punggol", "bishan"]);
  assert.deepEqual(compareIds("punggol,bishan,central,jurong-east", DATA), ["punggol", "bishan", "central"]);
  assert.equal(MAX_COMPARE, 3);
  assert.deepEqual(compareIds("", DATA), []);
  assert.deepEqual(compareIds(null, DATA), []);
  assert.deepEqual(compareIds("Punggol, bishan", DATA), []); // ids are exact: no case or space fixing
  assert.deepEqual(readQuery("?compare=x&compare=punggol", DATA).compare, []); // the first value only
});

test("writeQuery writes ?compare= with plain commas and round-trips", () => {
  const s = state({ compare: ["punggol", "bishan", "central"] });
  assert.equal(writeQuery(s), "?compare=punggol,bishan,central");
  assert.deepEqual(readQuery(writeQuery(s), DATA).compare, ["punggol", "bishan", "central"]);
  assert.equal(writeQuery(state({ area: "jurong-east", compare: ["punggol"] })), "?area=jurong-east&compare=punggol");
  assert.equal(writeQuery(state()), "");
});

test("toggleCompare adds, removes and stops at three", () => {
  assert.deepEqual(toggleCompare([], "punggol"), ["punggol"]);
  assert.deepEqual(toggleCompare(["punggol", "bishan"], "punggol"), ["bishan"]);
  const full = ["punggol", "bishan", "central"];
  assert.equal(toggleCompare(full, "jurong-east"), full);
  assert.deepEqual(toggleCompare(full, "central"), ["punggol", "bishan"]);
});

test("compare bar text asks for a second town", () => {
  assert.equal(compareBarText([]), "");
  assert.equal(compareBarText(["Punggol"]), "Punggol: add a town to compare");
  assert.equal(compareBarText(["Punggol", "Bishan"]), "Punggol and Bishan");
  assert.equal(namesText(["Punggol", "Bishan", "Bedok"]), "Punggol, Bishan and Bedok");
});

const lineOf = (table, key) => table.lines.find((l) => l.key === key);
const texts = (line) => line.cells.map((c) => c.text);
const bests = (line) => line.cells.map((c) => c.best);

test("compareTable: a column per town and the best value in each line", () => {
  const data = structuredClone(DATA);
  data.towns[0].commute.cbd.fare = 160; // bishan
  data.towns[1].commute.cbd.fare = 211; // punggol
  const t = compareTable(data, state({ compare: ["punggol", "bishan"] }));
  assert.deepEqual(t.towns.map((x) => x.id), ["punggol", "bishan"]);
  assert.equal(lineOf(t, "time").label, "Time to CBD (Raffles Place)");
  assert.deepEqual(texts(lineOf(t, "time")), ["45 min", "20 min"]);
  assert.deepEqual(bests(lineOf(t, "time")), [false, true]);
  assert.deepEqual(texts(lineOf(t, "transfers")), ["1 transfer", "No transfer"]);
  assert.deepEqual(texts(lineOf(t, "fare")), ["$2.11", "$1.60"]);
  assert.equal(lineOf(t, "price").label, "4-room median rent");
  assert.deepEqual(texts(lineOf(t, "price")), ["$3,300/month (Q1 2026)", "$3,700/month (Q3 2026)"]);
  assert.deepEqual(bests(lineOf(t, "price")), [true, false]);
  // All-in: rent + fare there and back on 22 days (3300 + 92.84 -> 3393, 3700 + 70.4 -> 3770).
  assert.deepEqual(texts(lineOf(t, "allin")), ["≈ $3,393", "≈ $3,770"]);
  assert.deepEqual(bests(lineOf(t, "allin")), [true, false]);
  assert.deepEqual(texts(lineOf(t, "hours")), ["33 h", "15 h"]);
});

test("compareTable: ties are all best, unknown values never are, one value marks nothing", () => {
  const data = structuredClone(DATA);
  data.towns[1].commute.cbd = { min: 20, transfers: 0 }; // punggol now as fast as bishan
  const t = compareTable(data, state({ compare: ["bishan", "punggol", "jurong-east"] }));
  assert.deepEqual(bests(lineOf(t, "time")), [true, true, false]);
  // No fares in this data: nothing to compare, nothing marked.
  assert.deepEqual(texts(lineOf(t, "fare")), ["Not known", "Not known", "Not known"]);
  assert.deepEqual(bests(lineOf(t, "fare")), [false, false, false]);
  // Jurong East has no 4-room rent: not enough data, and not best.
  assert.equal(texts(lineOf(t, "price"))[2], "Not enough data");
  assert.equal(bests(lineOf(t, "price"))[2], false);
  assert.deepEqual(texts(lineOf(t, "allin")), ["–", "–", "–"]); // no fares, no all-in
});

test("compareTable: the office area's town reads 'In this area' and is never best on the commute", () => {
  const data = structuredClone(DATA);
  data.towns[0].commute["jurong-east"].fare = 190; // bishan
  data.towns[1].commute["jurong-east"].fare = 245; // punggol
  const t = compareTable(data, state({ area: "jurong-east", compare: ["jurong-east", "bishan", "punggol"] }));
  // Jurong East has no 4-room rent here, so its all-in cell is "In this area" too.
  for (const key of ["time", "transfers", "fare", "allin", "hours"]) {
    const line = lineOf(t, key);
    assert.equal(line.cells[0].text, IN_AREA, key);
    assert.equal(line.cells[0].value, null, key);
    assert.equal(line.cells[0].best, false, key);
  }
  // Time, transfers, fare: best among the other two towns, Bishan (40 min, 1 transfer, $1.90).
  assert.deepEqual(bests(lineOf(t, "time")), [false, true, false]);
  assert.deepEqual(bests(lineOf(t, "transfers")), [false, true, false]);
  assert.deepEqual(bests(lineOf(t, "fare")), [false, true, false]);
  // All-in and hours a month: no "best" at all while the office area's town is compared.
  assert.deepEqual(bests(lineOf(t, "allin")), [false, false, false]);
  assert.deepEqual(bests(lineOf(t, "hours")), [false, false, false]);
  // Without it, the same two lines mark their best again.
  const others = compareTable(data, state({ area: "jurong-east", compare: ["bishan", "punggol"] }));
  assert.deepEqual(bests(lineOf(others, "allin")), [false, true]); // Punggol's lower rent
  assert.deepEqual(bests(lineOf(others, "hours")), [true, false]);
  // The price is not a commute line: the office area's town is compared as usual (no 4-room rent).
  assert.equal(texts(lineOf(t, "price"))[0], "Not enough data");
  // With only one other town, no commute line has two values: nothing is marked.
  const two = compareTable(data, state({ area: "jurong-east", compare: ["jurong-east", "bishan"] }));
  assert.deepEqual(bests(lineOf(two, "time")), [false, false]);
  // Buy mode: fares a month too.
  const buy = compareTable(data, state({ mode: "buy", area: "jurong-east", compare: ["jurong-east", "bishan"] }));
  assert.equal(texts(lineOf(buy, "fares"))[0], IN_AREA);
  assert.equal(lineOf(buy, "fares").cells[0].best, false);
  assert.deepEqual(texts(lineOf(buy, "price")), ["$560,000 (Q2 2026)", "$700,000 (Q2 2026)"]);
  assert.deepEqual(bests(lineOf(buy, "price")), [true, false]);
});

test("compareTable: Woodlands to Woodlands against Ang Mo Kio and Bedok (real data)", () => {
  const real = JSON.parse(read("data/where-to-live.json"));
  const t = compareTable(real, readQuery("?area=woodlands&compare=woodlands,ang-mo-kio,bedok", real));
  const wood = real.towns.find((x) => x.id === "woodlands");
  // The data is rebuilt weekly: without a 4-room rent the cell reads "In this area".
  const rent = wood.rent?.["4-ROOM"]?.median;
  assert.equal(
    lineOf(t, "allin").cells[0].text,
    rent == null ? IN_AREA : `≈ $${rent.toLocaleString("en-SG")} rent, no fare estimate`,
  );
  assert.equal(lineOf(t, "allin").cells[0].value, null);
  assert.equal(lineOf(t, "hours").cells[0].text, IN_AREA);
  // No "best" in all-in or hours a month: Woodlands (no fares, no hours) is in the comparison.
  assert.deepEqual(bests(lineOf(t, "allin")), [false, false, false]);
  assert.deepEqual(bests(lineOf(t, "hours")), [false, false, false]);
  // Other lines as before: the commute lines among Ang Mo Kio and Bedok, the rent among all three.
  // (Written to hold after any weekly data rebuild: a lost rent or route only changes which cell.)
  const time = lineOf(t, "time");
  assert.equal(time.cells[0].text, IN_AREA);
  assert.equal(time.cells[0].best, false);
  const commutes = time.cells.slice(1).filter((c) => c.value != null);
  assert.equal(time.cells.slice(1).some((c) => c.best), commutes.length >= 2);
  const rents = lineOf(t, "price").cells.map((c) => c.value);
  const known = rents.filter((r) => r != null);
  const low = Math.min(...known);
  assert.deepEqual(bests(lineOf(t, "price")), rents.map((r) => known.length >= 2 && r === low));
  // Buy mode: fares a month reads "In this area" and marks no "best" either.
  const buy = compareTable(real, readQuery("?area=woodlands&mode=buy&compare=woodlands,ang-mo-kio,bedok", real));
  assert.equal(lineOf(buy, "fares").cells[0].text, IN_AREA);
  assert.deepEqual(bests(lineOf(buy, "fares")), [false, false, false]);
  assert.deepEqual(bests(lineOf(buy, "hours")), [false, false, false]);
});

test("compareTable: towns without a route", () => {
  const noRoute = compareTable(DATA, state({ compare: ["central", "bishan"] }));
  assert.deepEqual(texts(lineOf(noRoute, "time")), ["No route data", "20 min"]);
  assert.deepEqual(bests(lineOf(noRoute, "time")), [false, false]); // one known value: no mark
  assert.equal(texts(lineOf(noRoute, "hours"))[0], "–");
});

test("compareTable in buy mode compares resale prices and monthly fares", () => {
  const data = structuredClone(DATA);
  data.towns[0].commute.cbd.fare = 160;
  data.towns[1].commute.cbd.fare = 211;
  const t = compareTable(data, state({ mode: "buy", compare: ["punggol", "bishan"] }));
  assert.equal(lineOf(t, "price").label, "4-room median resale price");
  assert.deepEqual(texts(lineOf(t, "price")), ["$610,000 (Q2 2026)", "$700,000 (Q2 2026)"]);
  assert.equal(lineOf(t, "allin"), undefined);
  assert.deepEqual(texts(lineOf(t, "fares")), ["≈ $93", "≈ $70"]);
  assert.deepEqual(bests(lineOf(t, "fares")), [false, true]);
});

test("the page has the compare panel and bar", () => {
  const html = read("where-to-live/index.html");
  for (const id of ["compare", "compare-table", "compare-bar", "compare-go", "compare-chips"]) {
    assert.match(html, new RegExp(`id="${id}"`));
  }
});
