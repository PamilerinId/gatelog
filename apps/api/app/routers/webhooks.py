"""Inbound resident messages: WhatsApp Cloud API and SMS (Termii)."""

import hashlib
import hmac
import logging

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request, Response

from .. import conversation, messaging, push
from ..config import get_settings

log = logging.getLogger("gatelog.webhooks")
router = APIRouter(prefix="/v1/webhooks", tags=["webhooks"])

MAX_PAYLOAD = 256 * 1024


def _after(bg: BackgroundTasks, result: conversation.Result) -> None:
    bg.add_task(messaging.dispatch)
    if result.changed and result.estate_id:
        bg.add_task(push.estate_changed, result.estate_id)


@router.get("/whatsapp")
def whatsapp_verify(
    mode: str = Query(alias="hub.mode"), token: str = Query(alias="hub.verify_token"), challenge: str = Query(alias="hub.challenge")
) -> Response:
    expected = get_settings().whatsapp_verify_token
    if mode != "subscribe" or not expected or not hmac.compare_digest(token, expected):
        raise HTTPException(403, "forbidden")
    return Response(challenge, media_type="text/plain")


@router.post("/whatsapp")
async def whatsapp(request: Request, bg: BackgroundTasks) -> dict:
    raw = await request.body()
    if len(raw) > MAX_PAYLOAD:
        raise HTTPException(413, "too large")
    secret = get_settings().whatsapp_app_secret
    if not secret:
        raise HTTPException(503, "WhatsApp is not configured")
    sig = request.headers.get("X-Hub-Signature-256", "")
    expected = "sha256=" + hmac.new(secret.encode(), raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(sig, expected):
        raise HTTPException(401, "bad signature")
    payload = await request.json()
    for entry in payload.get("entry", []):
        for change in entry.get("changes", []):
            for msg in change.get("value", {}).get("messages", []):
                if msg.get("type") == "text":
                    body = msg["text"]["body"]
                elif msg.get("type") == "button":
                    body = msg["button"].get("text", "")
                elif msg.get("type") == "interactive":
                    i = msg["interactive"]
                    body = (i.get("button_reply") or i.get("list_reply") or {}).get("id", "")
                else:
                    continue  # voice notes, images: not understood yet
                _after(bg, conversation.handle("whatsapp", "+" + msg["from"].lstrip("+"), body, msg.get("id")))
    return {"ok": True}  # always 200, or Meta retries and the resident gets a second code


@router.post("/sms/{secret}")
async def sms(secret: str, request: Request, bg: BackgroundTasks) -> dict:
    """Inbound SMS from the provider. The secret in the path is configured in the provider's
    dashboard; it is the only authentication SMS webhooks offer."""
    expected = get_settings().sms_webhook_secret
    if not expected or not hmac.compare_digest(secret, expected):
        raise HTTPException(404, "not found")
    if int(request.headers.get("content-length") or 0) > MAX_PAYLOAD:
        raise HTTPException(413, "too large")
    data = await request.json() if "json" in request.headers.get("content-type", "") else dict(await request.form())
    sender = data.get("sender") or data.get("from") or data.get("msisdn") or ""
    body = data.get("message") or data.get("text") or data.get("sms") or data.get("body") or ""
    if sender and body:
        message_id = data.get("id") or data.get("message_id") or data.get("messageId")
        _after(bg, conversation.handle("sms", str(sender), str(body), str(message_id) if message_id else None))
    return {"ok": True}
