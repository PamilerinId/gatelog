"""Per-estate settings, stored as JSON on the estate row. Defaults come from the spec."""

from datetime import time

from pydantic import BaseModel, Field


class EstateSettings(BaseModel):
    # A visit with no stay given is expected to end today at this time.
    default_stay_until: time = time(21, 0)
    # A code with no arrival time is valid until this time on the day.
    code_valid_until: time = time(21, 0)
    # The nightly list of guests still inside past their time.
    rollup_time: time = time(22, 0)
    # Morning handover: anything still open on last night's list closes as a missed exit.
    handover_time: time = time(7, 0)
    # What the guard does when a callback fails twice or a guest has no code. Shown in the app.
    walk_in_policy: str = Field(
        default="Do not admit. Ask the guest to have the resident message Gatelog or call the gate.",
        max_length=280,
    )
    # Abuse limits. Over the SMS budget, messages are held and Gatelog ops are alerted rather
    # than the estate's credit being drained. Over the visit cap, the resident is asked to call.
    daily_sms_budget: int = Field(default=500, ge=10, le=20000)
    max_visits_per_home_per_day: int = Field(default=30, ge=5, le=500)
    # From the contract: SMS included per home per month, and the price of each SMS over it.
    # Unset means the contract has none; the usage view then shows counts only.
    sms_allowance_per_home: int | None = Field(default=None, ge=0, le=1000)
    sms_overage_naira: float | None = Field(default=None, ge=0, le=1000)
    # Until the WhatsApp Business account is approved, residents who prefer WhatsApp get SMS.
    whatsapp_enabled: bool = False
    # The estate shuttle. Off unless the estate runs one; then RIDE works and riders can sign in.
    shuttle_enabled: bool = False
    # Rides one home can book by message in a day; past it, the resident is asked to call the CSO.
    max_rides_per_home_per_day: int = Field(default=20, ge=2, le=200)
