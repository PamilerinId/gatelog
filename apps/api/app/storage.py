"""Blob storage for shift selfies. Everything is encrypted before it is stored, so a bucket
that is misconfigured or copied still holds nothing readable. Local disk in development,
Cloud Storage in production."""

import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Protocol

from cryptography.fernet import Fernet

from .config import get_settings

log = logging.getLogger("gatelog.storage")


class Store(Protocol):
    def put(self, key: str, data: bytes) -> None: ...
    def get(self, key: str) -> bytes | None: ...
    def delete(self, key: str) -> None: ...


class LocalStore:
    def __init__(self, root: str) -> None:
        self.root = Path(root)

    def _path(self, key: str) -> Path:
        p = (self.root / key).resolve()
        if self.root.resolve() not in p.parents:
            raise ValueError("bad key")
        return p

    def put(self, key: str, data: bytes) -> None:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def get(self, key: str) -> bytes | None:
        p = self._path(key)
        return p.read_bytes() if p.exists() else None

    def delete(self, key: str) -> None:
        p = self._path(key)
        if p.exists():
            os.remove(p)


class GcsStore:
    def __init__(self, bucket: str) -> None:
        from google.cloud import storage as gcs  # only installed in production

        self.bucket = gcs.Client().bucket(bucket)

    def put(self, key: str, data: bytes) -> None:
        self.bucket.blob(key).upload_from_string(data, content_type="application/octet-stream")

    def get(self, key: str) -> bytes | None:
        b = self.bucket.blob(key)
        return b.download_as_bytes() if b.exists() else None

    def delete(self, key: str) -> None:
        b = self.bucket.blob(key)
        if b.exists():
            b.delete()


@lru_cache
def store() -> Store:
    s = get_settings()
    if s.storage_backend == "gcs":
        if not s.gcs_bucket:
            raise RuntimeError("GCS_BUCKET is required for STORAGE_BACKEND=gcs")
        return GcsStore(s.gcs_bucket)
    return LocalStore(s.storage_dir)


def _fernet() -> Fernet:
    return Fernet(get_settings().selfie_encryption_key.encode())


def put_encrypted(key: str, data: bytes) -> None:
    store().put(key, _fernet().encrypt(data))


def get_decrypted(key: str) -> bytes | None:
    blob = store().get(key)
    return _fernet().decrypt(blob) if blob is not None else None
