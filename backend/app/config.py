from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime config. Every secret comes from env vars (Render dashboard), never from code."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "dev"

    # data.gov.sg — optional key, raises rate limits (header: x-api-key)
    datagov_api_key: str | None = None
    datagov_base_url: str = "https://api-open.data.gov.sg/v2/real-time/api"

    # data.gov.sg v1 real-time (car park availability) and dataset search (CEA register)
    carpark_url: str = "https://api.data.gov.sg/v1/transport/carpark-availability"
    datastore_url: str = "https://data.gov.sg/api/action/datastore_search"
    cea_dataset_id: str = "d_07c63be0f37e6e59c07a4ddc2fd87fcb"

    # LTA DataMall — required for bus/train endpoints (header: AccountKey)
    lta_account_key: str | None = None
    lta_base_url: str = "https://datamall2.mytransport.sg/ltaodataservice"

    # OneMap account (Singapore Land Authority); the token is requested at runtime.
    onemap_email: str | None = None
    onemap_password: str | None = None
    search_ttl: int = 86400

    # URA Data Service (private property); a daily token is requested from the key.
    ura_access_key: str | None = None

    # Upstash Redis (redis:// or rediss:// URL). Empty = in-memory only (local dev).
    redis_url: str | None = None

    # Neon Postgres (static + spatial data). Not used by the MVP endpoints yet.
    database_url: str | None = None

    # QStash signature verification for /internal/poll
    qstash_current_signing_key: str | None = None
    qstash_next_signing_key: str | None = None
    public_base_url: str = "http://localhost:8000"

    # Cache TTLs (seconds)
    bus_arrival_ttl: int = 20
    agent_ttl: int = 86400
    http_timeout: float = 10.0


@lru_cache
def get_settings() -> Settings:
    return Settings()
