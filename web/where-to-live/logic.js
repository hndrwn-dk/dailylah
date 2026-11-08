// Pure logic for /where-to-live: reading the URL, filtering and ranking towns, and labels.
// No DOM here, so web/tests/logic.test.mjs can run it in Node. Data: /data/where-to-live.json
// (backend/app/where_to_live.py, docs/WHERE_TO_LIVE.md).

export const MODES = ["rent", "buy"];
export const MAX_MINUTES = [30, 45, 60, 75, 90];
export const DEFAULTS = { area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null, town: null, compare: [] };

/** Towns side by side in the comparison, at most. */
export const MAX_COMPARE = 3;

/** Working days in a month: the commute is there and back on each. */
export const WORKDAYS = 22;

const FLAT_LABELS = {
  "1-ROOM": "1-room",
  "2-ROOM": "2-room",
  "3-ROOM": "3-room",
  "4-ROOM": "4-room",
  "5-ROOM": "5-room",
  EXECUTIVE: "Executive",
};

export function flatLabel(flat) {
  return FLAT_LABELS[flat] ?? String(flat);
}

/** Flat types that have at least one price for this mode, in the JSON's order. */
export function flatTypes(data, mode) {
  const key = mode === "buy" ? "resale" : "rent";
  const seen = [];
  for (const town of data.towns) {
    for (const [flat, cell] of Object.entries(town[key] ?? {})) {
      if (cell && !seen.includes(flat)) seen.push(flat);
    }
  }
  const order = Object.keys(FLAT_LABELS);
  return seen.sort((a, b) => order.indexOf(a) - order.indexOf(b));
}

function positiveInt(value, limit) {
  if (value == null || !/^\d{1,9}$/.test(value)) return null;
  const n = Number(value);
  return n > 0 && n <= limit ? n : null;
}

/** Choices from a query string, each checked against the data; anything else is the default. */
export function readQuery(search, data) {
  const q = new URLSearchParams(search);
  const areas = data.areas.map((a) => a.id);
  const area = areas.includes(q.get("area")) ? q.get("area") : areas.includes(DEFAULTS.area) ? DEFAULTS.area : areas[0];
  const mode = MODES.includes(q.get("mode")) ? q.get("mode") : DEFAULTS.mode;
  const flats = flatTypes(data, mode);
  const flat = flats.includes(q.get("flat")) ? q.get("flat") : flats.includes(DEFAULTS.flat) ? DEFAULTS.flat : flats[0];
  const budget = positiveInt(q.get("budget"), mode === "buy" ? 10_000_000 : 100_000);
  const maxRaw = positiveInt(q.get("max"), 999);
  const max = MAX_MINUTES.includes(maxRaw) ? maxRaw : null;
  // A town to open on load (links from the town pages); only ids from the data.
  const town = data.towns.some((t) => t.id === q.get("town")) ? q.get("town") : null;
  const compare = compareIds(q.get("compare"), data);
  return { area, mode, flat, budget, max, town, compare };
}

/**
 * Towns to compare from "?compare=punggol,bedok": ids from the data only, each once, in the given
 * order, at most MAX_COMPARE. Anything else is dropped.
 */
export function compareIds(value, data) {
  const known = new Set(data.towns.map((t) => t.id));
  const out = [];
  for (const id of String(value ?? "").split(",")) {
    if (known.has(id) && !out.includes(id) && out.length < MAX_COMPARE) out.push(id);
  }
  return out;
}

/** The compare list with a town added or removed; unchanged when adding to a full list. */
export function toggleCompare(list, id) {
  if (list.includes(id)) return list.filter((x) => x !== id);
  return list.length < MAX_COMPARE ? [...list, id] : list;
}

/**
 * New choices from the form. A budget is a monthly rent or a total price, so it is dropped when
 * the mode changes (a rent of 3500 must not become a resale budget of $3,500).
 */
export function changeChoices(prev, search, data) {
  const next = readQuery(search, data);
  return next.mode !== prev.mode ? { ...next, budget: null } : next;
}

/** The query string for a state, leaving out defaults so shared links stay short. */
export function writeQuery(state) {
  const q = new URLSearchParams();
  for (const key of ["area", "mode", "flat", "budget", "max", "town"]) {
    const v = state[key];
    if (v != null && v !== DEFAULTS[key]) q.set(key, String(v));
  }
  if (state.compare?.length) q.set("compare", state.compare.join(","));
  // Town ids are [a-z0-9-], so the commas can stay readable: ?compare=punggol,bedok
  const s = q.toString().replace(/%2C/g, ",");
  return s ? `?${s}` : "";
}

/** "2026-Q3" -> "Q3 2026". */
export function quarterLabel(q) {
  const m = /^(\d{4})-Q([1-4])$/.exec(String(q ?? ""));
  return m ? `Q${m[2]} ${m[1]}` : "";
}

const money = new Intl.NumberFormat("en-SG", { maximumFractionDigits: 0 });

/**
 * The two picks for the summary card, from the towns that fit the choices and have both a travel
 * time and a price: the fastest (cheaper wins a tie) and the best value (the cheapest among those
 * with a travel time at or under the median of the candidates; faster wins a tie). null when no
 * town qualifies.
 */
export function highlights(groups) {
  const pool = groups.match.filter((r) => r.commute && r.price);
  if (!pool.length) return null;
  const byFast = [...pool].sort((a, b) => a.minutes - b.minutes || a.price.median - b.price.median);
  const mins = pool.map((r) => r.minutes).sort((a, b) => a - b);
  const mid = mins.length >> 1;
  const median = mins.length % 2 ? mins[mid] : (mins[mid - 1] + mins[mid]) / 2;
  const value = pool
    .filter((r) => r.minutes <= median)
    .sort((a, b) => a.price.median - b.price.median || a.minutes - b.minutes)[0];
  return { fastest: byFast[0], value };
}

/**
 * Estimated monthly commute for a row: fares (dollars, adult card fare there and back on WORKDAYS
 * days, null when OneMap gave no fare), hours on the road, and for rent the all-in total (rent +
 * fares). The town of the office area itself counts as no commute. null without a route.
 */
export function monthlyCost(state, row) {
  const c = row.commute;
  if (!c) return null;
  const same = Boolean(c.same_area);
  const fares = same ? 0 : Number.isInteger(c.fare) ? Math.round((c.fare * 2 * WORKDAYS) / 100) : null;
  const hours = same ? 0 : Math.round((c.min * 2 * WORKDAYS) / 60);
  const total = state.mode === "rent" && row.price && fares != null ? row.price.median + fares : null;
  return { fares, hours, total, same };
}

/** "≈ $3,535/mo all-in with fares, 26 h on the road a month (estimate)", or the known parts. */
export function allInText(state, row) {
  const m = monthlyCost(state, row);
  if (!m) return "";
  if (m.same) return "In this area: no commute to pay for (estimate)";
  const parts = [];
  if (m.total != null) parts.push(`≈ $${money.format(m.total)}/mo all-in with fares`);
  else if (m.fares != null) parts.push(`≈ $${money.format(m.fares)}/mo in fares`);
  parts.push(`${m.hours} h on the road a month`);
  return `${parts.join(", ")} (estimate)`;
}

/** "Bishan — 18 min, $3,700/mo" (or "Woodlands — in this area, $3,100/mo"). */
export function highlightText(row, mode) {
  const time = row.commute.same_area ? "in this area" : `${row.commute.min} min`;
  return `${row.town.name} — ${time}, ${shortPrice(mode, row.price)}`;
}

/** Short price for a board row: "$3,400/mo" (rent), "$559,400" (resale) or "No data". */
export function shortPrice(mode, cell) {
  if (!cell) return "No data";
  const amount = `$${money.format(cell.median)}`;
  return mode === "buy" ? amount : `${amount}/mo`;
}

/** Travel time band for colour: 1 (up to 20 min) .. 4 (over 50 min); 0 = same area. */
export const BANDS = [20, 35, 50];
export function timeBand(commute) {
  if (!commute) return null;
  if (commute.same_area) return 0;
  const i = BANDS.findIndex((limit) => commute.min <= limit);
  return i === -1 ? BANDS.length + 1 : i + 1;
}

/** Text in a map pill: "22′", or "Here" for the office area's own town. */
export function pillText(commute) {
  if (!commute) return "–";
  return commute.same_area ? "Here" : `${commute.min}′`;
}

function transfersText(n) {
  return n === 0 ? "no transfer" : n === 1 ? "1 transfer" : `${n} transfers`;
}

/** Second line of an opened row: station and transfers. */
export function routeDetail(row) {
  const c = row.commute;
  if (!c) return "No route data";
  if (c.same_area) return `In this area (${row.town.station} MRT)`;
  return `From ${row.town.station} MRT, ${transfersText(c.transfers)}`;
}

/** Third line of an opened row: what the price is and its own quarter. */
export function priceDetail(state, cell) {
  const what = `${flatLabel(state.flat)} median ${state.mode === "buy" ? "resale price" : "rent"}`;
  return cell ? `${what}, ${quarterLabel(cell.quarter)}` : `${what}: not enough data`;
}

export function priceText(mode, cell) {
  if (!cell) return "Not enough data";
  const amount = `$${money.format(cell.median)}`;
  return mode === "buy" ? amount : `${amount}/month`;
}

/** "4-room median rent $3,400/month (Q3 2026)", with the quarter of that figure. */
export function priceLine(state, cell) {
  const what = state.mode === "buy" ? "median resale" : "median rent";
  const head = `${flatLabel(state.flat)} ${what}`;
  if (!cell) return `${head}: not enough data`;
  return `${head} ${priceText(state.mode, cell)} (${quarterLabel(cell.quarter)})`;
}

/** Why a town is outside the choices, for the board. */
export function reasonText(row, state) {
  if (row.reason === "far") return `Over ${state.max} min`;
  if (row.reason === "budget") return "Over your budget";
  if (row.reason === "route") return "No route data";
  return "";
}

export function commuteText(c) {
  if (!c) return "No route data";
  if (c.same_area) return "In this area";
  const t = c.transfers === 0 ? "no transfer" : c.transfers === 1 ? "1 transfer" : `${c.transfers} transfers`;
  return `${c.min} min, ${t}`;
}

/**
 * Towns in three groups for the chosen office area, flat type and limits:
 * - match: travel time known and within `max`, and price within `budget` (any price, or none,
 *   when no budget is set),
 * - noPrice: a budget is set but the town has no price for this flat type,
 * - other: too far, over budget, or no route data.
 * Each group is sorted by travel time (same area first), then price. A row in "other" has a
 * reason: "route" (no route data), "far" (over `max`) or "budget" (over `budget`).
 */
export function rank(data, state) {
  const key = state.mode === "buy" ? "resale" : "rent";
  const rows = data.towns.map((town) => {
    const commute = town.commute?.[state.area] ?? null;
    const price = town[key]?.[state.flat] ?? null;
    const minutes = !commute ? Infinity : commute.same_area ? 0 : commute.min;
    const nearEnough = commute !== null && (state.max == null || minutes <= state.max);
    let group = "match";
    let reason = null;
    if (!commute) [group, reason] = ["other", "route"];
    else if (!nearEnough) [group, reason] = ["other", "far"];
    else if (state.budget != null && !price) group = "noPrice";
    else if (state.budget != null && price.median > state.budget) [group, reason] = ["other", "budget"];
    return { town, commute, price, minutes, group, reason };
  });
  const byTimeThenPrice = (a, b) =>
    a.minutes - b.minutes ||
    (a.price?.median ?? Infinity) - (b.price?.median ?? Infinity) ||
    a.town.name.localeCompare(b.town.name);
  const out = { match: [], noPrice: [], other: [] };
  for (const row of rows.sort(byTimeThenPrice)) out[row.group].push(row);
  return out;
}

// ---------------------------------------------------------------- compare

/** "Punggol, Bedok and Sengkang" for the compare bar and headings. */
export function namesText(names) {
  if (names.length < 2) return names.join("");
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/** The compare bar's line: who is picked and what to do next. */
export function compareBarText(names) {
  if (!names.length) return "";
  if (names.length === 1) return `${names[0]}: add a town to compare`;
  return namesText(names);
}

/**
 * The comparison table for the towns in state.compare, for the chosen office area, mode and flat
 * type: { towns, lines }, one column per town and per line a label and one cell per town
 * ({ text, value, best }). value is the number compared (lower is better), null when unknown.
 * best marks the lowest value, ties included, only when at least two towns have one. The town of
 * the office area itself counts as 0 minutes, no transfer and no fare.
 */
export function compareTable(data, state) {
  const key = state.mode === "buy" ? "resale" : "rent";
  const area = data.areas.find((a) => a.id === state.area);
  const towns = state.compare.map((id) => data.towns.find((t) => t.id === id)).filter(Boolean);
  const rows = towns.map((town) => {
    const row = { town, commute: town.commute?.[state.area] ?? null, price: town[key]?.[state.flat] ?? null };
    return { ...row, cost: monthlyCost(state, row) };
  });
  const cell = (text, value = null) => ({ text, value, best: false });
  const route = (c, same, known, unknown = "–") => (!c ? cell("–") : c.same_area ? same : known ?? cell(unknown));
  const lines = [
    {
      key: "time",
      label: `Time to ${area?.name ?? "the office"}`,
      cells: rows.map(({ commute: c }) =>
        !c ? cell("No route data") : route(c, cell("In this area", 0), cell(`${c.min} min`, c.min)),
      ),
    },
    {
      key: "transfers",
      label: "Transfers",
      cells: rows.map(({ commute: c }) => route(c, cell("None", 0), c && cell(transfersCell(c.transfers), c.transfers))),
    },
    {
      key: "fare",
      label: "Fare per trip (adult card)",
      cells: rows.map(({ commute: c }) =>
        route(c, cell("None", 0), Number.isInteger(c?.fare) ? cell(`$${(c.fare / 100).toFixed(2)}`, c.fare) : null, "Not known"),
      ),
    },
    {
      key: "price",
      label: `${flatLabel(state.flat)} median ${state.mode === "buy" ? "resale price" : "rent"}`,
      cells: rows.map(({ price: p }) =>
        p ? cell(`${priceText(state.mode, p)} (${quarterLabel(p.quarter)})`, p.median) : cell("Not enough data"),
      ),
    },
    state.mode === "buy"
      ? {
          key: "fares",
          label: "Fares a month",
          cells: rows.map(({ cost: m }) => (m?.fares != null ? cell(`≈ $${money.format(m.fares)}`, m.fares) : cell("–"))),
        }
      : {
          key: "allin",
          label: "All-in a month (rent + fares)",
          cells: rows.map(({ cost: m }) => (m?.total != null ? cell(`≈ $${money.format(m.total)}`, m.total) : cell("–"))),
        },
    {
      key: "hours",
      label: "On the road a month",
      cells: rows.map(({ cost: m }) => (m ? cell(`${m.hours} h`, m.hours) : cell("–"))),
    },
  ];
  for (const line of lines) {
    const known = line.cells.filter((c) => c.value != null);
    if (known.length < 2) continue;
    const low = Math.min(...known.map((c) => c.value));
    for (const c of known) c.best = c.value === low;
  }
  return { towns, lines };
}

function transfersCell(n) {
  return n === 0 ? "No transfer" : n === 1 ? "1 transfer" : `${n} transfers`;
}
