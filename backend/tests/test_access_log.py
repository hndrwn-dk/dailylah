"""The access log must not hold search text or the codes users send (root CLAUDE.md,
"Privacy rules"; docs/legal/privacy.md 4a and 5). A real uvicorn server serves the app, so
the request lines are the ones uvicorn writes on Render."""

import logging
import socket
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest
import uvicorn

from app.config import get_settings
from app.main import app, redact_access_path

SEARCH = "Blk 123 Secret Street"
# Each request fails validation (or has no key), so nothing reaches an upstream.
REQUESTS = [
    ("/v1/search", {"q": SEARCH + " x" * 40}, SEARCH),  # too long: 422
    ("/v1/places", {"q": SEARCH}, SEARCH),  # no Geoapify key: 503
    ("/v1/bus-arrival/8313X", None, "8313X"),
    ("/v1/ev/56789X", None, "56789X"),
    ("/v1/agent/R12345", None, "R12345"),
]


class _Collect(logging.Handler):
    def __init__(self) -> None:
        super().__init__()
        self.lines: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.lines.append(record.getMessage())


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def access_lines(monkeypatch):
    monkeypatch.setenv("ENV", "dev")
    monkeypatch.delenv("GEOAPIFY_API_KEY", raising=False)
    monkeypatch.delenv("REDIS_URL", raising=False)
    get_settings.cache_clear()
    access = logging.getLogger("uvicorn.access")
    handler = _Collect()
    old_level = access.level
    access.setLevel(logging.INFO)
    access.addHandler(handler)
    port = _free_port()
    config = uvicorn.Config(app, host="127.0.0.1", port=port, log_config=None, access_log=True)
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 10
        while not server.started:
            assert time.monotonic() < deadline, "uvicorn did not start"
            time.sleep(0.02)
        for path, params, _ in REQUESTS:
            url = f"http://127.0.0.1:{port}{path}"
            if params:
                url += "?" + urllib.parse.urlencode(params)
            try:
                urllib.request.urlopen(url, timeout=5)  # noqa: S310 - local test server
            except urllib.error.HTTPError:
                pass  # 4xx/5xx expected
        yield handler.lines
    finally:
        server.should_exit = True
        thread.join(timeout=10)
        access.removeHandler(handler)
        access.setLevel(old_level)
        get_settings.cache_clear()


def test_access_log_keeps_endpoint_and_status_but_not_user_input(access_lines):
    assert len(access_lines) == len(REQUESTS)
    joined = "\n".join(access_lines)
    for _, params, secret in REQUESTS:
        for form in {secret, urllib.parse.quote_plus(secret), urllib.parse.quote(secret)}:
            assert form not in joined
        if params:
            assert "q=" not in joined
    assert '"GET /v1/search HTTP/1.1" 422' in joined
    assert '"GET /v1/places HTTP/1.1" 503' in joined
    assert '"GET /v1/bus-arrival/* HTTP/1.1" 422' in joined
    assert '"GET /v1/ev/* HTTP/1.1" 422' in joined
    assert '"GET /v1/agent/* HTTP/1.1" 422' in joined


@pytest.mark.parametrize(
    ("path", "logged"),
    [
        ("/v1/search?q=Blk%20123", "/v1/search"),
        ("/v1/places?q=jewel&x=1", "/v1/places"),
        ("/v1/bus-arrival/83139", "/v1/bus-arrival/*"),
        ("/v1/ev/123456?x=1", "/v1/ev/*"),
        ("/v1/agent/R012345A", "/v1/agent/*"),
        ("/v1/crowd/NSL", "/v1/crowd/NSL"),
        ("/v1/weather/forecast", "/v1/weather/forecast"),
        ("/v1/evil/123", "/v1/evil/123"),
        ("/health", "/health"),
    ],
)
def test_redact_access_path(path, logged):
    assert redact_access_path(path) == logged
