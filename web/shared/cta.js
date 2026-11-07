// The "get the app" call to action, shared by the landing page and /where-to-live.
// Change it here only. While DailyLah is in closed testing it is the tester flow (Google Group,
// then opt in on Google Play). When production is live, switch to the public listing
// (docs/HANDOFF.md): url "https://play.google.com/store/apps/details?id=com.tursinalabs.dailylah",
// label "Get DailyLah", ariaLabel "Get DailyLah on Google Play", and steps [].
// `label` is short so the button fits one line on a 360 px phone; `ariaLabel` is the full name.
//
// Every element with data-cta is filled from this object with DOM nodes (textContent), never HTML.

export const CTA = {
  url: "https://play.google.com/apps/testing/com.tursinalabs.dailylah",
  label: "Join the beta",
  ariaLabel: "Join the beta on Google Play",
  // Each step is a list of parts: plain text, {strong} or {href, text}.
  steps: [
    [
      { href: "https://groups.google.com/g/tursinalabs-testers", text: "Join the testers group" },
      " with the Google account on your phone.",
    ],
    ["Tap ", { strong: "Join the beta" }, " above, accept, then install DailyLah from Google Play."],
  ],
};

const SVG_NS = "http://www.w3.org/2000/svg";

function playIcon(doc) {
  const svg = doc.createElementNS(SVG_NS, "svg");
  svg.setAttribute("width", "22");
  svg.setAttribute("height", "24");
  svg.setAttribute("viewBox", "0 0 22 24");
  svg.setAttribute("aria-hidden", "true");
  const path = doc.createElementNS(SVG_NS, "path");
  path.setAttribute("d", "M2 1.5v21L20.5 12z");
  path.setAttribute("fill", "#0F1618");
  svg.append(path);
  return svg;
}

function part(doc, p) {
  if (typeof p === "string") return doc.createTextNode(p);
  if (p.strong) {
    const b = doc.createElement("b");
    b.textContent = p.strong;
    return b;
  }
  const a = doc.createElement("a");
  a.href = p.href;
  a.rel = "noopener";
  a.textContent = p.text;
  return a;
}

/** Fill `el` with the button and, while in testing, the numbered steps. */
export function renderCta(el, cta = CTA, doc = document) {
  const link = doc.createElement("a");
  link.className = "play";
  link.href = cta.url;
  link.rel = "noopener";
  link.setAttribute("aria-label", cta.ariaLabel ?? cta.label);
  link.append(playIcon(doc), doc.createTextNode(cta.label));
  const nodes = [link];
  if (cta.steps.length) {
    const ol = doc.createElement("ol");
    ol.className = "steps";
    for (const step of cta.steps) {
      const li = doc.createElement("li");
      li.append(...step.map((p) => part(doc, p)));
      ol.append(li);
    }
    nodes.push(ol);
  }
  el.replaceChildren(...nodes);
}

if (typeof document !== "undefined") {
  for (const el of document.querySelectorAll("[data-cta]")) renderCta(el);
}
