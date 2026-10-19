"""Two-level cache: in-process memory first, Upstash Redis second.

Upstash free tier = 500K commands/month (~16K/day), so:
- reads are served from memory whenever possible;
- writes to Redis happen only when a dataset's content actually changed.
"""

import hashlib
import json
import time
from typing import Any

import redis.asyncio as redis


class Cache:
    def __init__(self, redis_url: str | None = None) -> None:
        self._mem: dict[str, tuple[float, Any]] = {}
        self._hash: dict[str, str] = {}
        self._redis = redis.from_url(redis_url, decode_responses=True) if redis_url else None

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

    def set_memory_only(self, key: str, value: Any, ttl: int) -> None:
        self._mem[key] = (time.monotonic() + ttl, value)

    async def close(self) -> None:
        if self._redis is not None:
            await self._redis.aclose()
