"""Two-level cache: in-process memory first, Upstash Redis second.

Upstash free tier = 500K commands/month (~16K/day), so:
- reads are served from memory whenever possible;
- writes to Redis happen only when a dataset's content actually changed.
"""

import hashlib
import json
import logging
import time
from typing import Any

import redis.asyncio as redis

log = logging.getLogger("dailylah.cache")

# Render free has 512 MB; per-query entries (search, agent) must not grow without bound.
MAX_MEMORY_KEYS = 5000
# After a failed Redis counter call, skip Redis counters for this long.
REDIS_RETRY_S = 60


class Cache:
    def __init__(self, redis_url: str | None = None) -> None:
        self._mem: dict[str, tuple[float, Any]] = {}
        self._hash: dict[str, str] = {}
        self._redis = redis.from_url(redis_url, decode_responses=True) if redis_url else None
        self._counts: dict[str, tuple[float, int]] = {}
        self._redis_down_until = 0.0

    async def get(self, key: str) -> Any | None:
        hit = self._mem.get(key)
        if hit and hit[0] > time.monotonic():
            return hit[1]
        if self._redis is None:
            return None
        raw = await self._redis.get(key)
        if raw is None:
            return None
        value = json.loads(raw)
        ttl = await self._redis.ttl(key)
        self._mem[key] = (time.monotonic() + (ttl if ttl and ttl > 0 else 60), value)
        return value

    async def set(self, key: str, value: Any, ttl: int) -> bool:
        """Store value. Returns True if content changed (and Redis was written)."""
        payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
        digest = hashlib.sha256(payload.encode()).hexdigest()
        self._mem[key] = (time.monotonic() + ttl, value)
        if self._hash.get(key) == digest:
            return False
        self._hash[key] = digest
        if self._redis is not None:
            await self._redis.set(key, payload, ex=ttl)
        return True

    def get_memory(self, key: str) -> Any | None:
        """Memory only (never Redis): for per-query answers such as address search."""
        hit = self._mem.get(key)
        return hit[1] if hit and hit[0] > time.monotonic() else None

    def set_memory_only(self, key: str, value: Any, ttl: int) -> None:
        if len(self._mem) >= MAX_MEMORY_KEYS:
            now = time.monotonic()
            for k in [k for k, (exp, _) in self._mem.items() if exp <= now]:
                del self._mem[k]
            while len(self._mem) >= MAX_MEMORY_KEYS:
                # Oldest expiry first; datasets refresh well before theirs.
                del self._mem[min(self._mem, key=lambda k: self._mem[k][0])]
        self._mem[key] = (time.monotonic() + ttl, value)

    async def incr_shared(self, key: str, ttl: int) -> int | None:
        """Add one to a counter in Redis (one INCR, plus EXPIRE the first time) and return it,
        so the count survives restarts. None when there is no shared count: Redis is not
        configured, just failed, or failed within the last minute (so an outage does not add a
        failing Redis call to every request)."""
        if self._redis is None or time.monotonic() < self._redis_down_until:
            return None
        try:
            n = int(await self._redis.incr(key))
            if n == 1:
                await self._redis.expire(key, ttl)
            return n
        except Exception as e:  # any Redis failure
            log.warning("Redis counter failed: %s", type(e).__name__)
            self._redis_down_until = time.monotonic() + REDIS_RETRY_S
            return None

    def incr_memory(self, key: str, ttl: int) -> int:
        """Add one to a counter in this process and return it. Lost on a restart."""
        now = time.monotonic()
        if len(self._counts) >= MAX_MEMORY_KEYS:
            self._counts = {k: v for k, v in self._counts.items() if v[0] > now}
            if len(self._counts) >= MAX_MEMORY_KEYS:  # all live: drop the one ending first
                del self._counts[min(self._counts, key=lambda k: self._counts[k][0])]
        exp, n = self._counts.get(key, (0.0, 0))
        if exp <= now:
            exp, n = now + ttl, 0
        self._counts[key] = (exp, n + 1)
        return n + 1

    async def close(self) -> None:
        if self._redis is not None:
            await self._redis.aclose()
