// Layout checks of dailylah.sg in a real browser at phone width (web.yml, "layout (Playwright)").
// The site is served from web/ with the same URL rewrites as web/vercel.json; nothing outside is
// fetched (map tiles and the like are blocked). Chrome: $CHROME_PATH, else the runner's Chrome.
//
//   cd web/tests/e2e && npm ci --ignore-scripts && node --test layout.e2e.mjs

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml",
  ".woff2": "font/woff2", ".ico": "image/x-icon",
};

/** The file web/vercel.json serves for a path (cleanUrls and the where-to-live rewrites). */
function fileFor(urlPath) {
  const p = decodeURIComponent(urlPath.split("?")[0]);
  if (p === "/") return "index.html";
  if (p === "/where-to-live" || p === "/where-to-live/") return "where-to-live/index.html";
  if (p === "/where-to-live/towns") return "where-to-live-towns/index.html";
  const town = p.match(/^\/where-to-live\/([a-z0-9-]+)$/);
  if (town) return `where-to-live-towns/${town[1]}.html`;
  return p.slice(1);
}

let server;
let base;
let browser;

before(async () => {
  server = createServer(async (req, res) => {
    const file = normalize(join(ROOT, fileFor(req.url)));
    if (!file.startsWith(ROOT)) return res.writeHead(403).end();
    try {
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" }).end(body);
    } catch {
      res.writeHead(404).end();
    }
  });
  await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
  base = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch(
    process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : { channel: "chrome" },
  );
});

after(async () => {
  await browser?.close();
  await new Promise((ok) => server?.close(ok));
});

/** The page at 360 px; [ready]: a selector to wait for when the page renders after a fetch. */
async function phone(path, ready) {
  const page = await browser.newPage({ viewport: { width: 360, height: 800 } });
  await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const res = await page.goto(base + path, { waitUntil: "load" });
  assert.ok(res?.ok(), `${path} answered ${res?.status()}`);
  if (ready) await page.waitForSelector(ready, { timeout: 15000 });
  return page;
}

/**
 * Every visible link and button with its box (the hard sticker shadow included), and how many
 * lines its text takes (counted from the text, so a block-level link that wraps counts too).
 * Map controls are left out.
 */
function controls(page) {
  return page.$$eval("a, button", (els) =>
    els
      .filter((el) => !el.closest(".leaflet-container"))
      .map((el) => {
        const r = el.getBoundingClientRect();
        const style = getComputedStyle(el);
        // One box per line: a wrapped inline link only covers its own lines, not the whole paragraph.
        // The shadow is drawn outside the box: "3px 4px 0" and the like.
        const shadow = style.boxShadow.match(/(-?\d+(?:\.\d+)?)px (-?\d+(?:\.\d+)?)px/);
        const dx = shadow ? Math.max(0, Number(shadow[1])) : 0;
        const dy = shadow ? Math.max(0, Number(shadow[2])) : 0;
        const range = document.createRange();
        range.selectNodeContents(el);
        const lines = new Set([...range.getClientRects()].filter((x) => x.width > 0).map((x) => Math.round(x.top))).size;
        return {
          text: el.textContent.trim().replace(/\s+/g, " ").slice(0, 60),
          visible: r.width > 0 && r.height > 0 && style.visibility !== "hidden",
          button: el.classList.contains("go-tool"),
          // A link that sits with a call-to-action button, or on its own as one ("Browse all towns").
          action: Boolean(el.closest(".actions, .towns-link")) || el.classList.contains("go-tool"),
          lines,
          cmp: el.classList.contains("cmp"),
          boxes: [...el.getClientRects()]
            .filter((x) => x.width > 0 && x.height > 0)
            .map((x) => ({ left: x.left + scrollX, top: x.top + scrollY, right: x.right + scrollX + dx, bottom: x.bottom + scrollY + dy })),
          box: { left: r.left + scrollX, top: r.top + scrollY, right: r.right + scrollX + dx, bottom: r.bottom + scrollY + dy },
        };
      })
      .filter((c) => c.visible),
  );
}

const overlaps = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
const anyOverlap = (a, b) => a.boxes.some((x) => b.boxes.some((y) => overlaps(x, y)));

// /where-to-live draws its board after fetching the bundle: wait for the rows and their + Compare.
for (const [name, path, ready] of [
  ["home", "/"],
  ["where-to-live", "/where-to-live", "#board-body .row .cmp"],
  ["towns list", "/where-to-live/towns"],
  ["town page", "/where-to-live/punggol"],
]) {
  test(`${name} at 360 px: no link or button overlaps another (shadows included), action links stay on one line`, async () => {
    const page = await phone(path, ready);
    try {
      const all = await controls(page);
      if (ready) assert.ok(all.some((c) => c.cmp), "the board rows and their + Compare are checked");
      const actions = all.filter((c) => c.action);
      assert.ok(actions.length > 0, `${path} has a call to action to check`);
      // A button's label may wrap inside the button; a link beside it must not break mid-phrase.
      for (const c of actions.filter((a) => !a.button)) assert.equal(c.lines, 1, `"${c.text}" breaks over ${c.lines} lines`);
      for (let i = 0; i < all.length; i++) {
        for (let j = i + 1; j < all.length; j++) {
          assert.ok(!anyOverlap(all[i], all[j]), `"${all[i].text}" and "${all[j].text}" overlap`);
        }
      }
    } finally {
      await page.close();
    }
  });
}

test("home at 360 px: Compare towns, then Browse all towns under it with a gap", async () => {
  const page = await phone("/");
  try {
    const [button, link] = (await controls(page)).filter((c) => c.action && c.text.match(/^(Compare towns|Browse all towns)$/));
    assert.equal(button?.text, "Compare towns");
    assert.equal(link?.text, "Browse all towns");
    assert.ok(link.box.top >= button.box.bottom + 8, "the link sits below the button and its shadow with room to spare");
  } finally {
    await page.close();
  }
});

/** "Four tabs for your day" without JS at a width: the cards, their rows and captions. */
async function fourCards(width, options = {}) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, javaScriptEnabled: false, ...options });
  const page = await context.newPage();
  try {
    await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
    await page.goto(base + "/", { waitUntil: "load" });
    await page.locator(".screens").scrollIntoViewIfNeeded();
    await page.hover(".screens li img");
    await page.waitForTimeout(400);
    return await page.$eval(".screens", (list) => {
      const shown = (el) => Boolean(el) && getComputedStyle(el).display !== "none" && el.getBoundingClientRect().width > 0;
      // The cards, not the screenshots: the one under the pointer is lifted.
      const tops = [...list.querySelectorAll("li")].map((li) => Math.round(li.getBoundingClientRect().top));
      return {
        firstRow: tops.filter((t) => t === tops[0]).length,
        rows: new Set(tops).size,
        captions: [...list.querySelectorAll("figcaption")].filter(shown).length,
        phone: shown(document.querySelector(".device")),
        sideways: list.scrollWidth > list.clientWidth + 1,
        lifted: getComputedStyle(list.querySelector("li img")).transform !== "none",
      };
    });
  } finally {
    await context.close();
  }
}

// Without JS the layout follows the width alone: a phone asking for the desktop site (980 px,
// touch) and a tablet get the same cards as a laptop of that width.
const touch = { hasTouch: true, isMobile: true };
for (const [name, width, options] of [
  ["a laptop at 1280 px", 1280, {}],
  ["Chrome Android's desktop site, 980 px (touch)", 980, touch],
  ["the hero's two-column width, 880 px", 880, touch],
]) {
  test(`home without JS, four tabs on ${name}: 4 cards in one row with their captions`, async () => {
    const tabs = await fourCards(width, options);
    assert.deepEqual(
      { firstRow: tabs.firstRow, rows: tabs.rows, captions: tabs.captions, phone: tabs.phone, sideways: tabs.sideways },
      { firstRow: 4, rows: 1, captions: 4, phone: false, sideways: false },
    );
  });
}

test("home without JS, four tabs at 768 px: 2 x 2 cards with their captions", async () => {
  const tabs = await fourCards(768, touch);
  assert.deepEqual(
    { firstRow: tabs.firstRow, rows: tabs.rows, captions: tabs.captions, phone: tabs.phone, sideways: tabs.sideways },
    { firstRow: 2, rows: 2, captions: 4, phone: false, sideways: false },
  );
});

test("home without JS, four tabs: a screenshot lifts under a mouse, not on a touch screen", async () => {
  assert.equal((await fourCards(980, {})).lifted, true, "mouse at 980 px");
  assert.equal((await fourCards(980, touch)).lifted, false, "touch at 980 px");
  assert.equal((await fourCards(1280, { reducedMotion: "reduce" })).lifted, false, "reduced motion");
});

/** The home page with JS at a width, scrolled to a selector; reduced motion so nothing plays by itself. */
async function home(width, selector, options = {}) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, reducedMotion: "reduce", ...options });
  const page = await context.newPage();
  await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
  await page.goto(base + "/", { waitUntil: "load" });
  await page.waitForSelector(selector);
  await page.locator(selector).first().scrollIntoViewIfNeeded();
  return { context, page };
}

/** Which screenshot fills the phone, the tab that is selected and the words beside it. */
function phoneState(page) {
  return page.$eval(".pager", (pager) => {
    const box = pager.getBoundingClientRect();
    const inside = [...pager.querySelectorAll("li")].filter((li) => {
      const r = li.getBoundingClientRect();
      return r.left >= box.left - 3 && r.right <= box.right + 3;
    });
    return {
      inside: inside.map((li) => li.querySelector("h3").textContent),
      selected: [...document.querySelectorAll(".tabbar [role=tab][aria-selected=true]")].map((b) => b.textContent),
      title: document.querySelector(".tab-title").textContent,
      text: document.querySelector(".tab-text").textContent.length > 20,
      captions: [...pager.querySelectorAll("figcaption")].filter((c) => getComputedStyle(c).display !== "none").length,
      sideways: document.documentElement.scrollWidth > innerWidth + 1,
    };
  });
}

for (const width of [360, 768, 1280]) {
  test(`home, four tabs at ${width} px: one phone with one screenshot, and a tab moves it`, async () => {
    const { context, page } = await home(width, ".device");
    try {
      assert.deepEqual(await phoneState(page), { inside: ["Today"], selected: ["Today"], title: "Today", text: true, captions: 0, sideways: false });
      await page.locator(".tabbar [role=tab]", { hasText: "Home" }).click();
      assert.deepEqual(await phoneState(page), { inside: ["Home"], selected: ["Home"], title: "Home", text: true, captions: 0, sideways: false });
      // Arrow keys on the tab bar, like any tab list.
      await page.locator(".tabbar [role=tab][aria-selected=true]").press("ArrowRight");
      assert.equal((await phoneState(page)).title, "History");
    } finally {
      await context.close();
    }
  });
}

test("home, four tabs: a swipe on the phone goes to the next tab, a small nudge springs back", async () => {
  const { context, page } = await home(1280, ".device", { reducedMotion: "no-preference" });
  try {
    const box = await page.locator(".pager").boundingBox();
    const y = box.y + box.height / 2;
    // A slow hand: 8 steps with a pause between them, so the speed at the release is the
    // gesture's own (a 12 px nudge is about 50 px/s), not how fast Playwright sends the events.
    const drag = async (dx) => {
      const x0 = box.x + box.width * 0.75;
      await page.mouse.move(x0, y);
      await page.mouse.down();
      for (let step = 1; step <= 8; step++) {
        await page.waitForTimeout(30);
        await page.mouse.move(x0 + (dx * step) / 8, y + 2);
      }
      await page.mouse.up();
      await page.waitForTimeout(900); // the spring settles
    };
    await drag(-box.width * 0.6);
    assert.deepEqual((await phoneState(page)).inside, ["Nearby"]);
    await drag(-12); // a hesitant nudge is not a swipe
    assert.deepEqual((await phoneState(page)).inside, ["Nearby"]);
    await drag(box.width * 0.6);
    assert.deepEqual((await phoneState(page)).inside, ["Today"]);
  } finally {
    await context.close();
  }
});

test("home, four tabs: a button let go outside the phone ends the drag", async () => {
  const { context, page } = await home(1280, ".device");
  try {
    const box = await page.locator(".pager").boundingBox();
    const y = box.y + box.height / 2;
    // Press near the edge and leave before the 8 px that would start a swipe; release outside.
    await page.mouse.move(box.x + 4, y);
    await page.mouse.down();
    await page.mouse.move(box.x - 40, y);
    await page.mouse.up();
    // Hovering over the phone afterwards must not drag the strip along.
    await page.mouse.move(box.x + box.width * 0.8, y);
    await page.mouse.move(box.x + box.width * 0.2, y, { steps: 5 });
    await page.waitForTimeout(100);
    assert.deepEqual((await phoneState(page)).inside, ["Today"]);
    assert.equal(await page.locator(".pager.dragging").count(), 0);
  } finally {
    await context.close();
  }
});

test("home, a day: the clock moves by keys and by its time labels, and the lock screen follows", async () => {
  const { context, page } = await home(360, ".day-stage");
  try {
    const state = () => page.evaluate(() => ({
      now: document.querySelector(".thumb").getAttribute("aria-valuenow"),
      title: document.querySelector(".day-title").textContent,
      notif: document.querySelector(".notif .n-title").textContent,
      clock: document.querySelector(".lock .clock b").textContent,
      listHidden: document.querySelector("[data-day]").hidden,
    }));
    assert.deepEqual(await state(), { now: "0", title: "Rain before you leave.", notif: "Rain before you leave.", clock: "7:00", listHidden: true });
    await page.locator(".thumb").press("ArrowRight");
    assert.equal((await state()).clock, "7:05");
    await page.locator(".stops button", { hasText: "7:55" }).click();
    assert.deepEqual(await state(), { now: "3", title: "MRT disrupted? Plan B.", notif: "MRT disrupted? Plan B.", clock: "7:55", listHidden: true });
    await page.locator(".thumb").press("End");
    assert.equal((await state()).title, "Your week.");
  } finally {
    await context.close();
  }
});

test("home, a day with motion on: a click on the line lands on the clicked time", async () => {
  const { context, page } = await home(1280, ".day-stage", { reducedMotion: "no-preference" });
  try {
    await page.locator(".day-play").click(); // pause, so only the click moves the clock
    assert.equal(await page.textContent(".day-play"), "Play the day");
    assert.equal(await page.locator(".day-play").getAttribute("aria-pressed"), null);
    const box = await page.locator(".scrub").boundingBox();
    const times = await page.$$eval(".stops button", (els) => els.map((el) => el.textContent));
    const gap = box.width / (times.length - 1);
    const now = () => page.$eval(".thumb", (el) => Number(el.getAttribute("aria-valuenow")));
    // From 7:00, three times away, then five, then back: a plain click, no move in between.
    for (const i of [3, 5, 1]) {
      await page.mouse.click(box.x + i * gap, box.y + box.height / 2);
      await page.waitForTimeout(900); // the spring settles
      assert.equal(await now(), i, `a click on ${times[i]}`);
      assert.equal(await page.locator(".stops button.on").textContent(), times[i]);
    }
    // A real hand moves a pixel or two between press and release: still the clicked time.
    await page.mouse.move(box.x + 6 * gap, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(16);
    await page.mouse.move(box.x + 6 * gap + 2, box.y + box.height / 2);
    await page.mouse.up();
    await page.waitForTimeout(900);
    assert.equal(await now(), 6, "a click that moved 2 px");
    // Drag the clock to a time, hold it there, let go: it stays, it is not carried on.
    const thumb = await page.locator(".thumb").boundingBox();
    await page.mouse.move(thumb.x + thumb.width / 2, thumb.y + thumb.height / 2);
    await page.mouse.down();
    for (let step = 1; step <= 6; step++) {
      await page.waitForTimeout(16);
      await page.mouse.move(thumb.x + thumb.width / 2 - (step * 4 * gap) / 6, thumb.y + thumb.height / 2);
    }
    await page.waitForTimeout(300);
    await page.mouse.up();
    await page.waitForTimeout(900);
    assert.equal(await now(), 2, "dragged four times back, held, let go");
    // Keys step at the same pace whatever ran before: two quick presses are two times.
    await page.locator(".thumb").press("ArrowRight");
    await page.waitForTimeout(250);
    await page.locator(".thumb").press("ArrowRight");
    await page.waitForTimeout(900);
    assert.equal(await now(), 4);
  } finally {
    await context.close();
  }
});

/** What a reader sees move: the bus board, the tab in the phone and the day's time. */
function moving(page) {
  return page.evaluate(() => ({
    board: [...document.querySelectorAll(".board .row")].map((r) => r.textContent.replace(/\s+/g, " ").trim()),
    answer: document.querySelector("[data-answer-card]").textContent,
    asked: [...document.querySelectorAll(".q[aria-pressed=true]")].map((q) => q.textContent),
    running: document.querySelectorAll(".q.run").length,
    tab: document.querySelector(".tab-title").textContent,
    strip: document.querySelector(".pager .track").style.transform,
    time: document.querySelector(".lock .clock b").textContent,
    thumb: document.querySelector(".thumb").style.transform,
    play: document.querySelector(".day-play").textContent,
  }));
}

test("home with reduced motion: nothing moves by itself (bus board, tabs, the day), and nothing is a live region yet", async () => {
  // A tall window, so the hero, the phone and the day are all on screen and would play if they could.
  // The page's clock is ours, so a minute of timers runs at once: long enough for a bus to leave.
  const context = await browser.newContext({ viewport: { width: 1280, height: 6000 }, reducedMotion: "reduce" });
  const page = await context.newPage();
  try {
    await page.clock.install();
    await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
    await page.goto(base + "/", { waitUntil: "load" });
    await page.waitForSelector(".day-stage");
    await page.waitForSelector(".device");
    await page.waitForSelector("[data-answer-card]:not([hidden])");
    await page.clock.runFor(500); // the observers have reported what is on screen
    const first = await moving(page);
    assert.equal(first.answer, "36 arrivingSeats available. Your stop is 2 minutes' walk.");
    assert.deepEqual(first.asked, ["Bus coming?"]);
    assert.match(first.board[0], /Arr/);
    assert.equal(first.running, 0);
    assert.equal(first.tab, "Today");
    assert.equal(first.time, "7:00");
    assert.equal(first.play, "Play the day");
    await page.clock.runFor(60000);
    assert.deepEqual(await moving(page), first);
    assert.equal(await page.locator("[aria-live]").count(), 0);
    // After a tap the answer is announced; after a key on the clock the notification is.
    await page.locator(".q", { hasText: "Makan where?" }).click();
    assert.equal(await page.getAttribute("[data-answer-card]", "aria-live"), "polite");
    await page.locator(".thumb").press("ArrowRight");
    assert.equal(await page.getAttribute(".notif", "aria-live"), "polite");
  } finally {
    await context.close();
  }
});

test("home with motion on: the questions take turns only while the hero is on screen, and the bus stays at Arr while it is asked", async () => {
  const { context, page } = await home(360, "[data-answer-card]:not([hidden])", { reducedMotion: "no-preference" });
  try {
    await page.waitForSelector(".q.run");
    assert.equal(await page.locator("[aria-live]").count(), 0, "nothing is announced while it plays by itself");
    await page.locator(".faq, footer").first().scrollIntoViewIfNeeded();
    await page.waitForFunction(() => document.querySelectorAll(".q.run").length === 0);
    const asked = await page.locator(".q[aria-pressed=true]").textContent();
    await page.waitForTimeout(4000); // longer than one turn
    assert.equal(await page.locator(".q[aria-pressed=true]").textContent(), asked, "no turn was taken off screen");
    await page.locator("[data-hero]").scrollIntoViewIfNeeded();
    await page.waitForSelector(".q.run");
    // A tap ends the turns; the bus asked for stays at Arr while the others count down.
    await page.locator(".q", { hasText: "Bus coming?" }).click();
    assert.equal(await page.locator(".q.run").count(), 0);
    assert.equal(await page.getAttribute("[data-answer-card]", "aria-live"), "polite");
    const rows = () => page.$$eval(".board .row .eta", (els) => els.map((el) => el.textContent));
    const before = await rows();
    assert.equal(before[0], "Arr");
    await page.waitForFunction((was) => document.querySelectorAll(".board .row .eta")[1].textContent !== was, before[1], { timeout: 30000 });
    assert.equal((await rows())[0], "Arr");
  } finally {
    await context.close();
  }
});

test("home with motion on: focus on the tab bar or the clock stops the playing", async () => {
  const { context, page } = await home(1280, ".device", { reducedMotion: "no-preference", viewport: { width: 1280, height: 6000 } });
  try {
    await page.waitForSelector(".day-stage");
    assert.equal(await page.textContent(".day-play"), "Pause the day");
    await page.locator(".tabbar [role=tab][aria-selected=true]").focus();
    await page.locator(".thumb").focus();
    assert.equal(await page.textContent(".day-play"), "Play the day");
    const first = await moving(page);
    await page.waitForTimeout(5200); // longer than a turn of the tabs (4.5 s) and of the day (3.6 s)
    const later = await moving(page);
    assert.equal(later.tab, "Today");
    assert.equal(later.time, first.time);
  } finally {
    await context.close();
  }
});

test("home: \"How we handle your data\" lands with its heading below the sticky bar", async () => {
  const { context, page } = await home(1280, "a[href='#privacy']");
  try {
    await page.locator("a[href='#privacy']").click();
    await page.waitForTimeout(300);
    const { bar, heading } = await page.evaluate(() => ({
      bar: document.querySelector(".nav").getBoundingClientRect().bottom,
      heading: document.querySelector("#privacy").getBoundingClientRect().top,
    }));
    assert.ok(heading >= bar, `the heading (top ${heading}) is under the bar (bottom ${bar})`);
  } finally {
    await context.close();
  }
});

test("home without JS: the answer card, the town teaser and the privacy drawing are not shown", async () => {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, javaScriptEnabled: false });
  const page = await context.newPage();
  try {
    await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
    await page.goto(base + "/", { waitUntil: "load" });
    const shown = await page.$$eval(".vault, .answer, .town-demo", (els) =>
      els.map((el) => [el.className, getComputedStyle(el).display, el.getBoundingClientRect().height]));
    assert.deepEqual(shown.map((s) => s[0]).sort(), ["answer", "town-demo", "vault"]);
    for (const [name, display, height] of shown) {
      assert.equal(display, "none", name);
      assert.equal(height, 0, name);
    }
  } finally {
    await context.close();
  }
});

test("home: the privacy drawing is shown once it was drawn, and stays hidden in a browser that cannot draw it", async () => {
  const { context, page } = await home(1280, ".vault");
  try {
    assert.equal(await page.$eval(".vault", (c) => getComputedStyle(c).display), "block");
    assert.ok(await page.$eval(".vault", (c) => c.width > 0 && c.getContext("2d").getImageData(0, 0, c.width, c.height).data.some((v) => v > 0)), "something was drawn");
  } finally {
    await context.close();
  }
  const old = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: "reduce" });
  try {
    await old.addInitScript(() => delete CanvasRenderingContext2D.prototype.roundRect);
    const page = await old.newPage();
    await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
    await page.goto(base + "/", { waitUntil: "load" });
    await page.waitForSelector(".day-stage"); // the modules ran
    assert.equal(await page.$eval(".vault", (c) => getComputedStyle(c).display), "none");
  } finally {
    await old.close();
  }
});

test("home, hero: tapping a question answers it in the stop card; the bus board has three rows", async () => {
  const { context, page } = await home(360, "[data-answer-card]:not([hidden])");
  try {
    // Reduced motion starts on the bus, as the page shows without JS.
    assert.equal(await page.textContent("[data-answer-card] b"), "36 arriving");
    await page.locator(".q", { hasText: "MRT disrupted?" }).click();
    assert.equal(await page.textContent("[data-answer-card] b"), "EWL disrupted");
    assert.equal(await page.locator(".q[aria-pressed=true]").textContent(), "MRT disrupted?");
    assert.equal(await page.locator(".board .row").count(), 3);
    assert.match(await page.locator(".board .row .eta").first().textContent(), /^(Arr|\d+min)$/);
  } finally {
    await context.close();
  }
});

test("home, where to live: the teaser ranks towns from the published data and re-ranks for another office", async () => {
  const { context, page } = await home(1280, ".town-rows li");
  try {
    const order = () => page.$$eval(".town-rows li b", (els) => els.map((el) => el.textContent));
    const first = await order();
    assert.equal(first.length, 6);
    await page.locator(".seg button", { hasText: "Jurong East" }).click();
    const second = await order();
    assert.equal(second[0], "Jurong West");
    assert.notDeepEqual(second, first);
  } finally {
    await context.close();
  }
});
