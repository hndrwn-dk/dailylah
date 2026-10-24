"""data.gov.sg API key handling shared by the poller and the daily build.

The key is optional: it only raises rate limits. Keys expire (the current one at the end of
2026), and an expired key is rejected with 401/403 instead of being ignored. When that
happens we retry the same request without the key, keep going without it, and log a clear
warning so the key gets renewed (GitHub secret and Render env DATAGOV_API_KEY).
"""

import logging

import httpx

log = logging.getLogger("dailylah.datagov")

REJECTED = (401, 403)


class DataGovKey:
    def __init__(self, key: str | None) -> None:
        self.key = key or None
        self.rejected = False

    def headers(self) -> dict[str, str]:
        return {"x-api-key": self.key} if self.key and not self.rejected else {}

    async def get(
        self, client: httpx.AsyncClient, url: str, params: dict | None = None
    ) -> httpx.Response:
        """GET with the key; on 401/403 retry once without it. The key is only marked as
        rejected when the keyless retry works, so a dataset-level 403 does not drop it."""
        headers = self.headers()
        resp = await client.get(url, params=params, headers=headers)
        if not headers or resp.status_code not in REJECTED:
            return resp
        retry = await client.get(url, params=params)
        if retry.is_success:
            if not self.rejected:
                log.warning(
                    "DATAGOV_API_KEY rejected (HTTP %s); continuing without it. "
                    "Renew the key on data.gov.sg and update the GitHub secret and Render env.",
                    resp.status_code,
                )
            self.rejected = True
            return retry
        return resp
