"""Transactional email through Postmark: dashboard sign-in codes and directory alerts."""

import logging

import httpx

from .config import get_settings

log = logging.getLogger("gatelog.email")

outbox: list[tuple[str, str, str]] = []  # development and tests


def send(to: str, subject: str, body: str) -> None:
    s = get_settings()
    if not s.postmark_server_token:
        outbox.append((to, subject, body))
        log.info("email to=%s subject=%r (not sent: no Postmark token)", to.split("@")[-1], subject)
        if not s.is_production:  # local development only: lets you sign in without Postmark
            print(f"[dev email] {subject}", flush=True)
        return
    r = httpx.post(
        "https://api.postmarkapp.com/email",
        json={"From": s.email_from, "To": to, "Subject": subject, "TextBody": body, "MessageStream": "outbound"},
        headers={"X-Postmark-Server-Token": s.postmark_server_token, "Accept": "application/json"},
        timeout=15,
    )
    r.raise_for_status()
