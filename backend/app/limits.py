"""Guards for calls to a paid-by-credits upstream (Geoapify, /v1/places).

The Geoapify account's daily credits are shared with another app, so DailyLah keeps its own
daily budget (counted in Redis, so it survives Render's sleep and restarts), a per-second cap
below Geoapify's 5 requests a second, a per-client share of the budget, and a pause after
Geoapify refuses (429 quota or rate limit, 401/403 key problem). The per-client guard answers
429 and the others 503; either way the app then searches OneMap.
"""

import hashlib
import hmac
import ipaddress
import time
from collections import deque
from collections.abc import Callable, Iterable
from datetime import UTC, datetime


def budget_key(day: str | None = None) -> str:
    """Redis key of the day's Geoapify call count; days are UTC, like Geoapify's."""
    return f"geoapify:budget:{day or datetime.now(UTC).date().isoformat()}"


def client_address(cf_connecting_ip: str | None, forwarded_for: Iterable[str], peer: str) -> str:
    """The address to count a client by, from headers the client cannot set.

    Render serves every request through Cloudflare and then its own proxy, so the socket peer
    is the proxy. Cloudflare overwrites `CF-Connecting-IP` with the address that connected to
    it; `X-Forwarded-For` is only appended to, so everything left of the last public entry may
    come from the client and is never read. Without the Cloudflare header the last public
    `X-Forwarded-For` entry is used (the hop nearest to us), then the socket peer.
    IPv6 clients are counted by /64, the block one subscriber gets."""
    for candidate in (cf_connecting_ip, *_last_public(forwarded_for)):
        ip = _ip(candidate)
        if ip is not None:
            return _block(ip)
    return peer or "unknown"


def _ip(text: str | None) -> ipaddress.IPv4Address | ipaddress.IPv6Address | None:
    try:
        return ipaddress.ip_address((text or "").strip())
    except ValueError:
        return None


def _last_public(forwarded_for: Iterable[str]) -> list[str]:
    entries = [e for value in forwarded_for for e in value.split(",")]
    for entry in reversed(entries):
        ip = _ip(entry)
        if ip is None:
            return []  # not an address: nothing further left can be trusted
        if ip.is_global:
            return [entry]
    return []


def _block(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> str:
    if isinstance(ip, ipaddress.IPv6Address):
        if ip.ipv4_mapped is not None:
            return str(ip.ipv4_mapped)
        return str(ipaddress.ip_network((ip, 64), strict=False).network_address) + "/64"
    return str(ip)


def client_key(secret: str, address: str, window: int, now: float | None = None) -> str:
    """Redis key of one client's call count in the current window. The address is stored as a
    keyed hash that changes with the window, never as the address itself."""
    slot = int((time.time() if now is None else now) // window)
    digest = hmac.new(secret.encode(), f"{slot}:{address}".encode(), hashlib.sha256).hexdigest()
    return f"geoapify:client:{slot}:{digest[:20]}"


class Blocked:
    """Keys that are over their limit, kept in memory until their window ends so a client that
    keeps asking costs no further Redis commands."""

    def __init__(self, max_keys: int = 5000, clock: Callable[[], float] = time.monotonic) -> None:
        self.max_keys = max_keys
        self.clock = clock
        self._until: dict[str, float] = {}

    def add(self, key: str, seconds: float) -> None:
        now = self.clock()
        if len(self._until) >= self.max_keys:
            self._until = {k: t for k, t in self._until.items() if t > now}
        if len(self._until) >= self.max_keys:
            del self._until[min(self._until, key=self._until.__getitem__)]
        self._until[key] = now + seconds

    def has(self, key: str) -> bool:
        until = self._until.get(key)
        if until is None:
            return False
        if until <= self.clock():
            del self._until[key]
            return False
        return True


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
