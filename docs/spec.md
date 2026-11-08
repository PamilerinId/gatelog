# Gatelog Product Spec v1.0

Oct 11, 2026 · @Pamilerin Idowu. Revised 4 November 2026: dues ledger in Phase 1, one Phase 1 row, the CSO role on the gate phone, guard PIN and selfie at shift start. Revised 8 November 2026: estate shuttle and the estate map; then the design handoff (`docs/gatelog-handoff/`) merged in: trust levels and one home PIN, satellite map (Google in production), voice clips for visitor names (uploaded encrypted, deleted after 7 days), the gate phone UX rules in `CLAUDE.md`.

This file is the working copy the code is built from. Change it in the same commit as the code that changes the behaviour.

## Summary

Gatelog v1.0 moves from gate access to estate safety: the core visitor flow stays, and five features join it.

| Feature | What it does | Ships in |
| --- | --- | --- |
| Core gate flow | Resident announces a guest, gets a six-digit signed code, guard verifies offline, entry is logged | Phase 1 |
| Visit length, exits, nightly rollup | Resident says how long the guest stays, guard confirms exit, the CSO gets a nightly list of guests still inside past their time | Phase 1 |
| Call-the-gate verification | Residents who prefer to phone (mostly elderly) announce guests by call; the guard confirms by calling back the registered number | Phase 1 |
| Emergency directory | Estate and state emergency numbers, tap to call, available offline | Phase 1 |
| Dues and levy ledger | Who has paid, reminders with a payment link into the association's own account; Gatelog never holds funds | Phase 1 |
| SOS alert | One button (or a missed call) alerts security, estate officials, neighbours and relatives, with escalation until someone acknowledges | Phase 2, after drills |

Three calls shape the spec. **Callback is the trust anchor for phone announcements**, because an outbound call to a number on file cannot be spoofed and an inbound caller ID can. **SOS ships last and only after it passes drills**, because a panic button that fails once is worse than no button. **Gatelog notifies, it does not respond**: the estate's guards and the resident's people respond, and every surface says so.

Hard blocker, unchanged: the written agreement with Deborah Ojo (role, equity, IP) is signed before the first paying estate.

## Users and surfaces

Residents never install an app: they use WhatsApp, SMS or a phone call. Only guards and estate staff run Gatelog software, on a Flutter Android app that works offline, plus a web dashboard.

| User | Surface | What they do |
| --- | --- | --- |
| Resident (smartphone) | WhatsApp, plus an optional home-screen web page for SOS and the directory | Announce guests, receive codes and arrival notices, pay dues from a link, raise SOS |
| Resident (prefers calls, often elderly) | Voice call to the gate line; missed call to the SOS line | Announce guests by phone, raise SOS without data or an app |
| Landlord | WhatsApp or SMS, dashboard view of their homes later | Add and remove occupants of their homes |
| Designated contact (neighbour, relative, possibly abroad) | SMS and WhatsApp | Accept the role once, then receive SOS alerts and acknowledge |
| Guard | Gate phone (Gatelog-leased Android, estate's own security SIM), guard view | Verify codes offline, log entries and exits, take and confirm phone announcements, receive and acknowledge SOS |
| CSO (chief security officer, the estate's security head) | Any Gatelog gate phone, signed in with their own PIN and selfie, which opens the CSO view; plus SMS, voice escalation and the web dashboard | Everything a guard can do, plus what needs a decision: overstays, walk-in calls, the night list, shifts and handovers, SOS response. No separate CSO phone is needed |
| Shuttle rider (estates with a shuttle) | Gatelog phone, rider view, signed in with their own PIN and selfie | Take rides from the queue, record who rode (card or house code), record flagged-down trips; position shown on the estate map during the shift |
| Estate admin (facility manager, secretary) | Web dashboard | Manage the address register, residents, guards, contacts and the directory |
| Treasurer | Web dashboard | Dues ledger, reminders, messaging usage |
| Committee (chairman, ExCo) | Web dashboard, read-mostly | See entries, SOS history, response times, false-alarm rate, dues position |
| Association (umbrella body or facility-management company) | Web dashboard | See across its estates, set shared defaults |
| Gatelog ops (PI Technologies) | Platform admin | Provision estates, curate state-level directory numbers, support |

Design rule: the elderly resident on a feature phone is the hardest user, so every resident feature must work for them by call or SMS. If it only works on a smartphone, it is not done.

## Core gate flow

The core flow is unchanged from the earlier spec: announce, code, verify offline, log, notify. It is restated here because the new features hang off it.

1. **Announce.** Resident messages Gatelog on WhatsApp (or SMS while WABA approval is pending): guest name, day, rough time, and how long they will stay.
2. **Issue.** Server derives a six-digit code with HMAC over home ID, visit ID and validity window, keyed per estate. Reply: "Gate code 482 917, valid today until 6pm."
3. **Verify.** Guard enters the code on the guard app. The device holds the estate key and the address register, so it verifies with no network and shows the guest name and home.
4. **Log.** Admit or turn away writes an entry with a client-generated ID. Offline entries queue and sync idempotently (unique on client ID) when the network returns.
5. **Notify.** Resident gets "Tunde is in. Main Gate, 16:06."

Addresses follow the four-level estate model (estate, block or zone, street or court, home), so a log line reads "14B Adeniyi Close, Block C", never a city street address.

Every entry carries a `method` field: `code`, `phone_announced`, `callback_confirmed`, `walk_in_admitted` or `refused`. The committee report splits by method, so the estate can see how much traffic still bypasses codes.

## Visit length, exits and the nightly rollup

Every visit now has an expected end, every exit is confirmed by the guard, and each night the CSO gets a short list of guests still inside past their time. The list is only useful if exits are captured, so exit capture is a tracked number from day one.

**Visit length, set at announcement.**

- The resident says how long: "for 2 hours", "till evening", "overnight", "staying till Sunday". Gatelog reads it into an `expected_until` time.
- If they don't say, WhatsApp replies with four quick options: about an hour, a few hours, overnight, longer (pick a date). SMS gets the same as a numbered reply.
- Call-preferring residents give it during the guard's callback; the guard picks one of the same four options.
- No answer means today until 9pm (estate-configurable).
- The code's validity window (when the guest may enter) and the stay window (when they are expected to leave) are separate fields.

**Exit at the gate.**

- Guard confirms exit by re-entering the guest's code or tapping the name in a **Leaving** list, sorted by home. One action, works offline, syncs like entries.
- Resident gets "Tunde has left. Main Gate, 18:40." On by default for residents whose contact preference is call or SMS; optional for others.
- An exit with no matching entry (guest came in before Gatelog, or the entry was missed) is still logged and flagged for the admin.

**Overstay nudge, then the rollup.**

1. When a guest passes `expected_until`, the resident gets: "Is Tunde still with you? Reply 1 staying (until when?), 2 already left." Reply 2 closes the visit as `resident_confirmed`; reply 1 extends it.
2. At the estate's rollup time (default 10pm), the CSO gets the list of guests still open past their window and not extended, grouped by home, each with entry time and the resident's last reply.
3. The list shows in the CSO view on the gate phone and goes to the CSO by WhatsApp or SMS. The CSO or a guard closes items as they are checked.
4. Anything still open at the next morning's handover is closed as `rollup_closed` and counted as a missed exit.

The nudge runs before the rollup so the CSO only sees what residents could not or did not resolve. The rollup lists guest name, home and times only, nothing else about the resident.

## Gates, vehicles, events and workers

Added after the first target estate's minutes (a three-area neighbourhood association with several gates, one shared with a neighbouring estate, that has just voted for "No Call, No Entry", vehicle checks and written notice of events).

**Several gates per estate.**

- An estate has any number of named gates; every entry, exit, callback and SOS acknowledgement records which gate.
- Each gate has its own device and on-duty guard; the code verifies at any gate, so a guest can leave by a different one.
- Zones in the address model can match how the association is actually organised (for example, one zone per street area it covers).

**Shared gates.** Where one gate serves two estates, the gate belongs to the estate whose guards staff it. Residents of the other estate are set up as a linked estate: their codes verify at that gate and their entries appear in both dashboards, each seeing only its own homes. Until both estates are on Gatelog, the guard logs the other estate's traffic as walk-ins with a callback.

**Vehicles.** Every entry and exit has an optional plate number, typed by the guard (camera capture later). Residents can register their own vehicles so the guard sees a match. The committee can search the log by plate. Plates are stored as entered and never used for anything except the estate's own log.

**Event passes (Phase 1.5).**

1. Resident submits an event: date, time window, expected guest count, optional guest list, parking needs.
2. Exco (or its delegate) approves or declines in the dashboard, which replaces the written letter. Approval notifies the CSO and the gate.
3. Guests get one group code for the window, or individual codes if a list was given. The guard sees a counter: "Adeyemi 50th, 34 of 60 in."
4. Rollup that night covers the event like any visit.

**Recurring worker passes (Phase 1.5, moved up from Phase 2).** Cooks, drivers, cleaners and artisans on construction or renovation jobs get a pass with fixed days, hours and an end date, linked to the home or the building site. Every entry and exit is still logged. Construction sites get a site record so the estate can see who is working where, useful if it introduces a development levy.

## Dues and levy ledger

The Exco sees who has paid, residents get reminders and a way to pay, and the money goes straight to the association. Gatelog never holds funds and never decides who gets in.

- **Ledger:** each home has levies and dues raised against it, payments recorded, and a balance. Import from the Exco's existing list (CSV or Excel); the treasurer marks payments manually or a payment-link confirmation marks them.
- **Who owes:** each home records whether the levy is owed by the landlord or the occupant, because the association decides that, not Gatelog.
- **Reminders:** WhatsApp or SMS, sent in the Exco's name, with a payment link that pays into the association's own account (Paystack or Flutterwave split or subaccount to be confirmed).
- **Exco view:** paid, outstanding and ageing per home and per zone; export for meetings and enforcement exercises.
- **Privacy:** visible to the treasurer and Exco only. Nothing about dues appears on the gate phone, in guest codes, in the nightly rollup or in SOS.

**Not built:** automatic or guard-visible restriction of entry, guest codes, worker passes or SOS based on dues. Enforcement stays with the Exco, offline. Revisit only after counsel advises on self-help and tenant-versus-landlord liability.

## The gate phone: guard and CSO

One app on every Gatelog gate phone. Who signs in decides what it shows.

**Shift start: PIN and selfie.** Each guard and the CSO has a permanent personal PIN. Starting a shift takes the PIN plus a selfie, and every action until shift end is logged against that person and that shift. The PIN identifies; the selfie is an audit record of who was actually holding the phone, for the Exco to check after a dispute. It is not face recognition and is never compared automatically. Selfies are stored encrypted, viewable only by the estate admin and the CSO (each viewing is audited), and deleted after 30 days. Guards consent in writing at onboarding (it is personal data under the NDPA); the admin records that consent before the guard's first shift. Shift end is explicit (hand over to the next person, or end with nobody taking over), or automatic after 14 hours.

- A guard sets their own PIN at their first shift; the admin never knows it. The admin can reset a forgotten PIN, and the next shift sets a new one.
- The PIN works offline: the phone holds a salted, slow hash for each guard. Five wrong tries lock that guard out on that phone for 5 minutes.
- If the camera fails, the shift still starts and is marked "no selfie", so a broken camera never stops a gate.

**Guard view.** The keypad is the screen. Under it, two buttons: **No code** (find the home, call a registered number, then let the guest in now or expect them later; if nobody confirms, turn them away) and **Leaving** (tap the person, or re-enter their code). A small menu holds emergency numbers and End shift. Nothing else: no counts, no rota, no night list.

**CSO view.** Everything in the guard view, plus:

- **Needs you:** guests past their time, walk-ins waiting for a decision, refusals, a gate phone that has stopped syncing, tonight's list.
- **On duty:** each gate, who is on shift, since when, and when its phone last synced.
- **People:** everyone expected and inside across all gates; add a guest when a resident rings the CSO directly (with a callback, as at the gate).
- **Shifts:** today's shifts and handovers.

The CSO view needs data for the whole estate, so it reads it live and shows the time it was last refreshed; with no network it shows the last copy and says so.

## Estate shuttle (optional per estate)

Added 8 November 2026: the pilot estate has bought electric motorcycles to carry people and parcels inside the estate. Estates without a shuttle never see any of this; it is off until the admin turns it on.

**What it carries.** Three kinds of ride, all inside the estate:

- **Resident:** a resident (often elderly, without a car) from their home to a gate or an estate place (clubhouse, mosque, market), or back.
- **Delivery:** a parcel collected from a delivery rider at the gate and taken to the home, so delivery riders do not need to come in.
- **Guest:** a guest who arrived on foot or by taxi, from the gate to the home they are visiting, after the gate has let them in as usual.

**Free to residents.** Rides are paid for by the levy, not per trip. Gatelog records every ride against the home it served, so the Exco can see use per home, per zone and per rider. No fare is charged and Gatelog holds no money.

**Who rides and on what.** Riders are estate staff, listed with the guards with the role `rider`, on a Gatelog phone, with the same PIN, selfie, consent and shift rules as guards. At shift start the rider picks the motorcycle they are on. The estate's motorcycles are listed in the dashboard (label and plate). A rider phone is paired to the gate the shuttle runs from.

**Booking. Four ways in, one queue:**

1. **WhatsApp or SMS:** the resident sends RIDE ("ride to gate", "ride to clubhouse at 4pm", "ride from gate"). With no direction given, Gatelog asks: 1 from your home to the gate, 2 from the gate to your home. The resident gets "Shuttle booked" by return and one message when a rider takes it. CANCEL RIDE cancels it.
2. **At the gate:** the guard books a delivery or a guest run to a home from the gate phone.
3. **Flagged down:** the rider records the trip on the spot.
4. **Through the CSO:** a resident who prefers to call rings the CSO, who books it from the CSO view.

Riders see the queue on their phone, oldest and soonest first, and take a ride with one tap. The first rider to take a ride gets it; a second sees "taken by Musa". A rider can hand a ride back to the queue.

**Who rode: card or house code.** At pickup (or at drop-off for a delivery) the rider records who it was for:

- **Estate card:** each resident can have an NFC tap card, tapped on the rider's phone. It works offline and suits elderly residents. Cards are issued on a gate phone in the CSO view (tap the card, pick the resident) and revoked in the dashboard. The card's ID is not secret, so a card identifies, it does not authorise payment.
- **Home PIN:** the home's 4-digit PIN, the same one used for phone calls to the gate (see trust levels). Gatelog sends it to a registered number on request (HOUSE CODE); the household or the admin can change it. The phone checks it offline against a slow hash, like a guard PIN.
- **Guard or rider:** for a guest or delivery run booked at the gate, or when the resident has neither, the rider records it as vouched by the guard or by themselves.

**Live position.** A rider phone reports its position every 15 seconds while the rider's shift is open, and never outside a shift. Positions show on the estate map and are kept 7 days (for disputes and incidents), then deleted. Riders consent to this with the selfie consent at onboarding.

**Later: bills.** The card and the house code identify a home without a phone. When estates take bills through Gatelog (dues receipts, utility tokens), the same card and code are how a resident at the gate or on the shuttle is matched to their home's account. Nothing about dues shows on the rider phone.

## Estate map

The dashboard is drawn over a live map of the estate, so the Exco and the CSO see the estate as it is right now, not as tables.

- **Bound to the estate.** The admin draws the estate's boundary once and drops pins for each gate and estate place. The map is locked to that boundary: it cannot be panned or zoomed out past the estate.
- **Map data.** Satellite imagery, drawn with MapLibre, as in the design handoff. Production uses Google satellite imagery with the view locked to the estate (decided 8 November 2026); development uses Esri World Imagery, which is for prototypes only. The provider sits behind one switch, and the imagery's attribution is always shown.
- **What is on it.** Each gate (who is on duty, when its phone last synced, quiet phones in red), the shuttles moving (rider, motorcycle, current ride), rides waiting for pickup (and for how long), estate places. SOS alerts join in Phase 2.
- **Day and night.** The map and the dashboard switch to a night style between sunset and sunrise at the estate's location, and back at sunrise.
- **Live.** The overview refreshes every 10 seconds. Other pages keep the map as a still background behind their tables, so tables stay readable.
- **Who sees positions.** Rider positions are visible to the admin, the committee and the security head; the treasurer sees the map without them.

## Shifts, tenants and edge cases

Decided 3 November 2026, revised 4 November.

**Handover.** Ending a shift asks who is taking over. The handover record holds who was still inside, what was still unsynced, and the night list if open. The CSO sees every handover.

**Tenants.** The landlord adds occupants for a home, either blanket ("any number I list") or by name and phone. Each added occupant gets an SMS invite and is active once they reply YES, which also confirms the number works. The landlord or the Exco can remove an occupant; removal is audited.

**No number or changed number.** Not solved in v1.0. A resident with no registered number cannot announce or be called back; the guard falls back to the walk-in rule. The Exco admin can change a home's numbers in the dashboard, which is audited and voids pending callbacks to the old number.

**Walk-ins and disputes.** When no resident can be reached, Gatelog records the situation and the decision of the CSO or guard on duty: admitted or refused, by whom, the reason given, and the time. Gatelog never decides. These records appear in the Exco view.

**Unstaffed and pedestrian gates.** Out of scope: a gate with no phone and no guard records nothing. The exit-capture kill criterion counts only staffed gates, and the Exco view says which gates are unstaffed so the numbers are read honestly.

## Association dashboard (several estates)

One organisation above several estates: an umbrella residents' association, a CDA, or a facility-management company that runs several estates. It sees across its estates and sets shared defaults; each estate keeps running its own gates.

**What the association sees.**

- Every member estate side by side: entries, exit capture, overstays, callbacks, walk-in decisions, SOS response times and drill results, dues position, messaging usage.
- Drill into any one estate with the same views its own Exco has.
- One combined export for meetings.

**What the association controls.**

- Adding and removing its estates, and their Exco admins.
- Shared defaults each estate can adopt: emergency directory entries, SOS ladder timings, rollup time, message wording, walk-in policy text.
- Consolidated billing for all its estates, if it is the one paying.

**What it does not do.** It does not operate any estate's gate, approve its events or see guard selfies. An estate's Exco remains in charge of its own residents, register and dues. An estate joins an association only with its Exco's approval, and leaving keeps the estate's data with the estate.

**Build.** Data model and permissions in Phase 1, because retrofitting a level above the tenant is expensive. The dashboard itself ships when the first customer runs two or more estates (about 1 to 2 build-weeks).

## Call-the-gate verification

Residents who prefer to phone keep phoning; Gatelog makes the call auditable instead of trying to stop it. The guard confirms by calling back the resident's registered number, because inbound caller ID can be spoofed and an outbound call to a number on file cannot.

**Why callback, not caller ID.** The guard app shows who is calling when the number is registered, but caller ID is spoofable. Treating an inbound call as proof would open the cheapest attack on the estate: ring the gate pretending to be Mama in 14B. So an inbound call is a hint; the callback is the proof.

**Flow A: resident calls ahead (Phase 1).**

1. Resident calls the gate line (the estate's existing security line, in the gate phone). Guard answers as today.
2. Guard taps **No code**, which also covers announcements, and searches the register by home or surname. The match shows the resident's registered number(s).
3. Guard taps **Call**. The app dials the registered number from the gate SIM. Resident confirms guest name.
4. Guard taps **Confirmed**, then **Coming later**. Gatelog creates an expected-visit record with method `callback_confirmed`, valid for the window the resident gave (default: rest of the day).
5. Guest arrives, guard finds the home, the guest shows as already confirmed, guard admits, entry logged. Resident gets the arrival notice by SMS (call-preferring residents default to SMS, not WhatsApp).

**Flow B: guest arrives with no code (Phase 1).** Same callback from step 3, then **They are here: let them in**. This replaces the unlogged "let me call oga" that happens today.

**Flow C: gate line with automatic lookup (Phase 2).** Residents call a Gatelog virtual number instead of the guard's SIM. A voice provider looks up the caller ID, plays "Press 1 to tell the gate a guest is coming", records the guest's name as a short clip, and pushes a card to the guard app: "Mrs Adeyemi, 14B Adeniyi Close, expects a guest. Call back to confirm." The callback rule still holds; the virtual number only removes the guard's search step and works when the guard's line is busy.

**Rules.**

- One home can register up to 3 numbers (resident, spouse, live-in carer). Only these count for callback.
- Callback confirmation is logged with time, number dialled (masked to last 4 digits in logs) and guard ID. No call audio is recorded in Phase 1.
- A resident can set **Callback required for all guests** (useful for a parent whose children worry about scams at the gate).
- If the callback fails (no answer twice), the guest is not admitted on phone authority; the guard follows the estate's walk-in policy, which may mean asking the CSO, and the decision is logged.

**Calls from unregistered numbers: trust levels, not a ban.** Merged from the design handoff, 8 November 2026. Estates already admit guests on a call from any number if the caller describes themselves well enough. Gatelog keeps that working and records how well each entry was verified.

| Trust level | How it is reached | Recorded as |
| --- | --- | --- |
| Verified | Guest gives a code, or the guard calls back a registered number for the home and the resident confirms | `verified` |
| PIN-verified | Caller from any number says the home's 4-digit home PIN | `pin_verified` |
| Description only | The CSO or supervisor decides on the caller's description, as today (`walk_in_admitted`) | `unverified`, with who admitted and the reason given |

- **The home is told about every description-only entry.** All registered numbers for the home get an SMS at once: "A guest for 14B was admitted at Atiba gate, 16:06, after a call from 0803•••1234. Not you? Reply NO." A NO alerts the CSO immediately and is logged against the entry. These messages are never billed against the SMS allowance.
- **One home PIN** (decided 8 November 2026): the same 4 digits for phone calls to the gate and for the estate shuttle (it replaces the shuttle's separate house code). Set at onboarding, changeable by the household or the Exco, stored only as a slow hash, never shown to guards (the gate phone checks it offline), 3 wrong tries per call, and the home is alerted after any wrong try. Elderly residents get a printed card. Guard PINs stay 6 digits: a stolen gate phone holds their hashes, so the extra digits matter.
- **New numbers.** When a resident calls from a new number and confirms on callback, the guard can offer to register it; an existing number for the home must reply YES first.
- **Exco view.** Share of phone-announced entries at each trust level, by gate and by guard, plus every NO reply.
- **Kill criteria (8 weeks into a pilot).** More than 20% of phone-announced entries still description-only → push PIN adoption with the Exco. Any confirmed NO reply that shows real abuse → propose to the Exco that description-only entries need the CSO's approval at every gate.

## SOS alert

One action raises an alert that rings the gate, then widens to the CSO, estate officials, neighbours and relatives until a named person acknowledges it. It is designed for the elderly resident and available to every resident.

**Three ways to raise it, all without the Gatelog app.**

| Trigger | Who it serves | How it works | Needs data? |
| --- | --- | --- | --- |
| Missed call to the estate SOS number | Feature phones, elderly, anyone panicking | Caller ID matched to a registered number; the call is rejected unanswered so it costs nothing. Unknown numbers raise an "unverified SOS" to the gate only | No |
| Big button on the home-screen web page | Smartphone users | Hold 2 seconds to send; a 5-second countdown allows cancel; then sent with optional category (medical, security, fire) | Yes, falls back to SMS |
| Send "SOS" or "HELP" to Gatelog on WhatsApp | Residents already in the WhatsApp thread | Keyword raises the alert; replies continue in the thread | Yes |

A missed call is the right primary trigger for the elderly: "flashing" is a habit Nigerians already have, it works on any phone, it is never answered so it costs nothing, and it needs no menu (some networks require a small airtime balance to place a call; confirm per network in the pilot). Category is optional everywhere; an alert with no category is treated as the most serious.

**Who gets alerted, in what order.** A ladder of 3 tiers that stops on the first acknowledgement: the gate and the resident's own contacts at once; the CSO if the gate has not acknowledged; estate officials last. (The diagram from the source document is not reproduced here.) The resident's own contacts hear at once because they are the resident's choice; estate officials join only if the gate is silent. Timings are defaults to tune from drill data.

**Acknowledgement is the product.** Every alert has one state: `raised`, `acknowledged` (by whom, when), `on_scene`, `resolved` (with outcome: real emergency, false alarm, test). The resident is told each change by SMS and call-back: "Security has seen your alert. Musa is on the way." An alert nobody acknowledges is the failure this feature exists to prevent, so escalation never stops by itself; it stops when a person acknowledges.

**Designated contacts.**

- Each home sets up to 5 contacts: neighbours inside the estate, relatives outside it, relatives abroad.
- A contact is active only after they reply YES to an invite SMS. This is consent under the NDPA and also stops a resident's contact list being used to harass people.
- Neighbours inside the estate can tap **I'm going** to tell everyone else someone is on the way.
- Relatives abroad get WhatsApp and SMS with the home address and the CSO's number, so they can phone in.

**False alarms and tests.**

- Every resolved alert records its outcome. The committee sees false-alarm rate per month.
- A resident can run a **test alert** that rings only the gate and is labelled TEST, so the elderly can practise.
- Estates run a monthly drill: Gatelog ops raises a test SOS at a random time and records time to acknowledge. This number is the feature's health metric.
- Repeated false alarms from one home are flagged to the estate admin, never auto-blocked. Blocking an SOS line is not a decision software makes.

**What SOS never claims.** Gatelog does not call the police, fire service or an ambulance, and it does not promise anyone will come. It tells the people the estate and the resident chose. The directory (next section) is shown alongside every alert so whoever responds can call public services.

## Emergency directory

The directory's value is accuracy, so every number carries a last-verified date and a dead number is worse than a missing one. Two tiers, merged into one list per estate.

| Tier | Examples | Owned by | Verified |
| --- | --- | --- | --- |
| Estate | Gate line, SOS line, CSO, facility manager, estate clinic or nearest hospital, electrician, plumber | Estate admin | Admin confirms quarterly; Gatelog prompts |
| State and national | National emergency line, police division covering the estate, fire service, state emergency agency, ambulance | Gatelog ops, per state and LGA | Gatelog ops test-calls every number quarterly and after any reported failure |

No state-level number goes live until Gatelog ops has dialled it and recorded who answered and when. Numbers are not seeded from memory or a web list.

**Where it shows up.**

- Gate phone: cached on the device, works offline, tap to call. Shown automatically beside every SOS alert.
- Resident web page: grouped by situation (crime, fire, medical, utilities), tap to call.
- WhatsApp and SMS: send "NUMBERS" to get the top five by return. Call-preferring residents get a printed card from the estate at onboarding, generated from the same data.

**Reporting a dead number.** Any user can tap **This number didn't work**. Reports from two different people in 7 days mark the number "reported not working" (still shown, never hidden, since a flaky line beats none in a fire) and alert whoever owns that tier to re-test within 48 hours.

## Estate admin and committee dashboard

The dashboard sells renewals: it shows the committee what happened at the gate and how fast people answered alarms.

**Admin (facility manager, secretary).**

- Address register on the four-level model; bulk import from the estate's existing list (CSV or Excel, staged for review before commit).
- Residents per home, up to 3 registered numbers, contact preference (WhatsApp, SMS, call), callback-required flag, landlord or occupant, who owes the levy.
- Guards and the CSO (with written consent recorded, PIN reset), shifts and handovers, gate devices; revoke a lost device remotely (rotates its key on next sync).
- SOS escalation ladder per estate: who is tier 2 and 3, timings.
- Estate tier of the directory.

**Committee (read-mostly).**

- Entries by day, gate and method (code, phone-announced, callback, walk-in admitted, refused); exit capture rate (entries with a confirmed exit) and overstays per night; walk-in decisions with who decided and why; search by plate.
- SOS: alerts per month, median and worst time to acknowledge, false-alarm rate, drill results.
- Directory health: numbers past their verification date.
- Export of any view to Excel for ExCo meetings.

**Messaging usage (Exco and treasurer).** A monthly tally of every message Gatelog sent for the estate, so the bill is never a surprise.

- WhatsApp and SMS counts for the month to date, by purpose: guest codes, arrival and exit notices, overstay nudges, rollups, dues reminders, event and worker passes, SOS.
- The SMS allowance (average per home per month, from the contract) against what has been used, a projection to month end, and the projected overage in naira at the contract rate.
- The same figures for each past month, matching the invoice line for line.
- An alert to the treasurer when projected SMS use passes 80% of the allowance.
- Counts only, never message contents or full phone numbers.

SOS and emergency-directory messages are shown but never counted towards the allowance or billed, so no one hesitates to raise an alarm. Dues reminders the Exco sends are counted, because the Exco controls how many go out.

Every change to the register, ladder, contacts, guards and directory is written to an append-only audit log (who, what, when, before, after), and so is every viewing of a shift selfie.

## Data model

Postgres, one shared schema, every table keyed by `estate_id` with Row-Level Security enforcing tenant isolation (same pattern as System A). Chosen over schema-per-tenant because tenants are many and small, the association view and the shared WhatsApp router both need cross-estate queries, and one migration run and one pool suit a single operator. Estate staff sessions see one estate; association users see only the estates their organisation owns; guard phones sync only their estate. CI runs every role against another estate's rows and must return zero. A per-estate export lets any estate be lifted into its own database if a contract ever requires physical separation.

```
Organisation           id, name, kind (association|facility_manager), billing_settings
Estate (tenant)        id, organisation_id|null, name, short_name, state, lga, settings, sos_ladder, hmac_key_ref
OrgMembership          id, organisation_id, user_id, role (org_admin|org_viewer)
Zone / Street / Home   four-level address; Home: id, estate_id, street_id, label, levy_payer (landlord|occupant)
Resident               id, home_id, name, relation (landlord|occupant), contact_pref (whatsapp|sms|call),
                       callback_required, status (invited|active|removed)
PhoneNumber            id, resident_id, e164, verified_at, is_primary     (max 3 per home)
Gate                   id, estate_id, name, shared_with_estate_id|null, lat, lng
Place                  id, estate_id, name, kind (amenity|pickup|post), lat, lng      (estate map and shuttle stops)
Guard                  id, estate_id, name, role (guard|cso|rider), pin_hash|null, consent_at, active
Shuttle                id, estate_id, label, plate, active
ResidentCard           id, resident_id, home_id, uid_hash, uid_last4, issued_at, revoked_at
Ride                   id, home_id, resident_id|null, kind (resident|delivery|guest), source (whatsapp|sms|gate|flag|dispatch),
                       pickup and dropoff (home|gate|place, ref, label), wanted_at, state (requested|accepted|picked_up|
                       done|cancelled|no_show), rider_id, shuttle_id, confirmed_by (card|house_code|guard|rider), times
RideEvent              id (client-generated), ride_id, event (accept|release|pick_up|drop_off|cancel|no_show), guard_id,
                       shift_id, at, lat|null, lng|null                                  (append-only)
Position               shift_id, guard_id, shuttle_id, lat, lng, accuracy, at           (rider shifts only, 7 days)
Device                 id, estate_id, gate_id, device_key_ref, revoked_at
Shift                  id (client-generated), estate_id, guard_id, device_id, gate_id, started_at, ended_at,
                       end_reason (handover|ended|auto), handed_to|null, selfie_ref|null, selfie_deleted_at,
                       handover (inside, unsynced, night list at the time)
Vehicle                id, home_id, plate, description
EventPass              id, home_id, title, window_start, window_end, expected_count,
                       status (requested|approved|declined), approved_by, group_code
WorkerPass             id, home_id|site_id, name, role, days, hours, valid_until
Visit                  id, home_id, guest_name, window_start, window_end,
                       source (whatsapp|sms|phone_announced|ivr), code_issued (bool),
                       expected_until, stay_type (hour|hours|overnight|multi_day),
                       state (expected|inside|left|overstay|rollup_closed)
Callback               id, visit_id|null, home_id, guard_id, shift_id, number_id,
                       outcome (confirmed|declined|no_answer), at
Entry                  id (client-generated, unique), visit_id|null, home_id, guard_id, shift_id, gate_id, plate|null,
                       method (code|phone_announced|callback_confirmed|walk_in_admitted|refused),
                       decided_by|null, reason|null, at, synced_at
Exit                   id (client-generated, unique), entry_id|null, guard_id, shift_id, plate|null,
                       method (code|list_tap|resident_confirmed|rollup_closed), at, synced_at
OverstayNudge          id, visit_id, sent_at, reply (staying|left|none), new_until
Rollup                 id, estate_id, run_at, open_count, closed_by_morning
Levy / Charge / Payment  ledger per home: what is owed, by whom, what was paid, by link or marked by the treasurer
EmergencyContact       id, home_id, name, e164, relation (neighbour|relative|other),
                       inside_estate, consent (invited|accepted|declined), consent_at
Alert                  id, estate_id, home_id|null, trigger (missed_call|web|whatsapp|guard),
                       caller_e164_masked, category|null, is_test, verified (bool),
                       state (raised|acknowledged|on_scene|resolved), outcome, raised_at
AlertEvent             id, alert_id, kind (notified|delivered|acknowledged|escalated|...),
                       recipient_type, recipient_id, channel (push|sms|voice|whatsapp), at
DirectoryEntry         id, scope (estate|state|lga), estate_id|state|lga, category,
                       name, e164, verified_at, verified_by, reports_open
AuditEvent             id, estate_id, actor_id, entity, entity_id, action, before, after, at
```

Phone numbers are stored in full only in `PhoneNumber` and `EmergencyContact`, encrypted at rest, and masked to the last 4 digits everywhere else, including logs and Sentry.

## Integrations and stack

Stack as decided: Next.js (admin dashboard and resident web page) on Vercel, FastAPI on Cloud Run, Cloud SQL Postgres, Termii for SMS and voice, Postmark for email, Sentry, and Flutter for the gate phone app. Termii's voice support for the SOS missed-call line is the one dependency still to prove.

| Need | Choice | Notes |
| --- | --- | --- |
| Resident messaging | WhatsApp Cloud API; SMS until WABA is approved | SOS alerts to contacts need pre-approved templates; submit them with the first template batch |
| SMS | Termii | Sender ID registration has weeks of lead time; start now |
| Voice: SOS missed-call line, automated alert calls, Phase 2 IVR | Termii (confirm inbound missed-call caller ID on a local number; Africa's Talking is the fallback if not) | Must support inbound caller ID on a local number, rejecting unanswered calls, and outbound text-to-speech calls in English and Yoruba |
| Gate alarm | FCM push to the gate phone app, which raises a full-screen alarm over the lock screen, plus a Termii voice call to the gate SIM as backup | Native Android can ring loudly with the screen locked; a PWA cannot. The voice call stays as the second channel |
| Callback dialling | Native dialler from the gate phone | No integration; the gate's own SIM places the call |
| Shift selfies | Cloud Storage bucket in `europe-west1`, encrypted before upload, 30-day deletion | Never in the database |

**Platform services.**

| Need | Choice | Why |
| --- | --- | --- |
| SOS escalation timers, sync retries, rollups | Cloud Tasks (rollups via Cloud Scheduler) | Durable scheduled callbacks. A FastAPI background task dies with its Cloud Run instance, and an escalation that silently never fires is the worst bug this product can have |
| Push | Firebase Cloud Messaging | Gate phone app, plus Web Push for the resident web page |
| Resident WhatsApp | WhatsApp Cloud API, direct with Meta | Termii does not cover it. SOS contact templates go into the first WABA approval batch |
| Secrets | Secret Manager | Per-estate HMAC keys and provider credentials; never in env files or the repo |
| Offline store on the gate device | SQLite via drift (Flutter), encrypted | Address register, estate key, expected visits, guard PIN hashes, queued entries, exits and shifts |
| Database, hosting | Cloud SQL Postgres, Cloud Run, Vercel (admin web), Sentry | As already decided |

**Gate phone app: Flutter, Android only.** Gate phones are Gatelog-leased Android devices running the estate's own SIMs, so there is no iOS build. Native gets three things a PWA cannot: a loud alarm over the lock screen, the incoming caller's number via Android's call-screening role, and dependable background sync. The admin dashboard and resident SOS page stay Next.js on the web.

If the Termii missed-call check fails, SOS waits; the rest of Phase 1 does not.

**One WhatsApp number for the whole platform.** Every estate's inbound and outbound WhatsApp runs through a single Gatelog number, display name "Gatelog". Rules that come with it:

- Inbound messages route strictly by sender number to a registered home. An unregistered number gets a reply that names no estate. A number registered to two homes is asked which home before anything happens. There is no default or "last used" estate.
- Every message body names the estate ("SKA Exco: …"), since the sender shows as Gatelog.
- Dues reminders use the utility template category, worded as statements of account, with a per-estate send cap, so one estate's blocks or reports cannot lower the number's quality rating for everyone.
- The number's quality rating is a tracked health metric. Termii SMS is the fallback for every message type if the number is restricted.
- Kill criterion: quality rating below high twice in any 90 days → move dues reminders to SMS or a second number before onboarding more estates.

**One phone per gate.** Each gate has its own phone and line; callbacks come from that gate's number. Until the Phase 2b virtual gate line exists, the main gate's number is published as the estate's gate number for call-the-gate.

**Walkie-talkies (to explore, Phase 2).** Most estates already run their guards on handheld radios. Gatelog does not replace them; it can speak into them.

- **What it would do:** the gate phone reads short alerts aloud onto the estate's radio channel, so every guard on patrol hears them: SOS ("SOS, 14B Adeniyi Close, security needed"), and optionally the nightly rollup and a gate needing backup.
- **How:** a dedicated radio at the gatehouse connected to the gate phone by a phone-to-radio audio cable (the kind used for APRS, on the common two-pin radio plug, voice-activated transmit). The app speaks the alert with text-to-speech. Needs a phone with a headphone jack or a USB-C audio adapter; check the chosen model.
- **One way only.** Radio traffic is not recorded or transcribed into Gatelog; guards still acknowledge in the app.
- **Risks:** many estate radios run on unlicensed frequencies, and automated transmission adds to that exposure, so the estate confirms its radio use is licensed (NCC) before this is switched on. Voice-activated transmit can trigger on gatehouse noise; test it in place.
- **Alternative:** push-to-talk over mobile data (a walkie-talkie app on the guard phones) only if an estate has no radios.
- **Kill criterion:** if a pilot gatehouse cannot get reliable transmission in 2 weeks of testing, drop it and rely on the voice call to the gate phone.

## Gate kit

Gatelog supplies the gate phones, leased inside the subscription, so every gate runs on a device Gatelog controls. The estate never buys hardware; Gatelog owns it, locks it down and swaps it. The CSO uses whichever gate phone is at hand; there is no separate CSO device.

**What is in the kit (per gate, plus one spare per estate).**

- Android phone, non-Go edition, Android 14 or newer, 4 GB RAM or more, 5,000 mAh battery or more, dual SIM, loud speaker, front camera (for the shift selfie).
- Rugged case and tempered glass (true rugged phones cost roughly 2 to 3 times more; see budget below).
- 20,000 mAh power bank and charging cable kept at the gatehouse.
- SIMs supplied by the estate: its existing security line (the number residents already have saved) for calls, and a data SIM in the second slot. The estate pays its own airtime and data.

**Budget (checked October 2026, re-check before each purchase).** New rugged phones in Nigeria start well above ₦200,000, and the cheapest one with a big enough battery is near ₦285,000. A mainstream budget phone with a case lands around ₦125,000 to ₦145,000 and meets the spec. Phones under ₦100,000 are mostly Android Go edition, which is ruled out.

**Lockdown.** Android Enterprise dedicated-device (kiosk) mode or a low-cost MDM: only the Gatelog app runs, settings are locked, and a lost phone can be wiped and its estate key rotated remotely.

**Lease terms.**

- Gatelog owns the devices; they are returned at contract end.
- Faults and wear are Gatelog's cost: swap from the estate's spare within 48 hours.
- Loss, theft or obvious abuse is the estate's cost at a fixed replacement fee in the contract.
- Device cost is recovered inside the subscription within 12 months.

**Kill criteria.** Review after 6 months with the first two estates. If devices are not paid back within 12 months, or more than 1 device per estate per quarter is lost or damaged, stop bundling and move to bring-your-own-phone with the same spec.

## Non-functional, safety and liability

The top failure mode is an SOS that nobody hears; the cheap mitigation is redundant channels plus an escalation that never stops on its own.

**Targets.**

- SOS: first notification to the gate within 10 seconds of the trigger reaching the server; gate phone rings by voice call within 30 seconds.
- Every SOS path has two channels per recipient (push and voice for guards; SMS and WhatsApp or voice for contacts).
- Core gate flow: code verification and shift start work with zero network; offline entries sync with no loss or duplication.
- Alert service is isolated from the rest of the API (its own Cloud Run service, minimum one warm instance) so a bad deploy of the dashboard cannot take SOS down.
- Synthetic SOS test every hour against a Gatelog-owned test estate; page PI Technologies if it fails.

**Liability and claims.**

- Terms and onboarding state plainly: Gatelog is a notification tool, not an emergency or security service, and does not guarantee a response.
- Marketing never says "help arrives" or "protects you". It says "alerts your gate and your people".
- The landing page's four claims (WhatsApp, signed codes, offline verification, four-level addresses) stay as they are until each new feature ships to a live estate. Update the CLAUDE.md claims list in the same commit that ships the feature.
- Counsel review of the SOS terms before the first estate turns it on.

**Data protection (NDPA 2023).**

- Explicit consent from each emergency contact (invite and YES reply), recorded with time.
- Written consent from each guard and CSO for shift selfies, recorded before their first shift; selfies deleted after 30 days.
- No call recordings in Phase 1. Phase 2 IVR guest-name clips are deleted after 7 days.
- Data hosted in `europe-west1`; confirm the cross-border transfer basis with counsel, as for System A.
- Never log full phone numbers.

## Phasing, effort, kill criteria

Phase 1 is the gate, the dues ledger and the two cheap features; SOS is built in Phase 2 and switched on only when drills prove it. Effort is in build-weeks at evening-and-weekend pace, to be recalibrated after the first two weeks.

| Phase | Scope | Effort (build-weeks) | Gate to move on |
| --- | --- | --- | --- |
| 1 | Auth, tenancy and the organisation level, address register and import, multiple gates, core gate flow with offline sync, vehicle plates, callback flows A and B, visit length with exits and nightly rollup, emergency directory, guard and CSO on the gate phone with PIN and selfie shifts, walk-in decisions, tenants, dues ledger with payment links (no custody), messaging usage, admin dashboard | 13 to 16 (core 5 to 6, gates and plates 1, exits and rollup 1 to 2, callback 1, directory 1, shifts and CSO 2, tenants and dues 1.5, dashboard 2) | One pilot estate live, signed agreement with Deborah Ojo |
| 1.5 | Estate shuttle and the estate map (built first: the pilot's motorcycles are in service), then event passes, recurring worker passes, shared-gate linking | 4 to 6 (shuttle 2 to 3, map 1) | Pilot estate asks for them, or its first event is booked |
| 2 | SOS (all three triggers, ladder, contacts, drills), voice provider, committee SOS reports | 4 to 5 | Provider check passed; drills meet the go-live bar below |
| 2b | Virtual gate line with IVR (flow C) | 2 | Pilot data shows guards spend real time on phone-announcement lookups |

In-app collection (Gatelog holding funds) and levy-based gating stay out until 2 paying estates ask and counsel has advised.

**Kill criteria.**

- **Whole product:** no signed pilot estate by 31 January 2027 → stop feature work and spend the hours on estate conversations.
- **Callback:** if after 8 weeks of a live pilot more than 40% of entries are phone-announced or callback and the share is not falling, codes are not being adopted; rethink the core for that estate type before building more. **Exits:** if fewer than 70% of entries have a confirmed exit after 4 weeks of pilot, the rollup is noise; fix exit capture at the gate (pedestrian gate, shift handover) before adding anything that reads it.
- **SOS go-live bar:** 4 consecutive weekly drills with median acknowledgement within 60 seconds and none over 3 minutes. Not met by 31 March 2027 → SOS stays off for residents, and only the guard-raised internal alert ships.
- **SOS after launch:** more than 2 false alarms per 100 homes per month after the first month, or any real alert unacknowledged for 5 minutes → pause new estate SOS rollouts and review.

**What gets dropped to fund this.** Landing page polish stops now; the IVR (2b) is not built on speculation.

## Out of scope and open decisions

**Out of scope for v1.0:** holding dues funds; restricting access on dues status; a native resident app; a separate CSO device; automatic dispatch to police, fire or ambulance; call recording; face recognition; physical panic buttons or wearables; CCTV or barrier hardware integration.

**Open decisions.**

- [ ] Pricing. Venco gives its visitor module away free and charges about ₦1,500 per occupied unit per month for the bundle. Decide whether Gatelog's gate is free, cheap or priced as the security tier, with dues and messaging carrying the rest.
- [ ] Voice provider: confirm one Nigerian provider supports missed-call caller ID, call rejection, outbound text-to-speech, and its per-call cost.
- [ ] Whether a missed call needs airtime on each major network; test on MTN, Airtel, Glo and 9mobile in the pilot.
- [ ] Yoruba (and Pidgin) voice prompts for alert calls and IVR.
- [ ] Who pays: estate subscription only, or a paid add-on for relatives (often abroad) who want SOS alerts about a parent. Worth testing in the pilot, not building.
- [ ] Payment link provider: Paystack or Flutterwave split or subaccount into the association's own account.
- [ ] Counsel review of SOS terms and the NDPA cross-border basis.
- [ ] Signed written agreement with Deborah Ojo (role, equity, IP) before the first paying estate.
