"""Phone numbers: normalise to E.164, mask for display and logs, encrypt at rest.

Full numbers live only in `phone_numbers` and `emergency_contacts`, encrypted. Everywhere
else (logs, Sentry, other tables, API responses that do not need the full number) carries
the last four digits only. Lookups by number go through a keyed blind index, so finding the
resident behind an inbound message never needs a decrypt-and-scan.
"""

import hashlib
import hmac
import re

from cryptography.fernet import Fernet

from .config import get_settings

_NG_LOCAL = re.compile(r"^(?:\+?234|0)([789][01]\d{8})$")
_INTL = re.compile(r"^\+[1-9]\d{7,14}$")


class InvalidPhone(ValueError):
    pass


def normalise(raw: str) -> str:
    """Return E.164. Nigerian numbers may be given locally (0803...) or with 234/+234.
    Relatives abroad must give the full international form (+44...)."""
    v = re.sub(r"[\s\-().]", "", raw or "")
    if v.startswith("00"):
        v = "+" + v[2:]
    m = _NG_LOCAL.match(v)
    if m:
        return "+234" + m.group(1)
    if _INTL.match(v):
        return v
    raise InvalidPhone("not a phone number we can use")


def last4(e164: str) -> str:
    return e164[-4:]


def mask(e164: str) -> str:
    """'+2348031234567' -> '***4567'. The only form a number may take in logs."""
    return f"***{last4(e164)}"


def blind_index(e164: str) -> str:
    key = get_settings().phone_index_key.encode()
    return hmac.new(key, e164.encode(), hashlib.sha256).hexdigest()


def _fernet() -> Fernet:
    return Fernet(get_settings().phone_encryption_key.encode())


def encrypt(e164: str) -> bytes:
    return _fernet().encrypt(e164.encode())


def decrypt(token: bytes) -> str:
    return _fernet().decrypt(bytes(token)).decode()
