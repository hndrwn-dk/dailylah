// "Four tabs for your day" on a phone: instead of a sideways row of screenshots with their
// captions, a deck. One screen at a time with the next peeking behind; they play in turn (DWELL ms
// each) while the section is on screen, with the tab names as buttons and the current tab's
// caption under them. A tap on a button or a swipe takes over and stops the play. Wide screens
// keep the 4-across row with captions (CSS). Without JS the sideways row stays as it is.

const DWELL = 4000;
const list = document.querySelector("[data-shots]");
const narrow = matchMedia("(max-width: 999px)");
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;

if (list) {
  const items = [...list.querySelectorAll("li")];
  const tabs = document.createElement("div");
  tabs.className = "shot-tabs";
  tabs.setAttribute("aria-label", "Tabs of the app");
  const cap = document.createElement("p");
  cap.className = "shot-cap";
  const buttons = items.map((li, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = li.querySelector("h3").textContent;
    b.append(document.createElement("i"));
    b.addEventListener("click", () => {
      stop();
      show(i);
    });
    tabs.append(b);
    return b;
  });
  list.after(tabs, cap);
  list.classList.add("deck");
  tabs.style.setProperty("--dwell", `${DWELL}ms`);

  let cur = 0;
  let timer = 0;
  let playing = !calm;
  let onScreen = false;

  function show(i) {
    const prev = cur;
    cur = (i + items.length) % items.length;
    items.forEach((li, k) => {
      li.classList.toggle("cur", k === cur);
      li.classList.toggle("next", k === (cur + 1) % items.length);
      li.classList.toggle("gone", k === prev && k !== cur);
      li.querySelector("img").setAttribute("aria-hidden", String(k !== cur));
    });
    buttons.forEach((b, k) => {
      b.setAttribute("aria-pressed", String(k === cur));
      b.classList.remove("run");
    });
    cap.textContent = items[cur].querySelector("figcaption p").textContent;
    // Restart the progress bar on the current tab.
    if (playing && onScreen && narrow.matches) {
      void buttons[cur].offsetWidth;
      buttons[cur].classList.add("run");
    }
    schedule();
  }

  function schedule() {
    clearTimeout(timer);
    if (playing && onScreen && narrow.matches) timer = setTimeout(() => show(cur + 1), DWELL);
  }

  function stop() {
    playing = false;
    clearTimeout(timer);
    buttons.forEach((b) => b.classList.remove("run"));
  }

  // Swipe left or right on the deck.
  let x0 = null;
  list.addEventListener("pointerdown", (e) => (x0 = e.clientX));
  list.addEventListener("pointerup", (e) => {
    if (x0 === null) return;
    const dx = e.clientX - x0;
    x0 = null;
    if (Math.abs(dx) > 40) {
      stop();
      show(cur + (dx < 0 ? 1 : -1));
    }
  });

  new IntersectionObserver(([e]) => {
    onScreen = e.isIntersecting;
    show(cur);
  }, { threshold: 0.5 }).observe(list);
  narrow.addEventListener("change", () => show(cur));
  show(0);
}
