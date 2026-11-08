"""Per-estate HMAC keys.

Each estate has a current key version. Visits record the version their code was derived
with, so revoking a lost gate phone (which bumps the version) does not invalidate codes
residents already hold; the device sync hands out every version an open visit still needs.

Keys never sit in env files or the repo. In production they live in Secret Manager as
`gatelog-estate-<estate_id>-hmac`, one secret version per key version.
"""

import hashlib
import hmac
import secrets
from functools import lru_cache
from typing import Protocol
from uuid import UUID

from .config import get_settings


class KeyStore(Protocol):
    def get(self, estate_id: UUID, version: int) -> bytes: ...
    def create_version(self, estate_id: UUID) -> int: ...


class DevKeyStore:
    """Derives keys from a master secret. Development and tests only."""

    def __init__(self, master: str) -> None:
        self._master = master.encode()

    def get(self, estate_id: UUID, version: int) -> bytes:
        return hmac.new(self._master, f"{estate_id}:{version}".encode(), hashlib.sha256).digest()

    def create_version(self, estate_id: UUID) -> int:
        # Versions are tracked on the estate row; derivation needs nothing stored.
        raise NotImplementedError("the estate row tracks versions in dev")


class SecretManagerKeyStore:
    def __init__(self, project: str) -> None:
        from google.cloud import secretmanager  # imported lazily: only needed in production

        self._client = secretmanager.SecretManagerServiceClient()
        self._project = project

    def _secret(self, estate_id: UUID) -> str:
        return f"projects/{self._project}/secrets/gatelog-estate-{estate_id}-hmac"

    @lru_cache(maxsize=512)
    def get(self, estate_id: UUID, version: int) -> bytes:
        res = self._client.access_secret_version(name=f"{self._secret(estate_id)}/versions/{version}")
        return res.payload.data

    def create_version(self, estate_id: UUID) -> int:
        name = self._secret(estate_id)
        try:
            self._client.get_secret(name=name)
        except Exception:
            self._client.create_secret(
                parent=f"projects/{self._project}",
                secret_id=name.rsplit("/", 1)[1],
                secret={"replication": {"automatic": {}}},
            )
        v = self._client.add_secret_version(parent=name, payload={"data": secrets.token_bytes(32)})
        return int(v.name.rsplit("/", 1)[1])


@lru_cache
def key_store() -> KeyStore:
    s = get_settings()
    if s.key_store == "gcp":
        if not s.gcp_project:
            raise RuntimeError("GCP_PROJECT is required for KEY_STORE=gcp")
        return SecretManagerKeyStore(s.gcp_project)
    return DevKeyStore(s.dev_master_key)


def next_version(estate_id: UUID, current: int) -> int:
    """The version to move to when rotating (device revoked, or estate created)."""
    store = key_store()
    if isinstance(store, DevKeyStore):
        return current + 1
    return store.create_version(estate_id)
