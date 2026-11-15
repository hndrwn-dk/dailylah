// "Your places stay on your phone": a small drawing. Home, work and school circle inside a phone;
// a dot sets off toward a crossed-out cloud and turns back. Decoration only (the list beside it
// says the same in words), so it is hidden from assistive technology. Drawn only while on screen;
// with reduced motion it is one still frame. Colours are the page's own tokens, read at draw time
// so light and dark both work.

import { calm } from "./spring.js";

const canvas = document.querySelector("[data-vault]");

if (canvas && canvas.getContext) {
  const ctx = canvas.getContext("2d");
  canvas.hidden = false; // hidden in the HTML: without this script there is nothing to draw
  const still = calm();
  const born = performance.now();
  const token = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const lerp = (a, b, t) => a + (b - a) * t;

  function draw() {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;
    if (canvas.width !== Math.round(w * dpr)) {
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const ink = token("--edge");
    const text = token("--ink");
    const teal = token("--teal");
    const amber = token("--amber");
    const card = token("--card");
    const stopRed = token("--stop");
    const mist = token("--mist");
    const t = still ? 0.6 : (performance.now() - born) / 1000;

    // the phone
    const pw = Math.min(w * 0.34, 150);
    const ph = Math.min(pw * 1.9, h - 24);
    const px = w * 0.32 - pw / 2;
    const py = (h - ph) / 2;
    ctx.lineWidth = 2.5;
    ctx.strokeStyle = ink;
    ctx.fillStyle = card;
    ctx.beginPath();
    ctx.roundRect(px, py, pw, ph, 20);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = ink;
    ctx.beginPath();
    ctx.roundRect(px + pw / 2 - 20, py + 9, 40, 9, 5);
    ctx.fill();

    // home, work and school going round inside it
    const cx = px + pw / 2;
    const cy = py + ph / 2;
    const rx = pw * 0.27;
    const ry = ph * 0.24;
    ctx.setLineDash([4, 5]);
    ctx.lineWidth = 1.5;
    ctx.strokeStyle = mist;
    ctx.beginPath();
    ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.font = '700 11px "Plus Jakarta Sans", system-ui, sans-serif';
    ctx.textAlign = "center";
    [["Home", amber], ["Work", teal], ["School", amber]].forEach(([label, colour], i) => {
      const a = t * 0.5 + (i * Math.PI * 2) / 3;
      const x = cx + Math.cos(a) * rx;
      const y = cy + Math.sin(a) * ry;
      ctx.fillStyle = colour;
      ctx.strokeStyle = ink;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x, y, 9, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = text;
      ctx.fillText(label, x, y + 24);
    });

    // the cloud, crossed out
    const kx = w * 0.78;
    const ky = h * 0.32;
    const s = Math.min(w, h) * 0.09;
    const puffs = [[kx - s, ky + s * 0.3, s * 0.7], [kx, ky - s * 0.1, s], [kx + s, ky + s * 0.3, s * 0.7]];
    ctx.strokeStyle = mist;
    ctx.lineWidth = 2;
    for (const [x, y, r] of puffs) {
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.fillStyle = card;
    for (const [x, y, r] of puffs) {
      ctx.beginPath();
      ctx.arc(x, y, r - 1, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.strokeStyle = stopRed;
    ctx.lineWidth = 4;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(kx - s * 1.4, ky + s);
    ctx.lineTo(kx + s * 1.4, ky - s * 0.9);
    ctx.stroke();
    ctx.lineCap = "butt";
    ctx.fillStyle = mist;
    ctx.font = '600 12px "Plus Jakarta Sans", system-ui, sans-serif';
    ctx.fillText("not sent", kx, ky + s * 2.2);

    // a dot that sets off for the cloud and turns back
    const x0 = px + pw + 6;
    const y0 = py + ph * 0.3;
    const x1 = kx - s * 1.5;
    const y1 = ky + s * 0.3;
    ctx.setLineDash([3, 6]);
    ctx.strokeStyle = mist;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();
    ctx.setLineDash([]);
    const phase = (t * 0.6) % 1;
    const out = Math.sin((phase < 0.5 ? phase * 2 : (1 - phase) * 2) * (Math.PI / 2)) * 0.45;
    ctx.fillStyle = teal;
    ctx.beginPath();
    ctx.arc(lerp(x0, x1, out), lerp(y0, y1, out), 4, 0, Math.PI * 2);
    ctx.fill();
  }

  let onScreen = false;
  const loop = () => {
    draw();
    if (onScreen && !still) requestAnimationFrame(loop);
  };
  new IntersectionObserver(([e]) => {
    const was = onScreen;
    onScreen = e.isIntersecting;
    if (onScreen && !was) loop();
  }, { threshold: 0.1 }).observe(canvas);
  new ResizeObserver(draw).observe(canvas);
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", draw);
  draw();
}
