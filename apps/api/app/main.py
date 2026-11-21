"""Gatelog API.

    /v1/device    the gate phone: pair, pull state, push its offline queue
    /v1/webhooks  resident messages in (WhatsApp, SMS)
    /v1/admin     estate admin dashboard
    /v1/reports   committee reports and Excel export
    /v1/ops       Gatelog ops: estates, state and LGA emergency numbers
    /v1/auth      dashboard sign-in
    /internal     Cloud Scheduler: the job tick
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .routers import admin, auth, demo, device, estate_map, imports, internal, ops, reports, shuttle_admin, webhooks

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

settings = get_settings()
app = FastAPI(title="Gatelog API", version="1.0.0", docs_url=None if settings.is_deployed else "/docs", redoc_url=None if settings.is_deployed else "/redoc", openapi_url=None if settings.is_deployed else "/openapi.json")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[o for o in settings.cors_origins.split(",") if o],
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Estate-Id", "If-None-Match"],
    expose_headers=["ETag", "Content-Disposition"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


for r in (demo, auth, device, webhooks, admin, estate_map, shuttle_admin, imports, reports, ops, internal):
    app.include_router(r.router)
