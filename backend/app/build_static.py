"""Build static data bundles for the app (served by Vercel from web/data/).

Run daily by .github/workflows/data.yml:
    cd backend && python -m app.build_static ../web/data

Writes:
    bus_stops.json  — [{"c": code, "n": name, "r": road, "la": lat, "lo": lng}, ...]
    manifest.json   — {"version": "<sha prefix>", "files": {...}} so the app can skip
                      re-downloading unchanged bundles.
"""

import asyncio
import hashlib
import json
import sys
from pathlib import Path

import httpx

from .config import get_settings
from .sources import Sources, compact_bus_stops

MIN_EXPECTED_STOPS = 4000  # Singapore has ~5,000; fewer means a broken upstream response


def _dump(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()


async def build(out_dir: Path, client: httpx.AsyncClient | None = None) -> dict:
    settings = get_settings()
    own = client is None
    client = client or httpx.AsyncClient(timeout=30)
    try:
        stops = compact_bus_stops(await Sources(settings, client).bus_stops())
    finally:
        if own:
            await client.aclose()
    if len(stops) < MIN_EXPECTED_STOPS:
        raise RuntimeError(f"only {len(stops)} bus stops returned; refusing to publish")

    out_dir.mkdir(parents=True, exist_ok=True)
    payload = _dump(stops)
    digest = hashlib.sha256(payload).hexdigest()
    (out_dir / "bus_stops.json").write_bytes(payload)
    manifest = {
        "version": digest[:12],
        "files": {"bus_stops": {"path": "bus_stops.json", "count": len(stops), "sha256": digest}},
    }
    (out_dir / "manifest.json").write_bytes(_dump(manifest))
    return manifest


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "../web/data")
    print(json.dumps(asyncio.run(build(target)), indent=2))
