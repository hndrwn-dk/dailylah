// /where-to-live: the form, the ranked board and the map. Logic lives in logic.js.
//
// Every string from where-to-live.json (town and station names, attribution, ids) reaches the page
// through textContent or createTextNode, never innerHTML.
// Map pills and popups are DOM elements. Query values are checked against the data.

import {
  MAX_COMPARE,
  MAX_MINUTES,
  changeChoices,
  compareBarText,
  compareTable,
  namesText,
  toggleCompare,
  commuteText,
  flatLabel,
  flatTypes,
  allInText,
  highlights,
  pillText,
  priceDetail,
  priceLine,
  quarterLabel,
  rank,
  readQuery,
  reasonText,
  routeDetail,
  shortPrice,
  timeBand,
  writeQuery,
} from "./logic.js";
// The landing page's motion helpers: the spring, a drag's speed, where a flick ends, soft edges.
import { Spring, Velocity, calm, clamp, project, rubber } from "/shared/spring.js";

const DATA_URL = "/data/where-to-live.json";
const TILE_URL = "https://www.onemap.gov.sg/maps/tiles/{style}/{z}/{x}/{y}.png";
const ONEMAP_LOGO = "https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png";
// OneMap's required attribution (logo, OneMap link, SLA link). A constant written here, not data;
// the logo size comes from the om-logo class, since the page's CSP allows no inline styles.
const ONEMAP_ATTRIBUTION =
  `<img class="om-logo" src="${ONEMAP_LOGO}" alt="OneMap logo">` +
  '&nbsp;<a href="https://www.onemap.gov.sg/" target="_blank" rel="noopener noreferrer">OneMap</a>' +
  '&nbsp;&copy;&nbsp;contributors&nbsp;&#124;&nbsp;' +
  '<a href="https://www.sla.gov.sg/" target="_blank" rel="noopener noreferrer">Singapore Land Authority</a>';
const SG_BOUNDS = [
  [1.144, 103.535],
  [1.494, 104.502],
];
const TOP_ROWS = 8;
const SVG_NS = "http://www.w3.org/2000/svg";

const $ = (id) => document.getElementById(id);

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

// ---------------------------------------------------------------- form

const ANY_TIME = MAX_MINUTES.length; // the travel time slider's last step
const dollars = new Intl.NumberFormat("en-SG");

/** One chip: a radio button with its label, so the keyboard and a screen reader get a real choice. */
function chip(name, value, text, checked) {
  const label = el("label");
  const input = document.createElement("input");
  input.type = "radio";
  input.name = name;
  input.value = value;
  input.checked = checked;
  label.append(input, el("span", null, text));
  return label;
}

/** Fill a group of chips. They are rebuilt only when the list changes, so focus stays put. */
function fillChips(box, name, items, chosen) {
  const have = [...box.querySelectorAll("input")].map((input) => input.value);
  if (have.length !== items.length || have.some((value, i) => value !== items[i][0])) {
    box.replaceChildren(...items.map(([value, text]) => chip(name, value, text, value === chosen)));
  } else {
    for (const input of box.querySelectorAll("input")) input.checked = input.value === chosen;
  }
}

/**
 * The budget slider for a mode: from the lowest to the highest median in the data, in steps of
 * $100 (rent) or $25,000 (resale). One step past the top means "Any".
 */
function budgetRange(data, mode) {
  const key = mode === "buy" ? "resale" : "rent";
  const step = mode === "buy" ? 25000 : 100;
  const all = data.towns.flatMap((t) => Object.values(t[key] ?? {}).map((c) => c?.median).filter(Number.isFinite));
  if (!all.length) return { min: 0, top: step, step, any: step * 2 };
  const top = Math.ceil(Math.max(...all) / step) * step;
  return { min: Math.floor(Math.min(...all) / step) * step, top, step, any: top + step };
}

function fillForm(data, state) {
  fillChips($("area"), "area", data.areas.map((a) => [a.id, a.name]), state.area);
  for (const input of document.querySelectorAll("input[name=mode]")) input.checked = input.value === state.mode;
  fillChips($("flat"), "flat", flatTypes(data, state.mode).map((f) => [f, flatLabel(f)]), state.flat);
  const range = budgetRange(data, state.mode);
  const budget = $("budget");
  budget.min = String(range.min);
  budget.max = String(range.any);
  budget.step = String(range.step);
  budget.value = String(state.budget == null ? range.any : clamp(state.budget, range.min, range.top));
  // A budget from a link may sit between two steps: it is kept until the slider is moved.
  if (state.budget == null) delete budget.dataset.moved;
  $("budget-label").textContent = state.mode === "buy" ? "Max price" : "Max rent per month";
  $("budget-out").textContent = state.budget == null ? "Any" : `$${dollars.format(state.budget)}`;
  $("max").value = String(state.max == null ? ANY_TIME : MAX_MINUTES.indexOf(state.max));
  $("max-out").textContent = state.max == null ? "Any time" : `Up to ${state.max} min`;
}

function formQuery(state) {
  const q = new URLSearchParams();
  const picked = (name) => document.querySelector(`input[name=${name}]:checked`)?.value;
  q.set("area", picked("area") ?? state.area);
  q.set("mode", picked("mode") ?? "rent");
  q.set("flat", picked("flat") ?? state.flat);
  const slider = $("budget");
  const budget = !slider.dataset.moved ? state.budget : Number(slider.value) >= Number(slider.max) ? null : Number(slider.value);
  if (budget != null) q.set("budget", String(budget));
  const step = Number($("max").value);
  if (step < ANY_TIME) q.set("max", String(MAX_MINUTES[step]));
  return `?${q}`;
}

// ---------------------------------------------------------------- board

const FULL_BAR = 90; // minutes that fill a row's bar

/**
 * One row per town: its place, the name over a bar as long as the trip, minutes and price; tapping
 * the line opens the details below. [place] is the town's number among those that fit, or null.
 */
function boardRow(row, view, actions, place) {
  const { state } = view;
  const open = view.open === row.town.id;
  const li = el("li", `row ${row.group}${view.selected === row.town.id ? " on" : ""}`);
  li.id = `row-${row.town.id}`;
  const number = el("span", "rank", place == null ? "–" : String(place));
  number.setAttribute("aria-hidden", "true");
  const line = el("button", "line");
  line.type = "button";
  line.setAttribute("aria-expanded", String(open));
  line.setAttribute("aria-controls", `more-${row.town.id}`);
  const eta = el("span", "eta");
  if (row.commute?.same_area) eta.textContent = "Here";
  else if (row.commute) {
    eta.textContent = String(row.commute.min);
    eta.append(el("small", null, " min"));
  } else eta.textContent = "--";
  // The bar takes the map pill's colour for the same travel time band.
  const band = timeBand(row.commute);
  const fill = el("i", band == null ? null : `b${band}`);
  fill.style.transform = `scaleX(${row.commute ? clamp(row.minutes / FULL_BAR, 0.03, 1) : 0})`;
  const bar = el("span", "tbar");
  bar.setAttribute("aria-hidden", "true");
  bar.append(fill);
  const town = el("span", "town");
  // A zero-width space after a slash lets "Kallang/Whampoa" break there on a narrow phone.
  town.append(el("span", "town-name", row.town.name.replace("/", "/​")), bar);
  line.append(town, eta, el("span", row.price ? "price" : "price none", shortPrice(state.mode, row.price)));
  line.addEventListener("click", () => actions.toggle(row.town.id));
  // The row under the pointer marks its pill on the map.
  li.addEventListener("pointerenter", () => actions.hover(row.town.id, true));
  li.addEventListener("pointerleave", () => actions.hover(row.town.id, false));
  li.append(number, line);
  const more = el("div", "more");
  more.id = `more-${row.town.id}`;
  more.hidden = !open;
  if (row.reason) more.append(el("span", "why", reasonText(row, state)));
  more.append(el("span", null, routeDetail(row)), el("span", null, priceDetail(state, row.price)));
  const cost = allInText(state, row);
  if (cost) more.append(el("span", "cost", cost));
  const page = el("a", "town-link", `More about ${row.town.name}`);
  page.href = `/where-to-live/${encodeURIComponent(row.town.id)}`;
  more.append(page);
  li.append(compareButton(row.town, view, actions), more);
  return li;
}

/** "+ Compare" next to a row: adds or removes the town (at most MAX_COMPARE). */
function compareButton(town, view, actions) {
  const picked = view.state.compare.includes(town.id);
  const full = !picked && view.state.compare.length >= MAX_COMPARE;
  const b = el("button", `cmp${picked ? " on" : ""}`);
  b.type = "button";
  b.append(el("span", "cmp-mark", picked ? "✓" : "+"), el("span", "cmp-word", picked ? "Added" : "Compare"));
  b.setAttribute("aria-pressed", String(picked));
  b.setAttribute("aria-label", `Compare ${town.name}`);
  if (full) {
    b.disabled = true;
    b.title = `Up to ${MAX_COMPARE} towns`;
  }
  b.addEventListener("click", () => actions.compare(town.id));
  return b;
}

// ---------------------------------------------------------------- compare

/** The bar at the bottom: the picked towns (tap to remove), a hint and the Compare button. */
function renderCompareBar(data, view, actions) {
  const ids = view.state.compare;
  const bar = $("compare-bar");
  bar.hidden = ids.length === 0;
  // Under the open sheet the bar cannot be seen: keep the keyboard out of it until the sheet is away.
  bar.inert = view.comparing;
  document.body.classList.toggle("has-bar", ids.length > 0);
  const names = ids.map((id) => data.towns.find((t) => t.id === id)?.name ?? id);
  $("compare-chips").replaceChildren(
    ...ids.map((id, i) => {
      const li = el("li");
      const chip = el("button", "chip");
      chip.type = "button";
      chip.append(el("span", null, names[i]), el("span", "chip-x", "×"));
      chip.setAttribute("aria-label", `Remove ${names[i]} from the comparison`);
      chip.addEventListener("click", () => actions.compare(id));
      li.append(chip);
      return li;
    }),
  );
  $("compare-hint").textContent =
    ids.length === 1 ? "Add a town to compare" : ids.length >= MAX_COMPARE ? `Up to ${MAX_COMPARE} towns` : "";
  const go = $("compare-go");
  go.disabled = ids.length < 2;
  // While the table is open it follows the list; the button then takes you back to it.
  go.textContent = view.comparing ? "See comparison" : "Compare";
  if (ids.length) bar.setAttribute("aria-label", `Towns to compare: ${compareBarText(names)}`);
}

/**
 * Keep the end of the page clear of the fixed bar, whatever its height (one to three lines of
 * chips on a phone). Sets padding through the CSSOM, which the page's CSP allows.
 */
function watchBarHeight() {
  const bar = $("compare-bar");
  const sheet = $("compare");
  const fit = () => {
    // While the comparison sheet is up it is the taller of the two: the last rows and the footer
    // can still be scrolled clear of it.
    const height = Math.max(bar.hidden ? 0 : bar.getBoundingClientRect().height, sheet.hidden ? 0 : sheet.getBoundingClientRect().height);
    const room = height ? `${Math.ceil(height) + 16}px` : "";
    document.body.style.paddingBottom = room;
    // A row focused with the keyboard is scrolled clear of the bar, not under it.
    document.documentElement.style.scrollPaddingBottom = room;
  };
  if (typeof ResizeObserver === "function") {
    const watch = new ResizeObserver(fit);
    watch.observe(bar);
    watch.observe(sheet); // also when it is shown or put away
  }
  return fit;
}

/** The side-by-side table: a column per town, the best value in each line marked. */
function renderCompare(data, view, actions) {
  // The sheet itself is shown and put away by makeSheet; here only what it holds.
  if (!view.comparing) return;
  const { state } = view;
  const { towns, lines } = compareTable(data, state);
  const area = data.areas.find((a) => a.id === state.area);
  $("compare-title").textContent = `Compare ${namesText(towns.map((t) => t.name))}`;
  $("compare-sub").textContent = `To ${area.name}, weekday 08:30 by MRT and bus, ${flatLabel(state.flat)} ${
    state.mode === "buy" ? "resale" : "rent"
  }`;
  const head = el("tr");
  head.append(el("td", "corner"));
  for (const town of towns) {
    const th = el("th");
    th.scope = "col";
    const link = el("a", null, town.name);
    link.href = `/where-to-live/${encodeURIComponent(town.id)}`;
    const drop = el("button", "col-x", "×");
    drop.type = "button";
    drop.setAttribute("aria-label", `Remove ${town.name} from the comparison`);
    drop.addEventListener("click", () => actions.compare(town.id));
    th.append(link, drop);
    head.append(th);
  }
  const thead = el("thead");
  thead.append(head);
  const tbody = el("tbody");
  for (const line of lines) {
    const tr = el("tr");
    const th = el("th", null, line.label);
    th.scope = "row";
    tr.append(th);
    for (const c of line.cells) {
      const td = el("td", c.best ? "best" : null, c.text);
      if (c.best) td.append(el("span", "best-tag", "Best"));
      tr.append(td);
    }
    tbody.append(tr);
  }
  $("compare-table").replaceChildren(thead, tbody);
}

function group(title, rows, view, actions, opts = {}) {
  const { emptyText = null, folded = false, top = null, key, numbered = false } = opts;
  if (!rows.length && !emptyText) return null;
  const heading = `${title} (${rows.length})`;
  const section = el(folded ? "details" : "section", "group");
  if (folded) {
    section.open = view.unfolded.has(key);
    section.addEventListener("toggle", () => {
      if (section.open) view.unfolded.add(key);
      else view.unfolded.delete(key);
    });
  }
  section.append(folded ? el("summary", null, heading) : el("h3", null, heading));
  if (!rows.length) {
    section.append(el("p", "empty", emptyText));
    return section;
  }
  const cut = top != null && !view.showAll && rows.length > top ? top : rows.length;
  const ol = el("ol", "rows");
  ol.append(...rows.slice(0, cut).map((r, i) => boardRow(r, view, actions, numbered ? i + 1 : null)));
  section.append(ol);
  if (cut < rows.length) {
    const more = el("button", "show-all", `Show all ${rows.length}`);
    more.type = "button";
    more.addEventListener("click", actions.showAll);
    section.append(more);
  }
  return section;
}

function renderBoard(data, view, groups, actions) {
  const { state } = view;
  const area = data.areas.find((a) => a.id === state.area);
  $("board-title").textContent = `To ${area.name}`;
  $("board-sub").textContent = `Weekday 08:30 by MRT and bus, ${flatLabel(state.flat)} ${
    state.mode === "buy" ? "resale" : "rent"
  }`;
  const parts = [
    group("Fits your choices", groups.match, view, actions, {
      emptyText: "Alamak, nothing fits. Try a bigger budget or longer travel time.",
      top: TOP_ROWS,
      numbered: true,
    }),
    group(`No ${flatLabel(state.flat)} price data`, groups.noPrice, view, actions),
    // Folded while some town fits, so the map is not pushed far down on a phone.
    group("Outside your choices", groups.other, view, actions, {
      folded: groups.match.length > 0,
      key: "other",
    }),
  ].filter(Boolean);
  $("board-body").replaceChildren(...parts);
  renderPicks(state, groups);
}

/** "Fastest" and "Best value" above the board; hidden when no town fits with a price. */
function renderPicks(state, groups) {
  const picks = highlights(groups);
  $("picks").hidden = !picks;
  if (!picks) return;
  for (const [id, row] of [["pick-fast", picks.fastest], ["pick-value", picks.value]]) {
    const cost = allInText(state, row);
    const time = row.commute.same_area ? "In this area" : `${row.commute.min} min`;
    $(id).replaceChildren(
      el("strong", "pick-town", row.town.name),
      el("span", "pick-line", `${time} · ${shortPrice(state.mode, row.price)}`),
      ...(cost ? [el("span", "allin", cost)] : []),
    );
  }
}

/**
 * The rows glide to their new places when the order changes, instead of jumping: each row starts
 * from where it was on screen a moment ago ([before]: town id to its top) and settles; a row that
 * was not there fades in. With reduced motion they simply change.
 */
function slideRows(before) {
  if (calm() || !before.size) return;
  for (const li of document.querySelectorAll("#board-body .row")) {
    const was = before.get(li.id);
    if (was == null) {
      li.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 260, easing: "ease-out" });
      continue;
    }
    const dy = was - li.getBoundingClientRect().top;
    if (Math.abs(dy) > 1) {
      li.animate([{ transform: `translateY(${dy}px)` }, { transform: "none" }], { duration: 420, easing: "cubic-bezier(.2,.9,.3,1)" });
    }
  }
}

/** Where every row is on screen right now, by its id. A row in a folded group is nowhere: left out. */
function rowTops() {
  return new Map(
    [...document.querySelectorAll("#board-body .row")]
      .filter((li) => li.getClientRects().length > 0)
      .map((li) => [li.id, li.getBoundingClientRect().top]),
  );
}

// ---------------------------------------------------------------- compare sheet

/**
 * The comparison as a sheet from the bottom. set(true) brings it up, set(false) puts it away; its
 * top can be dragged: it follows the finger, resists softly above its open place, and a flick or
 * a drag past 40% of its height dismisses it ([onDismiss], with the speed of the release).
 */
function makeSheet(onDismiss) {
  const panel = $("compare");
  const grip = $("compare-grip");
  const y = new Spring(0, { response: 0.35, damping: 1 });
  let open = false;
  let leaving = false;
  y.onUpdate = (v) => {
    panel.style.transform = `translateY(${v}px)`;
    if (leaving && v >= panel.offsetHeight - 0.5) {
      leaving = false;
      panel.hidden = true;
    }
  };
  let drag = null;
  grip.addEventListener("pointerdown", (e) => {
    // Not while it is on its way out: a grab then would bring back a sheet the page thinks is closed.
    if (!open || e.button !== 0 || e.target.closest("button, a")) return;
    y.stop(); // grab it where it is, even mid-flight
    drag = { id: e.pointerId, y0: e.clientY, from: y.x, speed: new Velocity() };
    drag.speed.add(y.x, e.timeStamp);
    grip.setPointerCapture(e.pointerId);
    grip.classList.add("dragging");
  });
  grip.addEventListener("pointermove", (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    if (e.buttons === 0) return release(e);
    let to = drag.from + (e.clientY - drag.y0);
    if (to < 0) to = -rubber(-to, panel.offsetHeight);
    y.jump(to);
    drag.speed.add(to, e.timeStamp);
  });
  function release(e) {
    if (!drag || (e && e.pointerId !== drag.id)) return;
    // With the time of the release: a finger that held still before letting go has no speed left.
    const velocity = drag.speed.get(e?.timeStamp ?? performance.now());
    drag = null;
    grip.classList.remove("dragging");
    const rest = y.x + project(velocity, 0.99);
    if (rest > panel.offsetHeight * 0.4) onDismiss(velocity);
    else y.to(0, { velocity, response: 0.3, damping: Math.abs(velocity) > 300 ? 0.8 : 1 });
  }
  grip.addEventListener("pointerup", release);
  grip.addEventListener("pointercancel", release);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && open) onDismiss(0);
  });
  return {
    set(want, velocity = 0) {
      if (want === open) return;
      open = want;
      if (want) {
        leaving = false;
        if (panel.hidden) {
          panel.hidden = false;
          y.jump(panel.offsetHeight); // start below the screen
        }
        y.to(0, { velocity, response: 0.35, damping: 1 });
      } else {
        leaving = true;
        y.to(panel.offsetHeight, { velocity, response: 0.3, damping: 1 });
      }
    },
  };
}

// ---------------------------------------------------------------- share

/** Share the current URL with the phone's share sheet, or copy it where that is not offered. */
function setUpShare() {
  const button = $("share");
  const note = $("share-note");
  const canShare = typeof navigator.share === "function";
  const canCopy = Boolean(navigator.clipboard?.writeText);
  if (!canShare && !canCopy) return;
  button.textContent = canShare ? "Share" : "Copy link";
  button.hidden = false;
  let timer;
  const say = (text) => {
    note.textContent = text;
    clearTimeout(timer);
    timer = setTimeout(() => {
      note.textContent = "";
    }, 2500);
  };
  button.addEventListener("click", async () => {
    const url = window.location.href;
    if (canShare) {
      try {
        await navigator.share({ title: document.title, text: "Where to live? HDB towns by commute and price", url });
      } catch {
        // Closed the share sheet, or sharing failed: nothing to report.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      button.textContent = "Link copied";
      say("Link copied. Paste it anywhere to share these choices.");
      setTimeout(() => {
        button.textContent = "Copy link";
      }, 2500);
    } catch {
      say("Copy did not work. Copy the address from the browser bar instead.");
    }
  });
}

// ---------------------------------------------------------------- map

function makeMap(data) {
  const L = window.L;
  if (!L) return null;
  // OneMap tiles start at zoom 11. A phone map is narrower than Singapore at zoom 11, so the map may
  // zoom out to 10.5 in quarter steps and scales the zoom 11 tiles down (minNativeZoom).
  const map = L.map("map", {
    maxBounds: SG_BOUNDS,
    minZoom: 10.5,
    maxZoom: 18,
    zoomSnap: 0.25,
    scrollWheelZoom: false,
  });
  const dark = window.matchMedia("(prefers-color-scheme: dark)");
  const tiles = L.tileLayer(TILE_URL, {
    style: dark.matches ? "Night" : "Default",
    maxZoom: 18,
    minZoom: 10.5,
    minNativeZoom: 11,
    attribution: ONEMAP_ATTRIBUTION,
  }).addTo(map);
  dark.addEventListener("change", (e) => {
    tiles.options.style = e.matches ? "Night" : "Default";
    tiles.redraw();
  });
  // A logo that does not load is hidden instead of showing a broken image (no inline onerror:
  // the CSP blocks it).
  // Listen on the container in the capture phase: Leaflet may rebuild the attribution, and an
  // image's error event does not bubble.
  const credits = map.attributionControl.getContainer();
  const hideBroken = (img) => img.classList.add("gone");
  credits.addEventListener(
    "error",
    (e) => {
      if (e.target instanceof HTMLImageElement && e.target.classList.contains("om-logo")) hideBroken(e.target);
    },
    true,
  );
  for (const img of credits.querySelectorAll("img.om-logo")) {
    if (img.complete && img.naturalWidth === 0) hideBroken(img);
  }
  map.fitBounds(data.towns.map((t) => [t.lat, t.lng]), { padding: [20, 20] });
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

function pill(row, selected) {
  const band = timeBand(row.commute);
  const outside = row.group === "other";
  const span = el(
    "span",
    `pill ${outside ? "out" : `b${band ?? "x"}`}${row.group === "noPrice" ? " noprice" : ""}${selected ? " on" : ""}`,
    pillText(row.commute),
  );
  span.title = row.town.name;
  return span;
}

function officePin(area) {
  const wrap = el("span", "office");
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 28 36");
  svg.setAttribute("width", "28");
  svg.setAttribute("height", "36");
  svg.setAttribute("aria-hidden", "true");
  const pin = document.createElementNS(SVG_NS, "path");
  pin.setAttribute("d", "M14 1C6.8 1 1 6.6 1 13.6 1 23 14 35 14 35s13-12 13-21.4C27 6.6 21.2 1 14 1z");
  pin.setAttribute("class", "pin");
  const bag = document.createElementNS(SVG_NS, "path");
  bag.setAttribute("d", "M10 10V8.5A1.5 1.5 0 0 1 11.5 7h5A1.5 1.5 0 0 1 18 8.5V10h3v8H7v-8zm2 0h4V9h-4z");
  bag.setAttribute("class", "bag");
  svg.append(pin, bag);
  wrap.append(svg);
  wrap.title = `Office area: ${area.name}`;
  return wrap;
}

function renderMap(m, data, view, groups, actions) {
  if (!m) return;
  const { L, layer, markers } = m;
  layer.clearLayers();
  markers.clear();
  for (const rows of [groups.other, groups.noPrice, groups.match]) {
    for (const row of rows) {
      const selected = view.selected === row.town.id;
      const icon = L.divIcon({ html: pill(row, selected), className: "pill-icon", iconSize: null, popupAnchor: [0, -14] });
      const marker = L.marker([row.town.lat, row.town.lng], {
        icon,
        keyboard: true,
        title: row.town.name,
        alt: row.town.name,
        zIndexOffset: selected ? 1000 : row.group === "match" ? 200 : 0,
      }).bindPopup(() => popup(row, view.state));
      marker.on("click", () => actions.fromMap(row.town.id));
      // The pill under the pointer marks its row in the list.
      marker.on("mouseover", () => $(`row-${row.town.id}`)?.classList.add("hot"));
      marker.on("mouseout", () => $(`row-${row.town.id}`)?.classList.remove("hot"));
      marker.addTo(layer);
      markers.set(row.town.id, marker);
    }
  }
  const area = data.areas.find((a) => a.id === view.state.area);
  const office = el("div", "pop");
  office.append(el("strong", null, area.name), el("span", null, "Office area"));
  L.marker([area.lat, area.lng], {
    icon: L.divIcon({ html: officePin(area), className: "pill-icon", iconSize: null, popupAnchor: [0, -34] }),
    title: `Office area: ${area.name}`,
    alt: `Office area: ${area.name}`,
    zIndexOffset: 2000,
  })
    .bindPopup(office)
    .addTo(layer);
}

// ---------------------------------------------------------------- page

function renderSources(data) {
  const updated = new Date(data.generated_at);
  const when = Number.isNaN(updated.getTime())
    ? ""
    : ` Updated ${updated.toLocaleDateString("en-SG", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Singapore" })}.`;
  $("sources").textContent = `Indicative figures from HDB via data.gov.sg (Singapore Open Data Licence).${when}`;
  $("about-data").textContent =
    `HDB median rent up to ${quarterLabel(data.rent_quarter)} and resale price up to ` +
    `${quarterLabel(data.resale_quarter)}; open a town to see the quarter of its figure, and ` +
    `"not enough data" means HDB published no median for it. Travel times are planned OneMap trips, ` +
    `not live ones, on a weekday at 08:30 from each town's main MRT station, with adult card ` +
    `fares; monthly figures assume 22 working days there and back. DailyLah is not ` +
    `affiliated with HDB or the Singapore Land Authority.`;
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
  const view = {
    state: readQuery(window.location.search, data),
    open: null, // town whose row is opened
    selected: null, // town whose pill is highlighted
    showAll: false,
    unfolded: new Set(),
    // The side-by-side table is open: on load when the link names two or more towns.
    comparing: false,
  };
  view.comparing = view.state.compare.length >= 2;
  const m = makeMap(data);
  let groups = rank(data, view.state);

  const fitBar = watchBarHeight();
  const syncUrl = () =>
    window.history.replaceState(null, "", `${window.location.pathname}${writeQuery(view.state)}`);
  const draw = () => {
    const before = rowTops();
    renderBoard(data, view, groups, actions);
    slideRows(before);
    renderMap(m, data, view, groups, actions);
    renderCompareBar(data, view, actions);
    fitBar();
    renderCompare(data, view, actions);
    sheet.set(view.comparing);
  };
  const showCompare = () => {
    view.comparing = true;
    draw();
    $("compare-title").focus({ preventScroll: true });
  };
  /** Put the comparison away (the button, Escape, or a drag down with [velocity]). */
  const closeCompare = (velocity = 0) => {
    view.comparing = false;
    sheet.set(false, velocity);
    draw();
    // The keyboard goes back to where the sheet was opened from, without scrolling the list.
    const go = $("compare-go");
    (go.disabled || $("compare-bar").hidden ? $("board-title") : go).focus({ preventScroll: true });
  };
  const sheet = makeSheet(closeCompare);
  const reveal = (id) => {
    // Make sure the row is on the board: past the top rows, or in the folded group.
    const row = [...groups.match, ...groups.noPrice, ...groups.other].find((r) => r.town.id === id);
    if (!row) return;
    if (row.group === "match" && groups.match.indexOf(row) >= TOP_ROWS) view.showAll = true;
    if (row.group === "other") view.unfolded.add("other");
  };
  const actions = {
    toggle(id) {
      const opening = view.open !== id;
      view.open = opening ? id : null;
      view.selected = opening ? id : null;
      draw();
      $(`row-${id}`)?.querySelector(".line")?.focus();
      if (opening && m) {
        const marker = m.markers.get(id);
        if (marker) {
          m.map.panTo(marker.getLatLng());
          marker.openPopup();
        }
      }
    },
    fromMap(id) {
      view.open = id;
      view.selected = id;
      reveal(id);
      draw();
      m?.markers.get(id)?.openPopup();
      $(`row-${id}`)?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    },
    showAll() {
      view.showAll = true;
      draw();
    },
    hover(id, on) {
      m?.markers.get(id)?.getElement()?.querySelector(".pill")?.classList.toggle("hot", on);
    },
    compare(id) {
      // draw() rebuilds the buttons, so remember where the keyboard was and put it back.
      const from = document.activeElement;
      const focusRow = from?.closest?.(".row")?.id;
      const chips = [...document.querySelectorAll("#compare-chips .chip")];
      const cols = [...document.querySelectorAll("#compare-table .col-x")];
      const chipAt = chips.indexOf(from);
      const colAt = cols.indexOf(from);
      view.state = { ...view.state, compare: toggleCompare(view.state.compare, id) };
      if (view.state.compare.length < 2) view.comparing = false;
      draw();
      syncUrl();
      if (focusRow) $(focusRow)?.querySelector(".cmp")?.focus();
      else if (chipAt >= 0) {
        // The next chip, else the Compare button, else the board.
        const left = document.querySelectorAll("#compare-chips .chip");
        const go = $("compare-go");
        (left[Math.min(chipAt, left.length - 1)] ?? (go.disabled ? $("board-title") : go)).focus();
      } else if (colAt >= 0) {
        // The next column's ×, else (the table closed) the board.
        const left = document.querySelectorAll("#compare-table .col-x");
        const next = view.comparing ? left[Math.min(colAt, left.length - 1)] : null;
        (next ?? $("board-title")).focus();
      }
    },
  };
  $("compare-go").addEventListener("click", showCompare);
  $("compare-close").addEventListener("click", () => closeCompare());
  const update = () => {
    // changeChoices drops the budget when the mode changes; fillForm then puts the slider on "Any".
    // The towns to compare stay: the table follows the new office area, mode and flat type.
    view.state = { ...changeChoices(view.state, formQuery(view.state), data), compare: view.state.compare };
    view.open = null;
    view.selected = null;
    view.showAll = false;
    groups = rank(data, view.state);
    fillForm(data, view.state);
    draw();
  };
  // "input" fires while a slider is being dragged, so the list answers under the finger; the
  // address bar is written once the drag ends ("change"), not on every step.
  $("choices").addEventListener("input", (e) => {
    if (e.target.id === "budget") e.target.dataset.moved = "1";
    update();
  });
  $("choices").addEventListener("change", syncUrl);
  $("choices").addEventListener("submit", (e) => {
    e.preventDefault();
    update();
    syncUrl();
  });
  // The map sticks under the choices card on a wide screen: tell the CSS how tall the card is.
  if (typeof ResizeObserver === "function") {
    new ResizeObserver(() => {
      document.documentElement.style.setProperty("--choices", `${Math.ceil($("choices").getBoundingClientRect().height)}px`);
    }).observe($("choices"));
  }
  renderSources(data);
  setUpShare();
  fillForm(data, view.state);
  // A town to show: ?town= (older links), or the one town of ?compare= (the town pages' link,
  // which then asks for a second town in the bar).
  const focusTown = view.state.town ?? (view.state.compare.length === 1 ? view.state.compare[0] : null);
  if (focusTown) {
    view.open = focusTown;
    view.selected = focusTown;
    reveal(focusTown);
  }
  draw();
  if (!view.comparing && focusTown) {
    m?.markers.get(focusTown)?.openPopup();
    $(`row-${focusTown}`)?.scrollIntoView({ block: "center" });
  }
  syncUrl();
}

main();
