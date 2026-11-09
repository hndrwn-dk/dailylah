"""Guards for calls to a paid-by-credits upstream (Geoapify, /v1/places).

The Geoapify account's daily credits are shared with another app, so DailyLah keeps its own
daily budget (counted in Redis, so it survives Render's sleep and restarts), a per-second cap
below Geoapify's 5 requests a second, and a pause after Geoapify refuses (429 quota or rate
limit, 401/403 key problem). Every guard answers 503, and the app then searches OneMap.
"""

import time
from collections import deque
from collections.abc import Callable
from datetime import UTC, datetime


def budget_key(day: str | None = None) -> str:
    """Redis key of the day's Geoapify call count; days are UTC, like Geoapify's."""
    return f"geoapify:budget:{day or datetime.now(UTC).date().isoformat()}"


class RateGate:
    """At most [per_second] calls in any one-second window; never waits."""

    def __init__(self, per_second: int, clock: Callable[[], float] = time.monotonic) -> None:
        self.per_second = per_second
        self.clock = clock
        self._calls: deque[float] = deque()

    def take(self) -> bool:
        now = self.clock()
        while self._calls and now - self._calls[0] >= 1.0:
            self._calls.popleft()
        if len(self._calls) >= self.per_second:
            return False
        self._calls.append(now)
        return True


class Breaker:
    """Stops calls for a while after the upstream refuses."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self.clock = clock
        self.until = 0.0

    def pause(self, seconds: float) -> None:
        self.until = max(self.until, self.clock() + seconds)

    def paused(self) -> bool:
        return self.clock() < self.until
