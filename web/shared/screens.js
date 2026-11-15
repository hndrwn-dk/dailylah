// "Four tabs for your day": the four real screenshots in one phone that you swipe, at every width.
// The screen follows the finger; a flick carries to the next tab, the first and last tab resist
// softly instead of stopping dead, and the marker in the tab bar slides with the screen. The tab
// name and its caption sit beside the phone. It plays in turn while on screen until someone swipes
// or taps a tab. Without JS the screenshots stay as cards with their captions (a sideways row on
// a phone, 2 x 2, then 4 across): this script builds the phone out of that same list.
// With reduced motion nothing plays by itself and a tab change is immediate.

import { Spring, Velocity, calm, clamp, project, rubber } from "./spring.js";

const DWELL = 4500; // ms a tab stays while it plays in turn
const list = document.querySelector("[data-shots]");

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

if (list) {
  const items = [...list.querySelectorAll("li")];
  const n = items.length;
  const names = items.map((li) => li.querySelector("h3").textContent);
  const captions = items.map((li) => li.querySelector("figcaption p").textContent);

  // Beside the phone: which tab, its name and what it holds.
  const stage = el("div", "tabs-stage");
  const copy = el("div", "tab-copy");
  const kicker = el("p", "kicker");
  const title = el("h3", "tab-title");
  const text = el("p", "tab-text");
  const dots = el("div", "dots");
  dots.setAttribute("aria-hidden", "true");
  const fills = items.map(() => {
    const dot = el("span");
    const fill = el("i");
    dot.append(fill);
    dots.append(dot);
    return fill;
  });
  copy.append(kicker, title, text, dots, el("p", "hint", "Swipe the phone, or tap a tab."));

  // The phone: the list of screenshots becomes the strip that slides inside it.
  const device = el("div", "device");
  const pager = el("div", "pager");
  const bar = el("div", "tabbar");
  bar.setAttribute("role", "tablist");
  bar.setAttribute("aria-label", "Tabs of the app");
  const marker = el("span", "ind");
  bar.append(marker);
  const buttons = names.map((name, i) => {
    const b = el("button", null, name);
    b.type = "button";
    b.setAttribute("role", "tab");
    b.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      stop();
      go(i); // on the press, not the release
    });
    b.addEventListener("keydown", (e) => {
      const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
      if (step) {
        const to = clamp(shown + step, 0, n - 1);
        stop();
        go(to);
        buttons[to].focus();
      } else if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        stop();
        go(i);
      }
    });
    bar.append(b);
    return b;
  });
  list.before(stage);
  pager.append(list);
  device.append(el("span", "notch"), pager, bar);
  stage.append(copy, device);
  list.classList.add("track");
  for (const img of list.querySelectorAll("img")) {
    img.draggable = false;
    img.loading = "eager"; // the next screen must be there before a swipe brings it in
  }

  let width = pager.clientWidth;
  let shown = -1;
  let auto = !calm();
  let onScreen = false;
  let timer = 0;

  const pos = new Spring(0, { response: 0.38, damping: 1 });
  pos.onUpdate = (x) => {
    list.style.transform = `translate3d(${x}px,0,0)`;
    const p = width ? -x / width : 0;
    marker.style.transform = `translateX(${clamp(p, -0.15, n - 0.85) * 100}%)`;
    fills.forEach((fill, i) => (fill.style.transform = `scaleX(${clamp(1 - Math.abs(p - i), 0, 1)})`));
    const near = clamp(Math.round(p), 0, n - 1);
    if (near !== shown) setTab(near);
  };

  function setTab(i) {
    shown = i;
    items.forEach((li, k) => {
      if (k === i) li.removeAttribute("aria-hidden");
      else li.setAttribute("aria-hidden", "true");
    });
    buttons.forEach((b, k) => {
      b.setAttribute("aria-selected", String(k === i));
      b.tabIndex = k === i ? 0 : -1;
    });
    kicker.textContent = `Tab ${i + 1} of ${n}`;
    title.textContent = names[i];
    text.textContent = captions[i];
    schedule();
  }

  /** Slide to tab i, carrying the speed of the swipe that just ended. */
  function go(i, velocity = 0, slow = false) {
    pos.to(-clamp(i, 0, n - 1) * width, {
      velocity,
      response: slow ? 0.6 : 0.38,
      damping: Math.abs(velocity) > 400 ? 0.82 : 1, // a little bounce only after a flick
    });
  }

  function schedule() {
    clearTimeout(timer);
    if (auto && onScreen) timer = setTimeout(() => go((shown + 1) % n, 0, true), DWELL);
  }

  function stop() {
    auto = false;
    clearTimeout(timer);
  }

  // Drag: wait for 8 px to tell a swipe from a page scroll, then follow the finger 1:1.
  let drag = null;
  pager.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    pos.stop(); // grab it mid-flight
    drag = { id: e.pointerId, x0: e.clientX, y0: e.clientY, from: pos.x, axis: null, speed: new Velocity() };
    drag.speed.add(pos.x, e.timeStamp);
  });
  pager.addEventListener("pointermove", (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x0;
    const dy = e.clientY - drag.y0;
    if (!drag.axis) {
      if (Math.hypot(dx, dy) < 8) return;
      drag.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
      if (drag.axis === "y") return release(0);
      pager.setPointerCapture(e.pointerId);
      pager.classList.add("dragging");
      stop();
    }
    const min = -(n - 1) * width;
    let x = drag.from + dx;
    if (x > 0) x = rubber(x, width);
    else if (x < min) x = min - rubber(min - x, width);
    pos.jump(x);
    drag.speed.add(x, e.timeStamp);
  });
  function release(velocity) {
    if (!drag) return;
    const start = Math.round(-drag.from / width);
    const rest = pos.x + project(velocity, 0.99);
    // At most one tab per swipe, toward where the flick was heading.
    const target = clamp(clamp(Math.round(-rest / width), start - 1, start + 1), 0, n - 1);
    drag = null;
    pager.classList.remove("dragging");
    go(target, velocity);
  }
  pager.addEventListener("pointerup", (e) => {
    if (drag && e.pointerId === drag.id) release(drag.axis === "x" ? drag.speed.get() : 0);
  });
  pager.addEventListener("pointercancel", () => release(0));

  new ResizeObserver(() => {
    width = pager.clientWidth;
    if (!drag) pos.jump(-Math.max(shown, 0) * width);
  }).observe(pager);
  new IntersectionObserver(([e]) => {
    onScreen = e.isIntersecting;
    schedule();
  }, { threshold: 0.5 }).observe(device);
  pos.onUpdate(0);
}
