"""Outbound messages: queue in the caller's transaction, send after commit.

Residents choose WhatsApp, SMS or calls. Call-preferring residents get SMS for written
notices. WhatsApp goes out only once the estate's WhatsApp Business account is approved;
until then WhatsApp residents get SMS too.

Business-initiated WhatsApp messages (codes, arrival and exit notices, nudges, the night
list) must use pre-approved templates: see docs/whatsapp-templates.md. Replies inside a
conversation the resident started go as plain text.
"""

import logging
from dataclasses import dataclass
from datetime import timedelta
from typing import Protocol
from uuid import UUID

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import abuse, clock, db, email, phones
from .config import get_settings
from .estate_settings import EstateSettings
from .models import Estate, MessageLog, PhoneNumber, Resident

log = logging.getLogger("gatelog.messaging")

MAX_ATTEMPTS = 5

# kind -> (WhatsApp template name, ordered parameter keys). "estate" comes first in every
# template: all estates share one WhatsApp number, so each message says whose it is.
TEMPLATES: dict[str, tuple[str, tuple[str, ...]]] = {
    "gate_code": ("gatelog_gate_code", ("estate", "guest", "code", "valid_until")),
    "arrival": ("gatelog_arrival", ("estate", "guest", "gate", "time")),
    "departure": ("gatelog_departure", ("estate", "guest", "gate", "time")),
    "overstay_nudge": ("gatelog_overstay", ("estate", "guest")),
    "rollup": ("gatelog_night_list", ("estate", "count", "summary")),
    "ride_on_way": ("gatelog_shuttle_on_way", ("estate", "rider", "shuttle", "from")),
    "parcel_on_way": ("gatelog_parcel_on_way", ("estate", "parcel", "from")),
}

# Shown in the Exco's usage view but never counted towards the allowance or billed, so no one
# hesitates to raise an alarm or look up an emergency number.
# Safety alerts to a home (an unchecked entry, a wrong home PIN, a disputed entry) too: nobody
# should weigh the cost of telling a home that a stranger was let in for them.
UNBILLED_KINDS = frozenset({"sos_not_live", "numbers", "unverified_entry", "wrong_pin", "entry_disputed", "number_offer", "number_added"})
UNBILLED_PREFIXES = ("sos",)


def billable(kind: str) -> bool:
    return kind not in UNBILLED_KINDS and not kind.startswith(UNBILLED_PREFIXES)


# How a message kind shows in the usage view.
PURPOSES = {
    "gate_code": "Guest codes", "stay_question": "Guest codes", "stay_noted": "Guest codes", "callback_notice": "Guest codes",
    "cancel": "Guest codes", "visit_cap": "Guest codes", "help": "Guest codes", "which_home": "Guest codes", "reply": "Guest codes",
    "arrival": "Arrival and exit notices", "departure": "Arrival and exit notices",
    "overstay_nudge": "Overstay nudges", "nudge_question": "Overstay nudges", "nudge_noted": "Overstay nudges",
    "rollup": "Night lists",
    "dues_reminder": "Dues reminders", "dues_receipt": "Dues reminders",
    "event_pass": "Event and worker passes", "worker_pass": "Event and worker passes",
    "numbers": "Emergency numbers", "sos_not_live": "SOS",
    "ride_booked": "Shuttle", "ride_question": "Shuttle", "ride_cancelled": "Shuttle", "ride_on_way": "Shuttle",
    "parcel_on_way": "Shuttle", "house_code": "Home PIN", "dispute_noted": "Gate safety alerts",
    "unverified_entry": "Gate safety alerts", "wrong_pin": "Gate safety alerts", "entry_disputed": "Gate safety alerts",
    "number_offer": "Gate safety alerts", "number_added": "Gate safety alerts", "number_answer": "Gate safety alerts",
}


def purpose(kind: str) -> str:
    return PURPOSES.get(kind, "SOS" if kind.startswith("sos") else "Other")


@dataclass
class Outgoing:
    to: str  # E.164; exists only in memory, never logged
    channel: str
    kind: str
    body: str
    params: dict | None


class Sender(Protocol):
    def send(self, msg: Outgoing) -> str | None: ...


class ConsoleSender:
    """Development and tests: records messages instead of sending them."""

    def __init__(self) -> None:
        self.sent: list[Outgoing] = []

    def send(self, msg: Outgoing) -> str | None:
        self.sent.append(msg)
        log.info("message channel=%s to=%s kind=%s", msg.channel, phones.mask(msg.to), msg.kind)
        return None


class TermiiSender:
    def __init__(self, api_key: str, sender_id: str, base_url: str) -> None:
        self._key, self._from, self._base = api_key, sender_id, base_url.rstrip("/")

    def send(self, msg: Outgoing) -> str | None:
        # The "dnd" route reaches numbers on Do-Not-Disturb, which most Nigerian lines are;
        # it needs the registered sender ID.
        r = httpx.post(
            f"{self._base}/api/sms/send",
            json={"api_key": self._key, "to": msg.to.lstrip("+"), "from": self._from, "sms": msg.body, "type": "plain", "channel": "dnd"},
            timeout=15,
        )
        r.raise_for_status()
        return str(r.json().get("message_id") or "")


class WhatsAppSender:
    def __init__(self, token: str, phone_number_id: str) -> None:
        self._token, self._pnid = token, phone_number_id

    def send(self, msg: Outgoing) -> str | None:
        payload: dict = {"messaging_product": "whatsapp", "to": msg.to.lstrip("+")}
        if msg.kind in TEMPLATES and msg.params is not None:
            name, keys = TEMPLATES[msg.kind]
            payload |= {
                "type": "template",
                "template": {
                    "name": name,
                    "language": {"code": "en"},
                    "components": [{"type": "body", "parameters": [{"type": "text", "text": str(msg.params[k])} for k in keys]}],
                },
            }
        else:
            payload |= {"type": "text", "text": {"body": msg.body}}
        r = httpx.post(
            f"https://graph.facebook.com/v21.0/{self._pnid}/messages",
            json=payload,
            headers={"Authorization": f"Bearer {self._token}"},
            timeout=15,
        )
        r.raise_for_status()
        return r.json()["messages"][0]["id"]


class Router:
    def __init__(self, sms: Sender, whatsapp: Sender) -> None:
        self.sms, self.whatsapp = sms, whatsapp

    def send(self, msg: Outgoing) -> str | None:
        return (self.whatsapp if msg.channel == "whatsapp" else self.sms).send(msg)


class Withheld(Exception):
    """Staging refused to send to a number that is not on its allowlist."""


class AllowlistSender:
    """Staging only. Wraps the real sender, so every path out (the queue, ops releases, direct
    replies) passes the same check. Off the list: nothing is sent, and the caller is told."""

    def __init__(self, inner: Sender, allowed: frozenset[str]) -> None:
        self.inner, self.allowed = inner, allowed

    def send(self, msg: Outgoing) -> str | None:
        if msg.to not in self.allowed:
            log.warning("message WITHHELD (staging allowlist) channel=%s to=%s kind=%s", msg.channel, phones.mask(msg.to), msg.kind)
            raise Withheld(phones.mask(msg.to))
        return self.inner.send(msg)


_sender: Sender | None = None


def sender() -> Sender:
    global _sender
    if _sender is None:
        s = get_settings()
        if s.messaging_provider == "live":
            sms = TermiiSender(s.termii_api_key or "", s.termii_sender_id, s.termii_base_url)
            wa = WhatsAppSender(s.whatsapp_token or "", s.whatsapp_phone_number_id or "") if s.whatsapp_token else sms
            _sender = Router(sms, wa)
        else:
            _sender = ConsoleSender()
        allowed = s.send_allowlist
        if allowed is not None:
            _sender = AllowlistSender(_sender, allowed[0])
    return _sender


def use_sender(s: Sender) -> None:
    global _sender
    _sender = s


# --- Queueing ------------------------------------------------------------------------------


def channel_for(estate: Estate, contact_pref: str) -> str:
    if contact_pref == "whatsapp" and EstateSettings.model_validate(estate.settings).whatsapp_enabled:
        return "whatsapp"
    return "sms"


def primary_number(db_: Session, resident_id: UUID) -> PhoneNumber | None:
    return db_.scalars(
        select(PhoneNumber)
        .where(PhoneNumber.resident_id == resident_id, PhoneNumber.pending_until.is_(None))
        .order_by(PhoneNumber.is_primary.desc(), PhoneNumber.created_at)
        .limit(1)
    ).first()


def queue(db_: Session, estate_id: UUID, number: PhoneNumber, channel: str, kind: str, body: str, params: dict | None = None) -> MessageLog:
    """Every message names its estate first ("SKA Exco: ..."): the sender shows as Gatelog
    for every estate, so the body has to say whose message it is."""
    estate = db_.get(Estate, estate_id)
    if estate is not None:
        body = f"{estate.sender_name}: {body}"
        if params is not None:
            params = {"estate": estate.sender_name, **params}
    m = MessageLog(
        estate_id=estate_id, direction="out", channel=channel, number_id=number.id, to_last4=number.last4,
        kind=kind, body=body, params=params, status="queued", created_at=clock.now(),
    )
    db_.add(m)
    return m


def to_resident(db_: Session, estate: Estate, resident: Resident, kind: str, body: str, params: dict | None = None, *, number: PhoneNumber | None = None) -> MessageLog | None:
    number = number or primary_number(db_, resident.id)
    if number is None:
        log.warning("no number for resident=%s kind=%s", resident.id, kind)
        return None
    return queue(db_, estate.id, number, channel_for(estate, resident.contact_pref), kind, body, params)


def to_number(db_: Session, estate: Estate, number: PhoneNumber, kind: str, body: str, *, prefer_whatsapp: bool = False) -> MessageLog:
    return queue(db_, estate.id, number, channel_for(estate, "whatsapp" if prefer_whatsapp else "sms"), kind, body)


def log_inbound(db_: Session, estate_id: UUID, number: PhoneNumber, channel: str, kind: str) -> None:
    db_.add(MessageLog(estate_id=estate_id, direction="in", channel=channel, number_id=number.id, to_last4=number.last4, kind=kind, status="received", created_at=clock.now()))


# --- Dispatch ------------------------------------------------------------------------------


def _within_limits(s: Session, m: MessageLog) -> bool:
    """Checked once per message, before its first send attempt."""
    if not abuse.hit(s, abuse.OUTBOUND_PER_NUMBER, str(m.number_id)):
        return False
    if m.channel != "sms":
        return True
    estate = s.get(Estate, m.estate_id)
    budget = EstateSettings.model_validate(estate.settings).daily_sms_budget
    if abuse.hit(s, abuse.Limit("sms-day", budget, timedelta(days=1)), str(m.estate_id)):
        return True
    # Tell ops once per estate per day; the held messages wait for a person to decide.
    if abuse.hit(s, abuse.Limit("sms-budget-alert", 1, timedelta(days=1)), str(m.estate_id)):
        ops = get_settings().ops_email
        if ops:
            email.send(ops, f"SMS budget reached: {estate.name}",
                       f"{estate.name} has sent {budget} SMS today, its daily budget. Further SMS are held, not sent. "
                       "Check for abuse, then release or drop them from the ops API.")
    return False


def dispatch(limit: int = 50) -> int:
    """Send queued messages across all estates. Safe to run concurrently: rows are claimed
    with SKIP LOCKED. Called after each request that queued something, and by the scheduler
    tick to retry anything that failed."""
    sent = 0
    with db.session(ops=True) as s:
        rows = s.scalars(
            select(MessageLog)
            .where(MessageLog.direction == "out", MessageLog.status == "queued")
            .order_by(MessageLog.created_at)
            .limit(limit)
            .with_for_update(skip_locked=True)
        ).all()
        for m in rows:
            number = s.get(PhoneNumber, m.number_id) if m.number_id else None
            if number is None:
                m.status, m.body = "failed", None
                continue
            if m.attempts == 0 and not _within_limits(s, m):  # released messages skip this
                m.status = "held"
                continue
            m.attempts += 1
            try:
                m.provider_id = sender().send(Outgoing(phones.decrypt(number.e164_enc), m.channel, m.kind, m.body or "", m.params))
                m.status, m.body, m.params, m.sent_at = "sent", None, None, clock.now()
                sent += 1
            except Withheld:  # staging: off the allowlist. Not sent, not retried, text kept to read.
                m.status = "withheld"
            except Exception as exc:  # provider down or rejected: keep for the next tick
                log.warning("send failed id=%s kind=%s to=***%s attempt=%d err=%s", m.id, m.kind, m.to_last4, m.attempts, type(exc).__name__)
                if m.attempts >= MAX_ATTEMPTS:
                    m.status, m.body, m.params = "failed", None, None
    return sent
