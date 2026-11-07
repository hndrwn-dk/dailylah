// /where-to-live: the form, the ranked board and the map. Logic lives in logic.js.
//
// Every string from where-to-live.json (town and station names, attribution, ids) reaches the page
// through textContent, createTextNode or option.text, never innerHTML (docs/WHERE_TO_LIVE.md,
// Fase 2). Map popups are DOM elements. Query values are checked against the data (readQuery).

import {
  MAX_MINUTES,
  commuteText,
  flatLabel,
  flatTypes,
  priceLine,
  quarterLabel,
  rank,
  readQuery,
  reasonText,
  writeQuery,
} from "./logic.js";

const DATA_URL = "/data/where-to-live.json";
const TILE_URL = "https://www.onemap.gov.sg/maps/tiles/{style}/{z}/{x}/{y}.png";
// OneMap's required attribution (logo, OneMap link, SLA link). A constant written here, not data;
// the logo size comes from the om-logo class, since the page's CSP allows no inline styles.
const ONEMAP_ATTRIBUTION =
  '<img class="om-logo" src="https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png" alt="">' +
  '&nbsp;<a href="https://www.onemap.gov.sg/" target="_blank" rel="noopener noreferrer">OneMap</a>' +
  '&nbsp;&copy;&nbsp;contributors&nbsp;&#124;&nbsp;' +
  '<a href="https://www.sla.gov.sg/" target="_blank" rel="noopener noreferrer">Singapore Land Authority</a>';
const SG_BOUNDS = [
  [1.144, 103.535],
  [1.494, 104.502],
];

const $ = (id) => document.getElementById(id);

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function option(value, text, selected) {
  const o = document.createElement("option");
  o.value = value;
  o.text = text;
  o.selected = selected;
  return o;
}

// ---------------------------------------------------------------- form

function fillForm(data, state) {
  $("area").replaceChildren(...data.areas.map((a) => option(a.id, a.name, a.id === state.area)));
  for (const input of document.querySelectorAll("input[name=mode]")) input.checked = input.value === state.mode;
  $("flat").replaceChildren(...flatTypes(data, state.mode).map((f) => option(f, flatLabel(f), f === state.flat)));
  $("budget-label").textContent = state.mode === "buy" ? "Max price ($)" : "Max rent per month ($)";
  $("budget").value = state.budget ?? "";
  $("max").replaceChildren(
    option("", "Any time", state.max == null),
    ...MAX_MINUTES.map((m) => option(String(m), `Up to ${m} min`, m === state.max)),
  );
}

function formQuery() {
  const q = new URLSearchParams();
  q.set("area", $("area").value);
  q.set("mode", document.querySelector("input[name=mode]:checked")?.value ?? "rent");
  q.set("flat", $("flat").value);
  if ($("budget").value) q.set("budget", $("budget").value.replace(/[^\d]/g, ""));
  if ($("max").value) q.set("max", $("max").value);
  return `?${q}`;
}

// ---------------------------------------------------------------- board

function boardRow(row, state, onPick) {
  const li = el("li", `row ${row.group}`);
  const head = el("div", "row-head");
  const name = el("button", "town", row.town.name);
  name.type = "button";
  name.addEventListener("click", () => onPick(row.town.id));
  const eta = el("span", "eta");
  if (row.commute?.same_area) eta.textContent = "Here";
  else if (row.commute) {
    eta.textContent = String(row.commute.min);
    eta.append(el("small", null, "min"));
  } else eta.textContent = "--";
  head.append(name, eta);
  const detail = el("p", "detail");
  detail.append(
    el(
      "span",
      null,
      row.commute && !row.commute.same_area
        ? `${commuteText(row.commute)} from ${row.town.station} MRT`
        : commuteText(row.commute),
    ),
    el("span", row.price ? null : "muted", priceLine(state, row.price)),
  );
  if (row.reason) detail.prepend(el("span", "why", reasonText(row, state)));
  li.append(head, detail);
  return li;
}

function group(title, rows, state, onPick, { emptyText = null, folded = false } = {}) {
  if (!rows.length && !emptyText) return null;
  const heading = `${title} (${rows.length})`;
  const section = el(folded ? "details" : "section", "group");
  section.append(folded ? el("summary", null, heading) : el("h3", null, heading));
  if (!rows.length) {
    section.append(el("p", "empty", emptyText));
    return section;
  }
  const ol = el("ol", "rows");
  ol.append(...rows.map((r) => boardRow(r, state, onPick)));
  section.append(ol);
  return section;
}

function renderBoard(data, state, groups, onPick) {
  const area = data.areas.find((a) => a.id === state.area);
  $("board-title").textContent = `To ${area.name}`;
  $("board-sub").textContent = `Public transport on a weekday at 08:30 · ${flatLabel(state.flat)} ${
    state.mode === "buy" ? "resale" : "rent"
  }`;
  const parts = [
    group("Fits your choices", groups.match, state, onPick, {
      emptyText: "No town fits. Raise the budget or allow a longer trip.",
    }),
    group(`No ${flatLabel(state.flat)} price data`, groups.noPrice, state, onPick),
    // Folded while some town fits, so the map is not pushed far down on a phone.
    group("Outside your choices", groups.other, state, onPick, { folded: groups.match.length > 0 }),
  ].filter(Boolean);
  $("board-body").replaceChildren(...parts);
}

// ---------------------------------------------------------------- map

function makeMap(data) {
  const L = window.L;
  if (!L) return null;
  const map = L.map("map", { maxBounds: SG_BOUNDS, minZoom: 11, maxZoom: 18, scrollWheelZoom: false });
  const dark = window.matchMedia("(prefers-color-scheme: dark)");
  const tiles = L.tileLayer(TILE_URL, {
    style: dark.matches ? "Night" : "Default",
    detectRetina: true,
    maxZoom: 18,
    minZoom: 11,
    attribution: ONEMAP_ATTRIBUTION,
  }).addTo(map);
  dark.addEventListener("change", (e) => {
    tiles.options.style = e.matches ? "Night" : "Default";
    tiles.redraw();
  });
  map.fitBounds(data.towns.map((t) => [t.lat, t.lng]), { padding: [16, 16] });
  return { L, map, layer: L.layerGroup().addTo(map), markers: new Map() };
}

function popup(row, state) {
  const box = el("div", "pop");
  box.append(
    el("strong", null, row.town.name),
    el("span", null, commuteText(row.commute)),
    el("span", null, priceLine(state, row.price)),
  );
  return box;
}

function renderMap(m, data, state, groups) {
  if (!m) return;
  const { L, layer, markers } = m;
  layer.clearLayers();
  markers.clear();
  const colour = { match: "#0E9488", noPrice: "#EDAD2B", other: "#8A9BA0" };
  for (const [name, rows] of Object.entries(groups)) {
    for (const row of rows) {
      const marker = L.circleMarker([row.town.lat, row.town.lng], {
        radius: name === "match" ? 9 : 6,
        color: "#0F1618",
        weight: 2,
        fillColor: colour[name],
        fillOpacity: 0.95,
      }).bindPopup(() => popup(row, state));
      marker.addTo(layer);
      markers.set(row.town.id, marker);
    }
  }
  const area = data.areas.find((a) => a.id === state.area);
  const office = el("div", "pop");
  office.append(el("strong", null, area.name), el("span", null, "Office area"));
  L.circleMarker([area.lat, area.lng], {
    radius: 11,
    color: "#0F1618",
    weight: 3,
    fillColor: "#FFFFFF",
    fillOpacity: 1,
  })
    .bindPopup(office)
    .addTo(layer);
}

// ---------------------------------------------------------------- page

function renderSources(data) {
  const updated = new Date(data.generated_at);
  const when = Number.isNaN(updated.getTime())
    ? ""
    : ` Updated ${updated.toLocaleDateString("en-SG", { day: "numeric", month: "short", year: "numeric" })}.`;
  $("sources").textContent =
    `HDB median rent up to ${quarterLabel(data.rent_quarter)} and median resale price up to ` +
    `${quarterLabel(data.resale_quarter)}; each figure shows its own quarter. Travel times from OneMap ` +
    `for a weekday at 08:30, from the town's main MRT station.${when}`;
  $("attribution").textContent = data.attribution;
}

async function main() {
  let data;
  try {
    const res = await fetch(DATA_URL);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    data = await res.json();
  } catch {
    $("board-body").replaceChildren(
      el("p", "empty", "The town data did not load. Check your connection and reload the page."),
    );
    return;
  }
  let state = readQuery(window.location.search, data);
  const m = makeMap(data);
  const pick = (id) => {
    const marker = m?.markers.get(id);
    if (!marker) return;
    m.map.setView(marker.getLatLng(), Math.max(m.map.getZoom(), 13));
    marker.openPopup();
    $("map").scrollIntoView({ block: "nearest", behavior: "smooth" });
  };
  const render = () => {
    fillForm(data, state);
    const groups = rank(data, state);
    renderBoard(data, state, groups, pick);
    renderMap(m, data, state, groups);
    window.history.replaceState(null, "", `${window.location.pathname}${writeQuery(state)}`);
  };
  $("choices").addEventListener("change", () => {
    state = readQuery(formQuery(), data);
    render();
  });
  $("choices").addEventListener("submit", (e) => {
    e.preventDefault();
    state = readQuery(formQuery(), data);
    render();
  });
  renderSources(data);
  render();
}

main();
