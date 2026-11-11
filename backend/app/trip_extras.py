"""Live LTA DataMall details for one mode of a planned trip (/v1/trip-extras).

The app sends a point (the destination, or the start for taxis) rounded to 4 decimals and gets
a short, already filtered answer: the nearest car parks with car or motorcycle lots, the
nearest bicycle parking, or how many free taxis are around. The full datasets stay on the
server; the point is never logged or stored (the cache keys of bicycle parking hold an area of
about 1 km, not the point).
"""

import logging
import math
import re

_AREA_PARAMS = re.compile(r"\b(Lat=|Long=)[^&\s'\"]+")


class _RedactArea(logging.Filter):
    """httpx logs every request URL at INFO: the area asked from LTA's bicycle parking API
    (its `Lat` and `Long` parameters) stays out of the log, coarse as it is."""

    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        redacted = _AREA_PARAMS.sub(r"\1***", msg)
        if redacted != msg:
            record.msg = redacted
            record.args = ()
        return True


for _name in ("httpx", "httpcore"):
    logging.getLogger(_name).addFilter(_RedactArea())

MODES = ("bicycle", "car", "motorcycle", "taxi")
LOT_TYPE = {"car": "C", "motorcycle": "Y"}

# Singapore, with a margin: anything outside is not a trip the app plans.
LAT_RANGE = (1.13, 1.50)
LNG_RANGE = (103.55, 104.15)

PARKING_RADIUS_M = 1000
PARKING_MAX = 3
TAXI_RADIUS_M = 500
BICYCLE_RADIUS_M = 500
BICYCLE_MAX = 3
# Bicycle parking is asked from LTA per area: the point snapped to a 0.01 degree grid (about
# 1.1 km), with a radius that covers BICYCLE_RADIUS_M around every point in that cell.
BICYCLE_GRID = 0.01
BICYCLE_DIST_KM = 1.4
BICYCLE_TTL_S = 86400


def metres(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in metres."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (
        math.sin((p2 - p1) / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lng2 - lng1) / 2) ** 2
    )
    return 2 * 6371000 * math.asin(math.sqrt(a))


def point(lat: float, lng: float) -> tuple[float, float] | None:
    """The point rounded to 4 decimals (about 11 m), or None outside Singapore."""
    if not (math.isfinite(lat) and math.isfinite(lng)):
        return None
    if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1] and LNG_RANGE[0] <= lng <= LNG_RANGE[1]):
        return None
    return round(lat, 4), round(lng, 4)


def area(lat: float, lng: float) -> tuple[float, float]:
    """Centre of the grid cell the point is in: what LTA is asked for and the cache is keyed by."""
    return (
        round(round(lat / BICYCLE_GRID) * BICYCLE_GRID, 2),
        round(round(lng / BICYCLE_GRID) * BICYCLE_GRID, 2),
    )


def nearest_parking(rows: list[list], lat: float, lng: float, lot_type: str) -> list[dict]:
    """The nearest car parks with [lot_type] lots within PARKING_RADIUS_M, from the
    compact_parking rows [[id, agency, lat, lng, lot_type, available, name]]."""
    near = []
    for r in rows:
        try:
            if r[4] != lot_type:
                continue
            d = metres(lat, lng, float(r[2]), float(r[3]))
            if d > PARKING_RADIUS_M:
                continue
            near.append(
                {
                    "id": str(r[0]),
                    "name": str(r[6]) or str(r[0]),
                    "agency": str(r[1]),
                    "lots": int(r[5]),
                    "m": round(d),
                    "la": float(r[2]),
                    "lo": float(r[3]),
                }
            )
        except (IndexError, TypeError, ValueError):
            continue
    near.sort(key=lambda x: x["m"])
    return near[:PARKING_MAX]


def taxis_within(points: list[list[float]], lat: float, lng: float) -> int:
    """Free taxis within TAXI_RADIUS_M, from the compact_taxis rows [[lat, lng]]."""
    n = 0
    for p in points:
        try:
            if metres(lat, lng, float(p[0]), float(p[1])) <= TAXI_RADIUS_M:
                n += 1
        except (IndexError, TypeError, ValueError):
            continue
    return n


def compact_bicycle(rows: list[dict]) -> list[dict]:
    """LTA BicycleParkingv2 rows -> [{"name", "type", "racks", "sheltered", "la", "lo"}]."""
    out = []
    for r in rows:
        try:
            lat, lng = round(float(r["Latitude"]), 5), round(float(r["Longitude"]), 5)
        except (KeyError, TypeError, ValueError):
            continue
        try:
            racks = int(r.get("RackCount") or 0)
        except (TypeError, ValueError):
            racks = 0
        out.append(
            {
                "name": str(r.get("Description") or "").strip(),
                "type": str(r.get("RackType") or "").strip(),
                "racks": racks,
                "sheltered": str(r.get("ShelterIndicator") or "").strip().upper() == "Y",
                "la": lat,
                "lo": lng,
            }
        )
    return out


def nearest_bicycle(rows: list[dict], lat: float, lng: float) -> list[dict]:
    """The nearest bicycle parking within BICYCLE_RADIUS_M, each with its distance "m"."""
    near = []
    for r in rows:
        d = metres(lat, lng, r["la"], r["lo"])
        if d <= BICYCLE_RADIUS_M:
            near.append({**r, "m": round(d)})
    near.sort(key=lambda x: x["m"])
    return near[:BICYCLE_MAX]
