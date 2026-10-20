"""SVY21 (Singapore grid, metres) to WGS84 lat/lng.

Transverse Mercator inverse as published by the Singapore Land Authority,
following the widely used reference implementation (cgcai/SVY21).
"""

import math

_A = 6378137.0
_F = 1 / 298.257223563
_O_LAT = 1.366666  # origin latitude, degrees
_O_LON = 103.833333  # origin longitude, degrees
_O_N = 38744.572  # false northing
_O_E = 28001.642  # false easting
_K = 1.0  # central meridian scale factor

_B = _A * (1 - _F)
_E2 = (2 * _F) - (_F * _F)
_E4 = _E2 * _E2
_E6 = _E4 * _E2
_A0 = 1 - (_E2 / 4) - (3 * _E4 / 64) - (5 * _E6 / 256)
_A2 = (3.0 / 8.0) * (_E2 + (_E4 / 4) + (15 * _E6 / 128))
_A4 = (15.0 / 256.0) * (_E4 + (3 * _E6 / 4))
_A6 = 35 * _E6 / 3072


def _meridian_distance(lat_deg: float) -> float:
    r = math.radians(lat_deg)
    return _A * (
        (_A0 * r) - (_A2 * math.sin(2 * r)) + (_A4 * math.sin(4 * r)) - (_A6 * math.sin(6 * r))
    )


def to_latlon(northing: float, easting: float) -> tuple[float, float]:
    """SVY21 (N, E) in metres -> (lat, lng) in degrees."""
    n_prime = northing - _O_N
    m_prime = _meridian_distance(_O_LAT) + (n_prime / _K)

    n = (_A - _B) / (_A + _B)
    n2, n3, n4 = n * n, n**3, n**4
    g = _A * (1 - n) * (1 - n2) * (1 + (9 * n2 / 4) + (225 * n4 / 64)) * (math.pi / 180)
    sigma = (m_prime * math.pi) / (180.0 * g)

    lat_prime = (
        sigma
        + ((3 * n / 2) - (27 * n3 / 32)) * math.sin(2 * sigma)
        + ((21 * n2 / 16) - (55 * n4 / 32)) * math.sin(4 * sigma)
        + (151 * n3 / 96) * math.sin(6 * sigma)
        + (1097 * n4 / 512) * math.sin(8 * sigma)
    )

    sin2 = math.sin(lat_prime) ** 2
    rho = _A * (1 - _E2) / ((1 - _E2 * sin2) ** 1.5)
    v = _A / math.sqrt(1 - _E2 * sin2)
    psi = v / rho
    psi2, psi3, psi4 = psi**2, psi**3, psi**4
    t = math.tan(lat_prime)
    t2, t4, t6 = t**2, t**4, t**6

    e_prime = easting - _O_E
    x = e_prime / (_K * v)
    x2 = x * x
    x3, x5, x7 = x * x2, x**5, x**7

    lat_factor = t / (_K * rho)
    lat = (
        lat_prime
        - lat_factor * ((e_prime * x) / 2)
        + lat_factor * ((e_prime * x3) / 24) * ((-4 * psi2) + (9 * psi) * (1 - t2) + (12 * t2))
        - lat_factor
        * ((e_prime * x5) / 720)
        * (
            (8 * psi4) * (11 - 24 * t2)
            - (12 * psi3) * (21 - 71 * t2)
            + (15 * psi2) * (15 - 98 * t2 + 15 * t4)
            + (180 * psi) * (5 * t2 - 3 * t4)
            + 360 * t4
        )
        + lat_factor * ((e_prime * x7) / 40320) * (1385 - 3633 * t2 + 4095 * t4 + 1575 * t6)
    )

    sec = 1 / math.cos(lat)
    lon = (
        math.radians(_O_LON)
        + x * sec
        - ((x3 * sec) / 6) * (psi + 2 * t2)
        + ((x5 * sec) / 120)
        * ((-4 * psi3) * (1 - 6 * t2) + psi2 * (9 - 68 * t2) + 72 * psi * t2 + 24 * t4)
        - ((x7 * sec) / 5040) * (61 + 662 * t2 + 1320 * t4 + 720 * t6)
    )
    return math.degrees(lat), math.degrees(lon)
