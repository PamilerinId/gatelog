"""Tell an estate's gate phones to sync now (FCM data message).

Best effort: the guard app also syncs on a timer and whenever the network returns, so a
lost push only delays a new visit reaching the gate by one poll interval. Pushes carry no
data beyond "sync", so nothing sensitive goes through Google's servers.
"""

import logging
from uuid import UUID

import httpx
from sqlalchemy import select

from . import db
from .config import get_settings
from .models import Device

log = logging.getLogger("gatelog.push")

sent: list[UUID] = []  # development and tests: estates that would have been pushed


def _access_token() -> str:
    import google.auth  # lazily: only installed where FCM is configured
    import google.auth.transport.requests

    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/firebase.messaging"])
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token


def estate_changed(estate_id: UUID) -> None:
    project = get_settings().fcm_project
    with db.session(estate_id) as s:
        tokens = [t for t in s.scalars(select(Device.fcm_token).where(Device.revoked_at.is_(None), Device.fcm_token.is_not(None)))]
    if not project:
        sent.append(estate_id)
        return
    if not tokens:
        return
    try:
        bearer = _access_token()
        for t in tokens:
            httpx.post(
                f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
                json={"message": {"token": t, "data": {"type": "sync"}, "android": {"priority": "high"}}},
                headers={"Authorization": f"Bearer {bearer}"},
                timeout=10,
            )
    except Exception as exc:
        log.warning("push failed estate=%s err=%s", estate_id, type(exc).__name__)
