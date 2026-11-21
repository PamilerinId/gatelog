"""Settings, read from the environment (and `.env` in development)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    env: str = "development"
    cors_origins: str = "http://localhost:3000"

    # The API connects as a role that does not own the tables, so Row-Level Security applies.
    database_url: str = "postgresql+psycopg://gatelog_app:gatelog_app@localhost:54329/gatelog"
    # Migrations and test setup run as the owner.
    database_owner_url: str = "postgresql+psycopg://gatelog_owner:gatelog_owner@localhost:54329/gatelog"

    # Shared bearer token for server-to-server calls (web app, Cloud Scheduler).
    api_internal_token: str | None = None

    # Signs staff and device access tokens. In production this comes from Secret Manager.
    token_secret: str = "dev-only-token-secret-change-me-in-production"
    staff_token_minutes: int = 60 * 12

    # Encrypts phone numbers at rest (Fernet, urlsafe base64, 32 bytes) and keys the blind
    # index used to look a number up without decrypting. Both from Secret Manager in production.
    phone_encryption_key: str = "s2a7Dq0bXyq4p1VQ4m3rLx8u6Z9cJt2wH5nK0fEoYgA="
    phone_index_key: str = "dev-only-phone-index-key"

    # Per-estate HMAC keys. "dev" derives them from a master secret; "gcp" reads Secret Manager.
    key_store: str = "dev"
    dev_master_key: str = "dev-only-master-key"
    gcp_project: str | None = None

    # Outbound messaging. "console" logs (masked) instead of sending.
    messaging_provider: str = "console"
    termii_api_key: str | None = None
    termii_sender_id: str = "Gatelog"
    termii_base_url: str = "https://v3.api.termii.com"
    whatsapp_token: str | None = None
    whatsapp_phone_number_id: str | None = None
    whatsapp_app_secret: str | None = None
    whatsapp_verify_token: str | None = None
    # Path secret for the inbound SMS webhook (/v1/webhooks/sms/<secret>).
    sms_webhook_secret: str | None = None
    postmark_server_token: str | None = None
    email_from: str = "Gatelog <no-reply@gatelog.ng>"
    # Gatelog ops inbox: state-tier directory alerts.
    ops_email: str | None = None

    # Firebase Cloud Messaging: a data push tells gate phones to sync now.
    fcm_project: str | None = None

    # Shift selfies: encrypted with this Fernet key before storage, deleted after 30 days.
    storage_backend: str = "local"  # local | gcs
    storage_dir: str = ".storage"
    gcs_bucket: str | None = None
    selfie_encryption_key: str = "d3YxX2Rldi1vbmx5LXNlbGZpZS1rZXktY2hhbmdlLW0="

    # Staging only: the only numbers (E.164 or local, comma-separated) and emails it may send to.
    # Anything else is withheld and logged, never sent. Staging refuses to start without both.
    allowed_phones: str | None = None
    allowed_emails: str | None = None

    @property
    def is_production(self) -> bool:
        return self.env == "production"

    @property
    def is_deployed(self) -> bool:
        """Anything reachable from the internet (staging and production): real secrets, a
        mandatory internal token, no API docs. Only local development relaxes these."""
        return self.env != "development"

    @property
    def send_allowlist(self) -> tuple[frozenset[str], frozenset[str]] | None:
        """(phones in E.164, lowercased emails) on staging; None means send to anyone."""
        if self.env != "staging":
            return None
        from .phones import normalise  # here, not at import time: phones reads settings

        phones_ = frozenset(normalise(p) for p in (self.allowed_phones or "").split(",") if p.strip())
        emails_ = frozenset(e.strip().lower() for e in (self.allowed_emails or "").split(",") if e.strip())
        return phones_, emails_


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if s.is_deployed:
        defaults = Settings.model_fields
        for name in ("token_secret", "phone_encryption_key", "phone_index_key", "selfie_encryption_key"):
            if getattr(s, name) == defaults[name].default:
                raise RuntimeError(f"{name.upper()} must be set outside development")
        if s.key_store == "dev":
            raise RuntimeError("KEY_STORE=dev is only allowed in development")
        if not s.api_internal_token:
            raise RuntimeError("API_INTERNAL_TOKEN must be set outside development")
        if s.storage_backend != "gcs":
            raise RuntimeError("STORAGE_BACKEND=gcs is required outside development (the disk is wiped on restart)")
    if s.env == "staging":
        allowed = s.send_allowlist
        if not allowed or not allowed[0] or not allowed[1]:
            raise RuntimeError("staging needs ALLOWED_PHONES and ALLOWED_EMAILS: it refuses to send to anyone else")
    return s
