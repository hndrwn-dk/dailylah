// Motion helpers for the landing page: a spring that can be grabbed and re-aimed at any moment,
// the velocity of a drag, where a flick would come to rest, and soft resistance past an edge.
// No DOM here except requestAnimationFrame, so web/tests can run the maths in Node.

/** True when the reader asked for less motion: springs then jump to their target. */
export const calm = () => typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;

export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/**
 * A spring on one number. `response` is roughly how long it takes to arrive (seconds), `damping`
 * 1 arrives without overshoot and less than 1 bounces a little. It always starts from where the
 * value is now, with the speed it has now, so a new target or a grab never jumps.
 */
export class Spring {
  constructor(value = 0, { response = 0.4, damping = 1 } = {}) {
    this.x = value;
    this.target = value;
    this.v = 0;
    this.frame = 0;
    this.onUpdate = () => {};
    this.tune(response, damping);
  }

  tune(response, damping) {
    this.k = (2 * Math.PI / response) ** 2;
    this.c = (4 * Math.PI * damping) / response;
  }

  /** Move `seconds` forward in small steps; true once it rests on the target. */
  step(seconds) {
    const n = Math.max(1, Math.ceil(seconds / 0.004));
    const h = seconds / n;
    for (let i = 0; i < n; i++) {
      this.v += (-this.k * (this.x - this.target) - this.c * this.v) * h;
      this.x += this.v * h;
    }
    if (Math.abs(this.v) < 0.02 && Math.abs(this.x - this.target) < 0.02) {
      this.x = this.target;
      this.v = 0;
      return true;
    }
    return false;
  }

  /** Aim at `target`, optionally with the speed of the drag that just ended (units per second). */
  to(target, { velocity, response, damping } = {}) {
    if (response) this.tune(response, damping ?? 1);
    if (velocity !== undefined) this.v = velocity;
    this.target = target;
    if (calm() || typeof requestAnimationFrame !== "function") return this.jump(target);
    if (this.frame) return;
    let last = performance.now();
    const tick = (now) => {
      const done = this.step(Math.min(0.064, (now - last) / 1000));
      last = now;
      this.onUpdate(this.x);
      this.frame = done ? 0 : requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  /** Put the value somewhere at once (while a finger drags it). */
  jump(value) {
    this.stop();
    this.x = this.target = value;
    this.onUpdate(value);
  }

  /** Freeze where it is on screen, so a grab takes over from there. */
  stop() {
    if (this.frame && typeof cancelAnimationFrame === "function") cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.v = 0;
    this.target = this.x;
  }
}

/** Speed of a drag from its last 100 ms of samples, in units per second. */
export class Velocity {
  constructor() {
    this.samples = [];
  }

  add(value, time) {
    this.samples.push([value, time]);
    while (this.samples.length > 2 && time - this.samples[0][1] > 100) this.samples.shift();
  }

  get() {
    if (this.samples.length < 2) return 0;
    const [x0, t0] = this.samples[0];
    const [x1, t1] = this.samples[this.samples.length - 1];
    return t1 > t0 ? ((x1 - x0) / (t1 - t0)) * 1000 : 0;
  }
}

/** How far a flick at `velocity` (per second) carries before it stops, like a scroll does. */
export function project(velocity, deceleration = 0.998) {
  return ((velocity / 1000) * deceleration) / (1 - deceleration);
}

/** Past an edge the content follows less and less: `overshoot` in, a smaller distance out. */
export function rubber(overshoot, dimension, constant = 0.55) {
  return (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));
}

/** The snap point nearest to where a release at `velocity` would come to rest. */
export function settle(value, velocity, points, deceleration = 0.998) {
  const rest = value + project(velocity, deceleration);
  return points.reduce((best, p) => (Math.abs(p - rest) < Math.abs(best - rest) ? p : best), points[0]);
}
