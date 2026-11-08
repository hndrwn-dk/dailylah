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

async function phone(path) {
  const page = await browser.newPage({ viewport: { width: 360, height: 800 } });
  await page.route((url) => !url.href.startsWith(base), (route) => route.abort());
  await page.goto(base + path, { waitUntil: "load" });
  return page;
}

/**
 * The boxes of a call-to-action button (with its hard shadow) and every link next to it in the
 * same block, plus how many lines each link takes.
 */
function actionBoxes(page, buttonSelector) {
  return page.$$eval(buttonSelector, (buttons) =>
    buttons.map((button) => {
      const r = button.getBoundingClientRect();
      // The sticker shadow is drawn outside the box: "3px 4px 0" and the like.
      const shadow = getComputedStyle(button).boxShadow.match(/(-?\d+(?:\.\d+)?)px (-?\d+(?:\.\d+)?)px/);
      const dx = shadow ? Math.max(0, Number(shadow[1])) : 0;
      const dy = shadow ? Math.max(0, Number(shadow[2])) : 0;
      const links = [...button.parentElement.querySelectorAll("a")].filter((a) => a !== button);
      return {
        button: { left: r.left, top: r.top, right: r.right + dx, bottom: r.bottom + dy },
        links: links.map((a) => {
          const box = a.getBoundingClientRect();
          return {
            text: a.textContent.trim(),
            lines: a.getClientRects().length,
            box: { left: box.left, top: box.top, right: box.right, bottom: box.bottom },
          };
        }),
      };
    }),
  );
}

const overlaps = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

for (const [name, path] of [
  ["home", "/"],
  ["where-to-live", "/where-to-live"],
  ["towns list", "/where-to-live/towns"],
  ["town page", "/where-to-live/punggol"],
]) {
  test(`${name} at 360 px: a button and the links beside it never overlap, links stay on one line`, async () => {
    const page = await phone(path);
    try {
      const groups = await actionBoxes(page, ".go-tool");
      for (const { button, links } of groups) {
        for (const link of links) {
          assert.equal(link.lines, 1, `"${link.text}" breaks over ${link.lines} lines`);
          assert.ok(!overlaps(button, link.box), `"${link.text}" overlaps the button or its shadow`);
        }
      }
    } finally {
      await page.close();
    }
  });
}

test("home at 360 px: Compare towns, then Browse all towns under it", async () => {
  const page = await phone("/");
  try {
    const [group] = await actionBoxes(page, ".tool .go-tool");
    assert.ok(group, "the Where to live? button is on the home page");
    assert.deepEqual(group.links.map((l) => l.text), ["Browse all towns"]);
    // Stacked: the link starts below the button and its shadow, with a gap.
    assert.ok(group.links[0].box.top >= group.button.bottom + 8, "the link sits below the button with room to spare");
  } finally {
    await page.close();
  }
});
