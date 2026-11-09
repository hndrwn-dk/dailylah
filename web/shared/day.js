// "A day with DailyLah" on the landing page: the timeline is an MRT line. As you scroll, the line
// fills, a train rides down it, and each station's card comes in with its small picture.
// Progressive enhancement: without this script (or with reduced motion) the cards are all shown
// as they are in the HTML; the CSS hides them only under the .moving class added here.

const list = document.querySelector("[data-day]");
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;

if (list) {
  const items = [...list.querySelectorAll("li")];
  if (calm || !("IntersectionObserver" in window)) {
    items.forEach((li) => li.classList.add("on"));
    list.style.setProperty("--p", "1");
  } else {
    list.classList.add("moving");
    const seen = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            e.target.classList.add("on");
            seen.unobserve(e.target);
          }
        }
      },
      { rootMargin: "0px 0px -20% 0px" },
    );
    items.forEach((li) => seen.observe(li));

    // How far the middle of the screen is down the line, 0 to 1.
    let queued = false;
    const draw = () => {
      queued = false;
      const r = list.getBoundingClientRect();
      const p = (innerHeight * 0.6 - r.top) / r.height;
      list.style.setProperty("--p", Math.min(1, Math.max(0, p)).toFixed(3));
    };
    const ask = () => {
      if (!queued) {
        queued = true;
        requestAnimationFrame(draw);
      }
    };
    addEventListener("scroll", ask, { passive: true });
    addEventListener("resize", ask);
    draw();
  }
}
