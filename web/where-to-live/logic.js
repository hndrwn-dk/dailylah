// Pure logic for /where-to-live: reading the URL, filtering and ranking towns, and labels.
// No DOM here, so web/tests/logic.test.mjs can run it in Node. Data: /data/where-to-live.json
// (backend/app/where_to_live.py, docs/WHERE_TO_LIVE.md).

export const MODES = ["rent", "buy"];
export const MAX_MINUTES = [30, 45, 60, 75, 90];
export const DEFAULTS = { area: "cbd", mode: "rent", flat: "4-ROOM", budget: null, max: null };

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
  return { area, mode, flat, budget, max };
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
  for (const key of ["area", "mode", "flat", "budget", "max"]) {
    const v = state[key];
    if (v != null && v !== DEFAULTS[key]) q.set(key, String(v));
  }
  const s = q.toString();
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
