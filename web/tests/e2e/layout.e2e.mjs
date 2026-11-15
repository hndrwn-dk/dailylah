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
      await page.locator(".tabbar [role=tab]", { hasText: "Home" }).dispatchEvent("pointerdown", { button: 0 });
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
    const drag = async (dx) => {
      await page.mouse.move(box.x + box.width * 0.75, y);
      await page.mouse.down();
      await page.mouse.move(box.x + box.width * 0.75 + dx, y + 2, { steps: 8 });
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

test("home, hero: tapping a question answers it in the stop card; the bus board has three rows", async () => {
  const { context, page } = await home(360, "[data-answer-card]:not([hidden])");
  try {
    // Reduced motion starts on the bus, as the page shows without JS.
    assert.equal(await page.textContent("[data-answer-card] b"), "36 arriving");
    await page.locator(".q", { hasText: "MRT disrupted?" }).dispatchEvent("pointerdown", { button: 0 });
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
    await page.locator(".seg button", { hasText: "Jurong East" }).dispatchEvent("pointerdown", { button: 0 });
    const second = await order();
    assert.equal(second[0], "Jurong West");
    assert.notDeepEqual(second, first);
  } finally {
    await context.close();
  }
});
