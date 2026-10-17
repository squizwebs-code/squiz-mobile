"""Environment-based configuration. No secrets are hardcoded; JWT_SECRET must be provided."""
from functools import lru_cache

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "development"
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    cors_origins: str = ""
    upload_dir: str = "./uploads"
    max_upload_mb: int = 2
    rate_limit_enabled: bool = True
    exam_submit_grace_seconds: int = 10
    app_timezone: str = "Africa/Addis_Ababa"      # day boundaries for streaks and daily charts

    @field_validator("jwt_secret")
    @classmethod
    def _secret_strength(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET must be at least 32 characters")
        return v

    @model_validator(mode="after")
    def _prod_checks(self):
        if self.env == "production" and "*" in self.cors_origin_list:
            raise ValueError("CORS_ORIGINS must not contain '*' in production")
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
