// "A day with DailyLah": a clock you drag through the day. The phone's lock screen shows what
// DailyLah would have told you at that time, the words beside it follow, and the card's colour
// drifts from morning to afternoon. A flick carries the clock on and it settles on the nearest
// time; the ends resist softly. It plays through the day while on screen until someone touches it.
// Everything comes from the list in the HTML (time, words and the small picture of each card), so
// without this script the page shows that list as it is. With reduced motion nothing plays by
// itself and the clock moves at once; arrow keys work on the clock either way. The notification
// is announced to a screen reader only once someone moved the clock, never while the day plays.

import { Spring, Velocity, calm, clamp, rubber, settle } from "./spring.js";

const DWELL = 3600; // ms a time stays while the day plays
const STEP = { response: 0.4, damping: 1 }; // a label or a key: always this, whatever ran before
// Hue and saturation of the card behind each time: dawn, haze, clear morning ..., noon, heat, Sunday.
const SKY = [[35, 75], [45, 28], [195, 55], [205, 40], [190, 60], [48, 85], [22, 85], [168, 45]];
const day = document.querySelector("[data-day]");

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

if (day) {
  const stops = [...day.querySelectorAll("li")].map((li) => {
    const title = li.querySelector(".dcard b").textContent;
    return {
      time: li.querySelector("time").textContent,
      title,
      text: li.querySelector(".dcard p").textContent.replace(title, "").trim(),
      mini: li.querySelector(".mini"),
    };
  });
  const n = stops.length;

  // Left: the clock, the times, the words. Right: the lock screen.
  const stage = el("div", "day-stage sticker");
  const copy = el("div", "day-copy");
  const scrub = el("div", "scrub");
  const fill = el("span", "fill");
  const thumb = el("div", "thumb");
  thumb.setAttribute("role", "slider");
  thumb.setAttribute("aria-label", "Time of day");
  thumb.setAttribute("aria-valuemin", "0");
  thumb.setAttribute("aria-valuemax", String(n - 1));
  thumb.tabIndex = 0;
  const ticks = stops.map(() => el("span", "tick"));
  scrub.append(el("span", "line"), fill, ...ticks, thumb);
  const labels = el("div", "stops");
  const labelButtons = stops.map((s, i) => {
    const b = el("button", null, s.time);
    b.type = "button";
    b.addEventListener("click", () => {
      stopPlay();
      clock.to(i * gap(), STEP);
    });
    labels.append(b);
    return b;
  });
  const title = el("h3", "day-title");
  const text = el("p", "day-text");
  const play = el("button", "day-play");
  play.type = "button";
  copy.append(
    el("p", "lead", "Drag the clock through a day. The phone shows what you would have heard, before you needed it."),
    scrub, labels, title, text, play,
  );

  const lock = el("div", "lock");
  const weekday = el("small");
  const big = el("b");
  const clockFace = el("div", "clock");
  clockFace.append(weekday, big);
  const notif = el("div", "notif");
  const app = el("div", "app");
  app.append(el("i", null, "lah"), "DailyLah", el("span", null, "now"));
  const nTitle = el("b", "n-title");
  const nText = el("p");
  const nMini = el("div", "n-mini");
  nMini.setAttribute("aria-hidden", "true");
  notif.append(app, nTitle, nText, nMini);
  lock.append(el("span", "notch"), clockFace, notif, el("span", "home-ind"));

  stage.append(copy, lock);
  day.before(stage);
  day.hidden = true; // the same content, now shown one time at a time

  let length = 1;
  let cur = -1;
  const gap = () => length / (n - 1);
  const clock = new Spring(0, { response: 0.4, damping: 1 });
  clock.onUpdate = (x) => {
    thumb.style.transform = `translateX(${x}px)`;
    fill.style.transform = `scaleX(${clamp(x / length, 0, 1)})`;
    // The colour blends between the two times the clock is between.
    const f = clamp(x / gap(), 0, n - 1);
    const a = SKY[Math.floor(f) % SKY.length];
    const b = SKY[Math.min(n - 1, Math.floor(f) + 1) % SKY.length];
    const t = f - Math.floor(f);
    let h = b[0];
    if (Math.abs(h - a[0]) > 180) h += h < a[0] ? 360 : -360; // the short way round
    stage.style.setProperty("--day-h", (((a[0] + (h - a[0]) * t) % 360) + 360) % 360);
    stage.style.setProperty("--day-s", `${a[1] + (b[1] - a[1]) * t}%`);
    const near = clamp(Math.round(f), 0, n - 1);
    if (near !== cur) show(near);
  };

  function show(i) {
    const dir = i > cur ? 1 : -1;
    cur = i;
    const s = stops[i];
    const timed = s.time.includes(":");
    thumb.setAttribute("aria-valuenow", String(i));
    thumb.setAttribute("aria-valuetext", `${s.time}: ${s.title}`);
    labelButtons.forEach((b, k) => b.classList.toggle("on", k === i));
    title.textContent = s.title;
    text.textContent = s.text;
    weekday.textContent = timed ? "Monday" : "Sunday";
    big.textContent = timed ? s.time : "10:00";
    nTitle.textContent = s.title;
    nText.textContent = s.text;
    nMini.replaceChildren(...(s.mini ? [...s.mini.cloneNode(true).childNodes] : []));
    // The notification drops in from the side the clock came from.
    notif.style.setProperty("--dir", String(dir));
    notif.classList.remove("in");
    void notif.offsetWidth;
    notif.classList.add("in");
  }

  function layout() {
    length = scrub.clientWidth || 1;
    ticks.forEach((tick, i) => (tick.style.left = `${i * gap()}px`));
    labelButtons.forEach((b, i) => (b.style.left = `${i * gap()}px`));
    if (!grab) clock.jump(Math.max(cur, 0) * gap());
  }

  // Drag: grab the clock where it was touched; a press elsewhere on the line glides it there, and
  // a plain click (no move) settles on the time nearest the click, not nearest the half-done glide.
  let grab = null;
  scrub.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    stopPlay();
    clock.stop();
    const left = scrub.getBoundingClientRect().left;
    const onThumb = thumb.contains(e.target);
    grab = { id: e.pointerId, left, offset: onThumb ? e.clientX - left - clock.x : 0, moved: false, speed: new Velocity() };
    scrub.setPointerCapture(e.pointerId);
    scrub.classList.add("dragging");
    if (!onThumb) clock.to(clamp(e.clientX - left, 0, length), { response: 0.3, damping: 1 });
    // The speed is measured from where the press is: on the line the clock has not arrived yet.
    grab.speed.add(onThumb ? clock.x : clamp(e.clientX - left, 0, length), e.timeStamp);
  });
  scrub.addEventListener("pointermove", (e) => {
    if (!grab || e.pointerId !== grab.id) return;
    let x = e.clientX - grab.left - grab.offset;
    if (x < 0) x = -rubber(-x, length * 0.3);
    else if (x > length) x = length + rubber(x - length, length * 0.3);
    grab.moved = true;
    clock.jump(x);
    grab.speed.add(x, e.timeStamp);
  });
  const letGo = (e) => {
    if (!grab || (e && e.pointerId !== grab.id)) return;
    const { moved } = grab;
    const velocity = moved ? grab.speed.get(e?.timeStamp) : 0;
    grab = null;
    scrub.classList.remove("dragging");
    const target = settle(moved ? clock.x : clock.target, velocity, stops.map((_, i) => i * gap()), 0.995);
    if (moved) clock.to(target, { velocity, response: 0.4, damping: Math.abs(velocity) > 300 ? 0.82 : 1 });
    else clock.to(target, { response: 0.4, damping: 1 }); // keeps the speed of the glide
  };
  scrub.addEventListener("pointerup", letGo);
  scrub.addEventListener("pointercancel", letGo);
  thumb.addEventListener("keydown", (e) => {
    const step = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 }[e.key];
    const to = step ? clamp(cur + step, 0, n - 1) : e.key === "Home" ? 0 : e.key === "End" ? n - 1 : null;
    if (to === null) return;
    e.preventDefault();
    stopPlay();
    clock.to(to * gap(), STEP);
  });

  // The day plays by itself while the card is on screen, until someone touches it.
  let playing = !calm();
  let onScreen = false;
  let timer = 0;
  const label = () => {
    play.textContent = playing ? "Pause the day" : "Play the day"; // the words say the state
  };
  function tick() {
    clearTimeout(timer);
    if (!playing || !onScreen) return;
    timer = setTimeout(() => {
      clock.to(((cur + 1) % n) * gap(), { response: 0.9, damping: 1 });
      tick();
    }, DWELL);
  }
  function stopPlay() {
    playing = false;
    clearTimeout(timer);
    label();
    notif.setAttribute("aria-live", "polite"); // someone took the clock: now it speaks
  }
  play.addEventListener("click", () => {
    if (playing) return stopPlay();
    playing = true;
    notif.removeAttribute("aria-live");
    label();
    tick();
  });
  label();
  // A keyboard or screen reader on the clock: the day stops, so the value it reads holds still.
  thumb.addEventListener("focus", () => {
    if (playing) stopPlay();
  });

  new ResizeObserver(layout).observe(scrub);
  new IntersectionObserver(([e]) => {
    onScreen = e.isIntersecting;
    tick();
  }, { threshold: 0.35 }).observe(stage);
  layout();
  show(0);
  clock.onUpdate(0);
}
