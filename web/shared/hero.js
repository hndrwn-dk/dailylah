// The landing page hero. Without this script the page is as it always was: the questions are
// marked in turn by a CSS clock and the bus board is a still example.
// With it: the questions can be tapped, the small scene beside "Know" and a short answer in the
// stop card follow the question, and the example bus board counts down like the app's. The
// questions still play in turn until one is tapped; hovering or focusing them holds the turn.
// With reduced motion nothing plays by itself: bus 36 is shown, and a tap still answers.

import { calm } from "./spring.js";

const DWELL = 3400; // ms a question stays before the next one
const hero = document.querySelector("[data-hero]");

if (hero) {
  const asks = [...hero.querySelectorAll(".q[data-answer]")];
  const scenes = [...hero.querySelectorAll(".scene")];
  const card = hero.querySelector("[data-answer-card]");
  const rows = [...hero.querySelectorAll(".board .row")];
  if (asks.length && card) questions(asks, scenes, card, rows);
  if (rows.length) board(rows);
}

function questions(asks, scenes, card, rows) {
  const title = card.querySelector("b");
  const line = card.querySelector("span");
  const quiet = calm();
  let auto = !quiet;
  let cur = -1;

  hero.classList.add("live");
  hero.style.setProperty("--dwell", `${DWELL}ms`);
  card.hidden = false;

  function pick(i, byUser) {
    if (byUser) auto = false;
    const from = cur < 0 ? 0 : byUser ? Math.sign(i - cur) : 1;
    if (i === cur && !byUser) return;
    cur = i;
    asks.forEach((q, k) => {
      q.classList.remove("run");
      q.classList.toggle("on", k === i && !auto);
      q.setAttribute("aria-pressed", String(k === i));
    });
    scenes.forEach((s, k) => s.classList.toggle("show", k === i));
    const [head, text] = asks[i].dataset.answer.split("|");
    title.textContent = head;
    line.textContent = text ?? "";
    rows.forEach((r, k) => r.classList.toggle("hl", asks[i].dataset.row === String(k)));
    // The answer comes in from the side the question sits on.
    card.style.setProperty("--from", String(from));
    card.classList.remove("in");
    void card.offsetWidth;
    card.classList.add("in");
    if (auto) {
      void asks[i].offsetWidth;
      asks[i].classList.add("run"); // the amber marker fills for DWELL, then the next question
    }
  }

  asks.forEach((q, i) => {
    q.setAttribute("role", "button");
    q.tabIndex = 0;
    q.addEventListener("pointerdown", (e) => {
      if (e.button === 0) pick(i, true); // answer on the press, not the release
    });
    q.addEventListener("keydown", (e) => {
      if (e.key !== "Enter" && e.key !== " ") return;
      e.preventDefault();
      pick(i, true);
    });
    q.addEventListener("animationend", (e) => {
      if (auto && e.animationName === "fillq") pick((i + 1) % asks.length, false);
    });
  });

  // Reduced motion: the bus, as the page shows without the script.
  const bus = asks.findIndex((q) => q.dataset.row !== undefined);
  pick(quiet && bus >= 0 ? bus : 0, false);
  if (quiet) asks[cur].classList.add("on");
}

/** The example board counts down: "Arr" under a minute, then the next bus takes the row. */
function board(rows) {
  const buses = rows.map((row) => {
    const eta = row.querySelector(".eta");
    const then = row.querySelector(".then");
    const minutes = Number.parseInt(eta.textContent, 10);
    return {
      eta,
      then,
      label: "",
      left: Number.isNaN(minutes) ? 40 : minutes * 60 + 20,
      next: (Number.parseInt(then.textContent.replace(/\D+/g, ""), 10) || 8) * 60,
    };
  });

  function draw(bus) {
    const label = bus.left < 60 ? "Arr" : String(Math.floor(bus.left / 60));
    if (label !== bus.label) {
      bus.label = label;
      if (label === "Arr") {
        const badge = document.createElement("span");
        badge.className = "arr";
        badge.textContent = "Arr";
        bus.eta.replaceChildren(badge);
      } else {
        const unit = document.createElement("small");
        unit.textContent = "min";
        bus.eta.replaceChildren(label, unit);
      }
    }
    const then = `then ${Math.round(bus.next / 60)} min`;
    if (bus.then.textContent !== then) bus.then.textContent = then;
  }

  buses.forEach(draw);
  setInterval(() => {
    if (document.hidden) return;
    for (const bus of buses) {
      bus.left -= 1;
      if (bus.left < 0) {
        bus.left = bus.next;
        bus.next = (6 + Math.floor(Math.random() * 9)) * 60;
      }
      draw(bus);
    }
  }, 1000);
}
