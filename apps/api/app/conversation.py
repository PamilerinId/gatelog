"""Messages from residents, on WhatsApp or SMS.

    announce   "Tunde, today 4pm, for 2 hours"  -> code by return
    stay       "1".."4" or "till Sunday" after we asked how long
    nudge      "1 till 9pm" / "2" after "Is Tunde still with you?"
    NUMBERS    top five emergency numbers
    CANCEL     cancel the last code not yet used
    SOS, HELP  Phase 1: says plainly that no alert went out, and lists numbers to call
    RIDE       book the estate shuttle ("ride to gate", "ride from gate 4pm"), where the estate runs one
    CANCEL RIDE, HOUSE CODE   cancel the open ride; send the home's shuttle house code

Every reply is queued on the outbox in the same transaction as the change it describes.
"""

import logging
import re
from dataclasses import dataclass, field
from uuid import UUID

from datetime import datetime
from datetime import time as dtime
from datetime import timedelta

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from . import abuse, announce, codes, db, directory, messaging, numbers, phones, shuttle, stay, trust, visits
from .estate_settings import EstateSettings
from .models import Conversation, Estate, Home, OverstayNudge, PhoneNumber, Resident, Ride, Visit

log = logging.getLogger("gatelog.conversation")

HELP_TEXT = (
    "To tell the gate about a guest, send their name and when they are coming, for example:\n"
    "Tunde, today 4pm, for 2 hours\n\n"
    "Send NUMBERS for emergency numbers, or CANCEL to cancel your last code."
)
NOT_REGISTERED = "This number is not registered with an estate on Gatelog. Please ask your estate office to add it."
ASK_DATE = "Until what date? For example: Sunday, or 25/10."
ASK_UNTIL = "Until when? For example: till 9pm, overnight, or till Sunday."

_SOS = re.compile(r"^\s*(sos|help|emergency)\b", re.I)
_NUMBERS = re.compile(r"^\s*(numbers?|emergency numbers)\s*$", re.I)
_CANCEL = re.compile(r"^\s*cancel\b", re.I)
_CANCEL_RIDE = re.compile(r"^\s*cancel\s+(?:my\s+|the\s+)?(?:ride|shuttle)\b", re.I)
_HOUSE_CODE = re.compile(r"^\s*(?:house\s*code|home\s*pin|pin)\s*[.!?]?\s*$", re.I)
_NEW_PIN = re.compile(r"^\s*new\s*(?:home\s*)?(?:pin|house\s*code)\s*[.!?]?\s*$", re.I)
_NO = re.compile(r"^\s*no\s*[.!]?\s*$", re.I)
_YES = re.compile(r"^\s*yes\s*[.!]?\s*$", re.I)
NO_SHUTTLE = "Your estate does not run a shuttle on Gatelog."
_LEFT = re.compile(r"^\s*(2|left|gone|already left|he left|she left|they left)\b", re.I)
_STAYING = re.compile(r"^\s*(1|staying|still here|yes)\b[\s,.:-]*", re.I)


@dataclass
class Result:
    estate_id: UUID | None = None
    changed: bool = False  # the gate's expected list changed: push a sync
    replies: list[str] = field(default_factory=list)


class Turn:
    """One inbound message, already matched to a resident and scoped to their estate."""

    def __init__(self, s: Session, estate: Estate, resident: Resident, number: PhoneNumber, channel: str):
        self.s, self.estate, self.resident, self.number, self.channel = s, estate, resident, number, channel
        self.result = Result(estate_id=estate.id)
        self.settings = EstateSettings.model_validate(estate.settings)

    def reply(self, body: str, kind: str = "reply", params: dict | None = None) -> None:
        self.result.replies.append(body)
        # Replies go back on the channel the resident used.
        messaging.queue(self.s, self.estate.id, self.number, self.channel, kind, body, params)

    def _awaiting(self) -> str | None:
        c = self.s.scalars(select(Conversation).where(Conversation.resident_id == self.resident.id)).first()
        return c.awaiting if c else None

    def conversation(self) -> Conversation:
        c = self.s.scalars(select(Conversation).where(Conversation.resident_id == self.resident.id)).first()
        if c is None:
            c = Conversation(estate_id=self.estate.id, resident_id=self.resident.id)
            self.s.add(c)
        return c

    # --- dispatch -----------------------------------------------------------------------

    def handle(self, body: str) -> Result:
        if _SOS.match(body):
            self.sos_not_live()
        elif _NUMBERS.match(body):
            self.reply(directory.as_text(directory.top_five(self.s)), "numbers")
        elif (_YES.match(body) or _NO.match(body)) and self._awaiting() == "number_offer":
            self.reply(numbers.answer(self.s, self.estate, self.resident, self.conversation(), bool(_YES.match(body))), "number_answer")
            self.result.changed = True
        elif _CANCEL_RIDE.match(body):
            self.cancel_ride()
        elif _CANCEL.match(body):
            self.cancel()
        elif _NO.match(body):
            self.dispute()
        elif _NEW_PIN.match(body):
            self.new_home_pin()
        elif _HOUSE_CODE.match(body):
            self.send_house_code()
        elif m := shuttle.RIDE_WORD.match(body):
            self.ride(m.group("rest"))
        else:
            c = self.conversation()
            handled = False
            if c.awaiting == "ride":
                handled = self.on_ride(c, body)
            elif c.awaiting and c.visit_id:
                v = self.s.get(Visit, c.visit_id)
                if v is not None:
                    handled = getattr(self, f"on_{c.awaiting}")(c, v, body)
            if not handled:
                self.announce(body)
        return self.result

    # --- flows --------------------------------------------------------------------------

    def sos_not_live(self) -> None:
        numbers = directory.as_text(directory.top_five(self.s))
        self.reply(
            "Gatelog SOS alerts are not switched on for your estate yet, so this message has NOT alerted anyone.\n"
            f"If you need help now, call:\n{numbers}",
            "sos_not_live",
        )

    def announce(self, body: str) -> None:
        now = visits.local_now(self.estate)
        a = announce.parse(body, now)
        if not a.guest_name:
            self.reply(HELP_TEXT, "help")
            return
        if self._over_visit_cap(now):
            return
        tz = now.tzinfo
        start, end = announce.code_window(a, now, self.settings.code_valid_until)
        base = a.arrival_at(tz) or max(start, now)
        s = a.stay or stay.default_stay(base, self.settings.default_stay_until)
        if s.type == "multi_day":
            end = max(end, s.until)  # a guest staying days can come and go until they leave
        v = Visit(
            estate_id=self.estate.id, home_id=self.resident.home_id, resident_id=self.resident.id, guest_name=a.guest_name,
            window_start=start, window_end=end, source=self.channel, expected_until=s.until, stay_type=s.type,
            stay_minutes=s.minutes, stay_given=s.given, state="expected", created_at=visits.clock.now(),
        )
        code = visits.issue_code(self.s, self.estate, v)
        self.s.add(v)
        self.s.flush()
        valid = visits.until_phrase(end, self.estate)
        self.reply(
            f"Gate code {codes.display(code)} for {v.guest_name}, valid {valid}.",
            "gate_code",
            {"guest": v.guest_name, "code": codes.display(code), "valid_until": valid},
        )
        if self.resident.callback_required:
            self.reply(f"The gate will also call you to confirm before letting {v.guest_name} in.", "callback_notice")
        c = self.conversation()
        if not s.given:
            c.awaiting, c.visit_id = "stay", v.id
            self.reply(stay.QUICK_OPTIONS_TEXT, "stay_question")
        else:
            c.awaiting, c.visit_id = None, None
        self.result.changed = True

    def _over_visit_cap(self, now) -> bool:
        """A forged sender ID can make us issue codes to the real resident's phone. Cap visits
        per home per day so that costs little and cannot bury their inbox."""
        day_start = stay.at(now.date(), dtime(0, 0), now.tzinfo)
        today = self.s.scalar(select(func.count()).select_from(Visit).where(
            Visit.home_id == self.resident.home_id, Visit.source.in_(("whatsapp", "sms")), Visit.created_at >= day_start))
        cap = self.settings.max_visits_per_home_per_day
        if today < cap:
            return False
        if abuse.hit(self.s, abuse.Limit("visit-cap-notice", 1, timedelta(days=1)), str(self.resident.home_id)):
            self.reply(f"Your home has announced {cap} guests today, the daily limit. For more guests today, please call the gate.", "visit_cap")
        return True

    def _stay_base(self, v: Visit):
        now = visits.local_now(self.estate)
        return now if v.state != "expected" else max(now, v.window_start.astimezone(now.tzinfo))

    def _apply_stay(self, c: Conversation, v: Visit, s: stay.Stay) -> None:
        v.expected_until, v.stay_type, v.stay_given = s.until, s.type, True
        v.stay_minutes = s.minutes if v.state == "expected" else None
        c.awaiting, c.visit_id = None, None
        if s.minutes and v.state == "expected":
            hours = s.minutes // 60
            length = "about an hour" if s.minutes <= 60 else f"about {hours} hours"
            self.reply(f"Noted. We expect {v.guest_name} to stay {length} from when they arrive.", "stay_noted")
        else:
            self.reply(f"Noted. We expect {v.guest_name} to leave {visits.until_phrase(s.until, self.estate)}.", "stay_noted")
        self.result.changed = True

    def on_stay(self, c: Conversation, v: Visit, body: str) -> bool:
        base = self._stay_base(v)
        choice = body.strip().rstrip(".")
        if choice == "4":
            c.awaiting = "stay_date"
            self.reply(ASK_DATE, "stay_question")
            return True
        s = stay.quick_option(choice, base) or stay.parse_stay(body, base)
        if s is None:
            return False  # not an answer: read it as a new announcement instead
        self._apply_stay(c, v, s)
        return True

    def on_stay_date(self, c: Conversation, v: Visit, body: str) -> bool:
        base = self._stay_base(v)
        s = stay.parse_stay(body, base)
        if s is None:
            d = stay.parse_day(body, base.date())
            s = stay.until_date(d, base) if d and d > base.date() else None
        if s is None:
            if announce.guest_name(body) and not stay.parse_day(body, base.date()):
                return False
            self.reply(ASK_DATE, "stay_question")
            return True
        self._apply_stay(c, v, s)
        return True

    def _open_nudge(self, v: Visit) -> OverstayNudge | None:
        return self.s.scalars(select(OverstayNudge).where(OverstayNudge.visit_id == v.id).order_by(OverstayNudge.sent_at.desc())).first()

    def on_nudge(self, c: Conversation, v: Visit, body: str) -> bool:
        nudge = self._open_nudge(v)
        if _LEFT.match(body):
            if v.state in visits.OPEN_STATES:
                visits.close_by_resident(self.s, self.estate, v)
            if nudge:
                nudge.reply, nudge.replied_at = "left", visits.clock.now()
            c.awaiting, c.visit_id = None, None
            self.reply(f"Thanks. We have marked {v.guest_name} as gone.", "nudge_noted")
            self.result.changed = True
            return True
        m = _STAYING.match(body)
        if not m:
            return False
        rest = body[m.end():]
        if nudge:
            nudge.reply, nudge.replied_at = "staying", visits.clock.now()
        if not self._extend_from(c, v, rest, nudge):
            c.awaiting = "nudge_until"
            self.reply(ASK_UNTIL, "nudge_question")
        return True

    def on_nudge_until(self, c: Conversation, v: Visit, body: str) -> bool:
        if _LEFT.match(body):
            return self.on_nudge(c, v, body)
        if self._extend_from(c, v, body, self._open_nudge(v)):
            return True
        if announce.guest_name(body):
            return False
        self.reply(ASK_UNTIL, "nudge_question")
        return True

    def _extend_from(self, c: Conversation, v: Visit, body: str, nudge: OverstayNudge | None) -> bool:
        now = visits.local_now(self.estate)
        s = stay.parse_stay(body, now)
        if s is None:
            d = stay.parse_day(body, now.date())
            s = stay.until_date(d, now) if d and d > now.date() else None
        if s is None:
            return False
        visits.extend(v, s.until)
        if nudge:
            nudge.new_until = s.until
        c.awaiting, c.visit_id = None, None
        self.reply(f"Noted. {v.guest_name} is expected to leave {visits.until_phrase(s.until, self.estate)}.", "nudge_noted")
        self.result.changed = True
        return True

    def cancel(self) -> None:
        v = self.s.scalars(
            select(Visit)
            .where(Visit.resident_id == self.resident.id, Visit.state == "expected", Visit.code_issued.is_(True))
            .order_by(Visit.created_at.desc())
        ).first()
        if v is None:
            self.reply("You have no unused gate codes to cancel.", "cancel")
            return
        code = visits.code_for(self.estate, v)
        v.state = "cancelled"
        self.reply(f"Cancelled. Code {codes.display(code)} for {v.guest_name} no longer works.", "cancel")
        self.result.changed = True


    # --- the estate shuttle ---------------------------------------------------------------

    def ride(self, rest: str) -> None:
        if not shuttle.enabled(self.estate):
            self.reply(NO_SHUTTLE, "ride_question")
            return
        now = visits.local_now(self.estate)
        ask = shuttle.parse_request(rest, now, self.s)
        if ask.unknown_place:
            self.reply(f"The shuttle does not know \"{ask.unknown_place}\". Send RIDE TO and one of: {', '.join(shuttle.place_names(self.s))}.", "ride_question")
            return
        when = ask.when or now
        home = self.s.get(Home, self.resident.home_id)
        here = shuttle.Stop("home", home.id, home.address)
        if ask.to:
            self._book(here, ask.to, when)
        elif ask.from_:
            self._book(ask.from_, here, when)
        elif ask.home:
            gate = shuttle.main_gate(self.s)
            self._book(shuttle.Stop("gate", gate.id, gate.name), here, when)
        else:
            c = self.conversation()
            c.awaiting, c.visit_id, c.pending = "ride", None, {"when": when.isoformat()}
            gate = shuttle.main_gate(self.s)
            others = [n for n in shuttle.place_names(self.s) if n != gate.name]
            more = f"\nOr send RIDE TO and a place: {', '.join(others)}." if others else ""
            self.reply(f"Where should the shuttle take you?\n1 From your home to {gate.name}\n2 From {gate.name} to your home{more}", "ride_question")

    def on_ride(self, c: Conversation, body: str) -> bool:
        choice = body.strip().rstrip(".")
        if choice not in ("1", "2"):
            c.awaiting, c.pending = None, None
            return False  # not an answer: read it as anything else
        when =datetime.fromisoformat((c.pending or {}).get("when")) if (c.pending or {}).get("when") else visits.local_now(self.estate)
        c.awaiting, c.pending = None, None
        home = self.s.get(Home, self.resident.home_id)
        here = shuttle.Stop("home", home.id, home.address)
        gate = shuttle.main_gate(self.s)
        there = shuttle.Stop("gate", gate.id, gate.name)
        self._book(*((here, there) if choice == "1" else (there, here)), when)
        return True

    def _book(self, pickup: "shuttle.Stop", dropoff: "shuttle.Stop", when) -> None:
        now = visits.local_now(self.estate)
        home_id = self.resident.home_id
        settings = EstateSettings.model_validate(self.estate.settings)
        if len(shuttle.open_rides_for_home(self.s, home_id)) >= shuttle.MAX_OPEN_RIDES_PER_HOME:
            self.reply("Your home already has 3 rides waiting. Send CANCEL RIDE to cancel one first.", "ride_question")
            return
        day_start = stay.at(now.date(), dtime(0, 0), now.tzinfo)
        if shuttle.booked_today(self.s, home_id, day_start) >= settings.max_rides_per_home_per_day:
            self.reply("Your home has booked the most rides allowed by message today. Please call the CSO for another.", "ride_question")
            return
        home = self.s.get(Home, home_id)
        try:
            ride = shuttle.book(self.s, self.estate, kind="resident", source=self.channel, home=home, resident=self.resident,
                                pickup=pickup, dropoff=dropoff, wanted_at=when)
        except shuttle.RideError as e:
            self.reply(str(e)[0].upper() + str(e)[1:] + ".", "ride_question")
            return
        local = when.astimezone(now.tzinfo)
        at = "now" if when <= now + timedelta(minutes=5) else f"{visits.day_phrase(local.date(), now.date())} {visits.clock_12h(local)}"
        self.reply(
            f"Shuttle booked: {ride.pickup_label} to {ride.dropoff_label}, {at}. We will message you when a rider is on the way. "
            "Send CANCEL RIDE to cancel.",
            "ride_booked",
        )
        self.result.changed = True

    def cancel_ride(self) -> None:
        if not shuttle.enabled(self.estate):
            self.reply(NO_SHUTTLE, "ride_cancelled")
            return
        waiting = [r for r in shuttle.open_rides_for_home(self.s, self.resident.home_id) if r.state in ("requested", "accepted")]
        if not waiting:
            self.reply("You have no shuttle ride waiting to cancel.", "ride_cancelled")
            return
        ride: Ride = max(waiting, key=lambda r: r.created_at)
        ride.state, ride.closed_at = "cancelled", visits.clock.now()
        self.reply(f"Cancelled your ride from {ride.pickup_label} to {ride.dropoff_label}.", "ride_cancelled")
        self.result.changed = True

    # --- the home PIN and the second pair of eyes ------------------------------------------

    def _pin_text(self, code: str) -> str:
        rider = " or to the shuttle rider" if shuttle.enabled(self.estate) else ""
        return f"Your home PIN is {code}. Give it when you call the gate about a guest{rider}. Never share it outside your home."

    def send_house_code(self) -> None:
        """The home PIN, to the number that asked. Safe against a forged sender: the reply goes
        to the real number, not to whoever forged it."""
        if not abuse.hit(self.s, abuse.Limit("house-code", 3, timedelta(days=1)), str(self.resident.home_id)):
            self.reply("We have already sent your home PIN 3 times today. Please ask the estate office.", "house_code")
            return
        home = self.s.get(Home, self.resident.home_id)
        first = home.house_code_enc is None
        code = shuttle.house_code(home)
        self.result.changed = first  # a new PIN's hash must reach the gate phones
        self.reply(self._pin_text(code), "house_code")

    def new_home_pin(self) -> None:
        """A new random PIN, sent to every registered number of the home: nobody chooses it, so a
        forged request learns nothing, and the whole household sees that it changed."""
        if not abuse.hit(self.s, abuse.Limit("new-pin", 2, timedelta(days=1)), str(self.resident.home_id)):
            self.reply("Your home PIN has already been changed twice today. Please ask the estate office.", "house_code")
            return
        home = self.s.get(Home, self.resident.home_id)
        code = shuttle.set_house_code(home)
        text_ = f"{self.resident.name} asked for a new home PIN. " + self._pin_text(code) + " The old PIN no longer works."
        for n in trust._home_numbers(self.s, home.id):
            messaging.queue(self.s, self.estate.id, n, "sms", "house_code", text_)
        self.result.changed = True

    def dispute(self) -> None:
        e = trust.dispute(self.s, self.estate, self.resident)
        if e is None:
            self.reply("There is no unchecked guest for your home in the last day to answer NO to.", "dispute_noted")
            return
        self.reply(f"Thank you. The estate's security has been told that {e.guest_name} was not expected.", "dispute_noted")
        self.result.changed = True


def _match(s: Session, e164: str) -> list[tuple[UUID, UUID, UUID]]:
    rows = s.execute(text("SELECT estate_id, resident_id, home_id FROM gatelog_lookup_phone(:i) WHERE resident_id IS NOT NULL"), {"i": phones.blind_index(e164)})
    return [(r.estate_id, r.resident_id, r.home_id) for r in rows]


def _pick(s: Session, matches: list[tuple[UUID, UUID, UUID]], body: str) -> tuple[UUID, UUID] | None:
    """A number registered to more than one home: the message must start with the house."""
    if len(matches) == 1:
        return matches[0][0], matches[0][1]
    first = body.strip().split(maxsplit=1)[0].strip(",:").lower() if body.strip() else ""
    for estate_id, resident_id, home_id in matches:
        db.rescope(s, estate_id)
        home = s.get(Home, home_id)
        if home and home.label.lower() == first:
            return estate_id, resident_id
    return None


MAX_BODY = 1000


def handle(channel: str, from_raw: str, body: str, message_id: str | None = None) -> Result:
    try:
        e164 = phones.normalise(from_raw)
    except phones.InvalidPhone:
        return Result()
    body = body[:MAX_BODY]
    idx = phones.blind_index(e164)
    with db.session() as s:
        if not abuse.first_time(s, channel, message_id):
            return Result()  # a retried or replayed webhook
        # Over the limit: drop silently. Answering would let a flood generate outbound traffic.
        if not (abuse.hit(s, abuse.INBOUND_BURST, idx) and abuse.hit(s, abuse.INBOUND_DAILY, idx)):
            return Result()
        matches = _match(s, e164)
        if not matches:
            log.info("inbound from unregistered number=%s channel=%s", phones.mask(e164), channel)
            # WhatsApp replies are free and reach only the real sender; still, once a day each and
            # a global ceiling. SMS replies to unknown numbers cost money: never.
            if channel == "whatsapp" and abuse.hit(s, abuse.UNKNOWN_REPLY, idx) and abuse.hit(s, abuse.UNKNOWN_REPLY_GLOBAL, "all"):
                messaging.sender().send(messaging.Outgoing(e164, channel, "not_registered", NOT_REGISTERED, None))
            return Result()
        picked = _pick(s, matches, body)
        if picked is None:
            estate_id, resident_id = matches[0][0], matches[0][1]
            db.rescope(s, estate_id)
            number = s.scalars(select(PhoneNumber).where(PhoneNumber.e164_index == phones.blind_index(e164), PhoneNumber.resident_id == resident_id)).one()
            messaging.queue(s, estate_id, number, channel, "which_home", "This number is registered to more than one home. Please start your message with the house number, for example: 14B Tunde, today 4pm.")
            return Result(estate_id=estate_id)
        estate_id, resident_id = picked
        db.rescope(s, estate_id)
        estate = s.get(Estate, estate_id)
        resident = s.get(Resident, resident_id)
        number = s.scalars(select(PhoneNumber).where(PhoneNumber.e164_index == phones.blind_index(e164), PhoneNumber.resident_id == resident_id)).one()
        messaging.log_inbound(s, estate_id, number, channel, "inbound")
        if len(matches) > 1:  # strip the house number we matched on
            body = body.strip().split(maxsplit=1)[1] if len(body.strip().split(maxsplit=1)) > 1 else ""
        return Turn(s, estate, resident, number, channel).handle(body)
