"""Endpoints for Cloud Scheduler. Protected by API_INTERNAL_TOKEN."""

from fastapi import APIRouter, Depends

from .. import jobs, messaging
from ..auth import require_internal

router = APIRouter(prefix="/internal", tags=["internal"], dependencies=[Depends(require_internal)])


@router.post("/jobs/tick")
def tick() -> dict:
    """Every 5 minutes: overstay nudges, the nightly rollup, the morning handover, and a
    retry of any messages that failed to send."""
    return jobs.tick()


@router.post("/jobs/dispatch")
def dispatch() -> dict:
    return {"sent": messaging.dispatch()}
