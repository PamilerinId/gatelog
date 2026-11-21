"""Landing page demo requests (unchanged from the landing-page release)."""

import logging
import re
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Header, status
from pydantic import BaseModel, Field, field_validator

from app.auth import require_internal

log = logging.getLogger("gatelog.api")
router = APIRouter(tags=["landing"])

NG_PHONE = re.compile(r"^(\+?234|0)\d{10}$")


def require_internal_token(authorization: str | None = Header(default=None)) -> None:
    """The web app calls this API server-to-server. The same check as the internal routes:
    the token is mandatory anywhere but local development."""
    require_internal(authorization)


class DemoRequest(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    estate: str = Field(min_length=2, max_length=160)
    phone: str = Field(min_length=8, max_length=32)
    source: Literal["landing"] = "landing"

    @field_validator("name", "estate")
    @classmethod
    def strip(cls, v: str) -> str:
        return v.strip()

    @field_validator("phone")
    @classmethod
    def nigerian_number(cls, v: str) -> str:
        v = re.sub(r"[\s-]", "", v)
        if not NG_PHONE.match(v):
            raise ValueError("expected a Nigerian number")
        # store in E.164
        return "+234" + v[-10:]


class Accepted(BaseModel):
    ok: bool = True
    received_at: datetime


@router.post("/v1/demo-requests", status_code=status.HTTP_202_ACCEPTED, response_model=Accepted, dependencies=[Depends(require_internal_token)])
def create_demo_request(body: DemoRequest) -> Accepted:
    # TODO(persistence): insert into demo_requests, then notify the founders. Until then, log
    # without the full number (NDPA 2023).
    log.info("demo_request estate=%r phone=***%s", body.estate, body.phone[-4:])
    return Accepted(received_at=datetime.now(timezone.utc))
