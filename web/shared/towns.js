// "Where to live?" on the landing page: a small taste of the tool. Six HDB towns ranked by travel
// time to an office; pick another office and the rows slide to their new order. The minutes come
// from the same published bundle as /where-to-live (/data/where-to-live.json), never from this
// file. Without JS, or when the bundle does not load, the card is just its words and two links.

import { Spring, clamp } from "./spring.js";

const OFFICES = ["cbd", "one-north", "jurong-east"];
const TOWNS = ["bishan", "queenstown", "tampines", "punggol", "jurong-west", "woodlands"];
const ROW = 46; // px per row
const FULL = 70; // minutes that fill the bar
// (the tests import minutesTo in Node, where there is no page)
const demo = typeof document === "undefined" ? null : document.querySelector("[data-towns]");

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

/** Minutes from a town to an office area; 0 for the office's own town, null without a route. */
export function minutesTo(town, area) {
  const c = town?.commute?.[area];
  if (!c) return null;
  if (c.same_area) return 0;
  return Number.isFinite(c.min) ? c.min : null;
}

async function start() {
  let data;
  try {
    const res = await fetch("/data/where-to-live.json");
    if (!res.ok) return;
    data = await res.json();
  } catch {
    return; // the card stays as it is
  }
  const offices = OFFICES.map((id) => data.areas?.find((a) => a.id === id)).filter(Boolean);
  const towns = TOWNS.map((id) => data.towns?.find((t) => t.id === id)).filter(Boolean);
  if (offices.length < 2 || towns.length < 3) return;

  const seg = el("div", "seg");
  seg.setAttribute("role", "group");
  seg.setAttribute("aria-label", "Your office");
  const list = el("ol", "town-rows");
  list.style.height = `${towns.length * ROW}px`;
  const rows = towns.map((town) => {
    const li = el("li");
    const bar = el("i");
    const track = el("span", "tb");
    track.append(bar);
    const num = el("span", "tm");
    li.append(el("b", null, town.name), track, num);
    list.append(li);
    const y = new Spring(0, { response: 0.45, damping: 0.9 });
    y.onUpdate = (v) => (li.style.transform = `translateY(${v}px)`);
    const w = new Spring(0, { response: 0.5, damping: 1 });
    w.onUpdate = (v) => {
      bar.style.transform = `scaleX(${clamp(v / FULL, 0, 1)})`;
      num.textContent = `${Math.round(v)} min`;
    };
    return { town, li, y, w };
  });

  function rank(office, first) {
    const sorted = rows
      .map((r) => ({ r, min: minutesTo(r.town, office.id) }))
      .filter((x) => x.min !== null)
      .sort((a, b) => a.min - b.min);
    sorted.forEach(({ r, min }, place) => {
      r.li.classList.toggle("best", place === 0);
      if (first) r.y.jump(place * ROW);
      else r.y.to(place * ROW);
      r.w.to(min);
    });
    // Reading order follows the ranking too.
    list.replaceChildren(...sorted.map((x) => x.r.li));
  }

  const buttons = offices.map((office, i) => {
    const b = el("button", null, office.name.replace(/\s*\(.*\)$/, ""));
    b.type = "button";
    b.setAttribute("aria-pressed", String(i === 0));
    const choose = () => {
      buttons.forEach((x, k) => x.setAttribute("aria-pressed", String(k === i)));
      rank(office, false);
    };
    b.addEventListener("pointerdown", (e) => {
      if (e.button === 0) choose();
    });
    b.addEventListener("keydown", (e) => {
      if (e.key !== "Enter" && e.key !== " ") return;
      e.preventDefault();
      choose();
    });
    seg.append(b);
    return b;
  });

  demo.replaceChildren(seg, el("p", "demo-note", "Weekday 08:30 by MRT and bus, minutes"), list);
  demo.hidden = false;
  demo.closest(".tool")?.classList.add("has-demo");
  rank(offices[0], true);
}

if (demo) start();
