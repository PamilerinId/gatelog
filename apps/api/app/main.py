"""Gatelog API.

Only the landing page's demo-request intake exists so far. Estates, homes,
residents, visits, codes and entries arrive with the dashboard work, on
Postgres (see the repo README for why).
"""

import logging
import os
import re
from datetime import datetime, timezone
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

log = logging.getLogger("gatelog.api")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

app = FastAPI(title="Gatelog API", version="0.1.0", docs_url="/docs" if os.getenv("ENV") != "production" else None)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o for o in os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",") if o],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

NG_PHONE = re.compile(r"^(\+?234|0)\d{10}$")


def require_internal_token(authorization: str | None = Header(default=None)) -> None:
    """The web app calls this API server-to-server. If a token is configured, require it."""
    expected = os.getenv("API_INTERNAL_TOKEN")
    if expected and authorization != f"Bearer {expected}":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorised")


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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/demo-requests", status_code=status.HTTP_202_ACCEPTED, response_model=Accepted, dependencies=[Depends(require_internal_token)])
def create_demo_request(body: DemoRequest) -> Accepted:
    # TODO(persistence): insert into demo_requests once the Postgres schema lands,
    # then notify the founders. Until then, log without the full number (NDPA 2023).
    log.info("demo_request estate=%r phone=***%s", body.estate, body.phone[-4:])
    return Accepted(received_at=datetime.now(timezone.utc))
