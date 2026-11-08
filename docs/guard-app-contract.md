# Gate phone ↔ API contract

The gate phone is a Gatelog-leased Android phone running the estate's own security SIM. One
app serves the guard and the CSO: whoever opens the shift decides which view shows. It must
keep working with no data connection: start a shift, verify codes, log entries and exits, take
phone announcements and call residents back. This file is what the Flutter app and
`apps/api/app/routers/device.py` agree on. The product rules are in `docs/spec.md`.

## Pairing

The estate admin registers the phone in the dashboard and gets an 8-character code
(`ABCD-2345`, 24 hours, single use).

```
POST /v1/device/pair            {"code": "ABCD-2345", "fcm_token": "..."}
-> 200 {"token": "gld.<device_id>.<estate_id>.<secret>", "device_id", "estate_id", "estate_name", "gate_name"}
-> 400 wrong or expired code     -> 429 too many attempts from this address
```

Store the token in the encrypted store. Send it as `Authorization: Bearer <token>` on every
call. A `401` means the phone was revoked or re-paired: wipe local data and show the pairing
screen. `PUT /v1/device/fcm-token {"fcm_token"}` when Firebase rotates the token.

## Pulling state

```
GET /v1/device/state   (If-None-Match: <etag>)  -> 200 + ETag, or 304
```

Pull on launch, on an FCM data message `{"type": "sync"}`, every 2 minutes while in the
foreground, every 15 minutes in the background, and whenever the network returns. The
response replaces the local copy of each section:

| Key | Use |
|---|---|
| `estate` | name, timezone, `walk_in_policy` (show it when a callback fails or a guest has no code), current `key_version` |
| `device` | this phone's id and gate |
| `keys[]` | `{version, key_b64}`: every HMAC key an open visit still needs. Keep them only in the encrypted store |
| `gates[]` | `{id, name}` |
| `guards[]` | `{id, name, role: guard\|cso, pin_hash\|null, pin_reset_at\|null, consent}`: everyone who can open a shift. Keep in the encrypted store |
| `homes[]` | `{id, label, street, zone, address, callback_required, residents[{id, name, contact_pref, numbers[{id, e164, last4, is_primary}]}], vehicles[{plate, description}]}`. Full numbers are here so callbacks work with no data; never show more than the last 4 digits except on the dial screen |
| `visits[]` | expected and open visits: `{id, home_id, resident_id, guest_name, window_start, window_end (unix s), key_version, code_issued, source, state, expected_until, entry_id, entered_at}` |
| `rollup` | tonight's list, or null: `{id, for_date, items[{id, visit_id, guest_name, home_id, address, expected_until, checked_at, check_result}]}` |
| `directory[]` | `{id, category, name, number, verified_at, reported_not_working}`, already ordered |

## Shifts: PIN and selfie

Nothing can be recorded without an open shift. The start screen lists `guards[]` by name.

1. **Pick your name.** A guard with `consent: false` cannot start: show "Ask the estate admin to
   record your consent form first." A guard who is not in the list asks the CSO.
2. **PIN.** If `pin_hash` is null (first shift, or the admin reset it), the guard chooses a PIN
   (6 digits, entered twice). The phone hashes it and queues a `pins` record; the PIN itself
   never leaves the phone. Otherwise the guard enters their PIN and the phone checks it
   against `pin_hash`. Five wrong tries lock that guard out on this phone for 5 minutes.

   ```
   pin_hash = "pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>"
   salt     = 16 random bytes; iterations >= 20000 (use 60000); hash = PBKDF2-HMAC-SHA256(pin, salt, iterations, 32 bytes)
   ```

   A PIN set on this phone but not yet synced wins locally over the state's `pin_hash` until it
   syncs. If the sync rejects it (the admin reset the PIN after it was set), the guard sets it again.
3. **Selfie.** Front camera, one photo, JPEG under 400 KB (about 640 px on the long side). If the
   camera fails, the shift still starts with `selfie_taken: false`; never block a gate on a camera.
4. **Open.** Queue the shift `{id, guard_id, started_at, selfie_taken}`. Store the selfie in the
   encrypted store and upload it when there is data:

   ```
   PUT /v1/device/shifts/{shift_id}/selfie     body: the JPEG, Content-Type: image/jpeg
   -> 204 stored (or already stored)   -> 404 the shift has not synced yet: retry after the next sync
   -> 413 too large   -> 415 not a JPEG
   ```

   Delete the local copy once uploaded. Never show selfies in the app.

Every record made during the shift carries `shift_id` and `guard_id`. A guard's role decides the
view: `guard` gets the guard view, `cso` gets the CSO view (below).

**Ending.** End shift asks who is taking over (anyone in `guards[]` with consent), or "nobody".
Queue the same shift record again with `ended_at`, `end_reason: handover|ended`, `handed_to`, and
`handover: {inside: <count>, unsynced: <count>, night_list_open: <count>}`. The next person then
starts their own shift with their PIN and selfie. The phone ends a shift by itself after 14
hours (`end_reason: auto`); the server does the same for a shift whose phone went quiet.

## Verifying a code offline

For each cached visit with `code_issued` and `window_start <= now <= window_end`:

```
msg  = "gatelog-code-v1|<home_id>|<visit_id>|<window_start>|<window_end>"   (UUIDs lowercase, times unix seconds)
mac  = HMAC-SHA256(key[visit.key_version], msg)
off  = mac[31] & 0x0f
code = ((mac[off..off+4] as big-endian u32) & 0x7fffffff) % 1_000_000, zero-padded to 6
```

`docs/code-test-vectors.json` pins the output. The app's unit tests must pass every vector.
The server guarantees no two open visits **whose entry windows overlap** share a code. Two
visits on different days can, so when more than one cached visit matches, prefer in order:
the one whose window is open now, then a guest already inside, then "code not valid now"
(show the window). A guest who is **inside** matches their code at any time, so they can exit
after their entry window has closed. A visit in state `cancelled` is not sent, so it does not match.

If the home's `callback_required` is true, a valid code still needs a callback before admitting.

## Recording things: the offline queue

Everything is written to a local queue first, with a UUID v4 generated on the phone, and
pushed in batches:

```
POST /v1/device/sync
{
  "pins":      [{guard_id, pin_hash, set_at}],
  "shifts":    [{id, guard_id, started_at, selfie_taken, ended_at?, end_reason?, handed_to?, handover?}],
  "visits":    [{id, home_id, resident_id, guest_name, window_start, window_end, expected_until, stay_type, stay_minutes, stay_given}],
  "callbacks": [{id, home_id, number_id, outcome: confirmed|declined|no_answer, visit_id?, guard_id, shift_id, at}],
  "entries":   [{id, home_id, guest_name, method: code|callback_confirmed|walk_in_admitted|refused, visit_id?, guard_id, shift_id,
                 gate_id?, plate?, decided_by?, reason?, note?, at}],
  "exits":     [{id, method: code|list_tap, entry_id?, visit_id?, guest_name?, guard_id, shift_id, gate_id?, plate?, at}],
  "rollup_checks": [{item_id, result: left|still_inside, guard_id, at}]
}
-> {"accepted": [ids], "duplicates": [ids], "rejected": [{id, reason}]}
```

Ids in the response are the record's `id`; for `pins` it is the `guard_id`, for `rollup_checks`
the `item_id`. Remove `accepted` and `duplicates` from the queue. `rejected` items will never be
accepted: remove them too and show them on a "needs attention" screen. Retrying is always safe:
the server inserts on the client ID and runs side effects (resident notices) only once. Times
are ISO 8601 with offset; send the phone's time, the server clamps anything more than 5
minutes in the future. Send a shift before the records made during it (the server orders them
within one batch anyway).

**Plates** are optional on every entry and exit, typed by the guard. Send them as typed; the
server normalises (`lnd 123-ab` → `LND123AB`). When the typed plate matches one of the home's
`vehicles`, show it as a match.

**Walk-in decisions.** When nobody at the home can be reached, the guard or the CSO on duty
decides. Admitted: entry `method: walk_in_admitted` with `decided_by` (a guard id, usually the
CSO's) and `reason` (required). Refused: entry `method: refused`, with `reason` if one was given.
The server rejects a `walk_in_admitted` entry without both.

## The guard view

The keypad is the screen. Under it, two buttons only: **No code** and **Leaving**. A small menu
holds Emergency numbers and End shift.

**Code at the gate.** Enter 6 digits → offline match → show guest name and home address →
Let them in (entry `method: code`, `visit_id`) or Turn away (entry `method: refused`).

**Leaving.** Re-enter the guest's code, or tap the name in the Leaving list (visits with an entry
and no exit, sorted by home) → exit `method: code` or `list_tap` with `entry_id`. One action,
works offline. An exit for someone not on the list is still recorded with `guest_name` only.

**No code (flows A and B together).** Find the home by label or surname → the home shows any
guest already confirmed by phone (Let in: entry `method: callback_confirmed` with that
`visit_id`) and its residents with masked numbers → **Call** opens the native dialler (`tel:`)
→ Confirmed / Said no / No answer (a `callbacks` record). Confirmed asks the guest's name, then:

- **They are here: let them in** → entry `method: callback_confirmed`, no `visit_id`. The server
  makes a visit for it, which comes back in `/state` with `entry_id` equal to the phone's entry
  id; drop the local copy when it does.
- **Coming later: expect them** → pick the stay (about an hour = 60, a few hours = 180,
  overnight = next day 10:00, a date = 18:00 that day) → a `visits` record (window now until
  23:59 today, at least one hour) linked from the callback's `visit_id`.

Record a **Confirmed** callback as soon as the guard taps it, before asking what happens next, so
the call is on file even if the guard never chooses. For "expect them", queue the visit, then send
the same callback again (same `id`, now with `visit_id`), behind the visit in the queue: the server
answers `duplicates` and links the visit once. It never moves a link that is already set.

Said no, or No answer twice → do not admit on phone authority: show `walk_in_policy`; the guard
can turn the guest away (entry `refused` with the reason) or, if the policy allows, record the
CSO's decision (entry `walk_in_admitted`, `decided_by`, `reason`, no `visit_id`). As with flow B,
the server makes a visit for the walk-in, which comes back in `/state` with `entry_id` equal to
the phone's entry id, so every gate, the CSO's People tab and the night list see the guest inside.
The walk-in visit has no resident: nobody confirmed, so nobody is messaged about it.

**Trust levels and the home PIN** (spec: call-the-gate, trust levels). The server records how well
each admitted entry was verified: `code` and `callback_confirmed` are verified; `pin_confirmed` is
PIN-verified; `walk_in_admitted` and `phone_announced` are unverified.

- **Home PIN.** A caller from any number can give the home's 4-digit PIN. Check it offline against
  the home's `house_code_hash` in `homes[]` (the same hash the shuttle uses; null until set), exactly
  like a guard PIN. **3 wrong tries per call**, then stop and offer the callback or the CSO.
  - Every check, right or wrong, is a `pin_checks` record: `{id, home_id, ok, context: gate|shuttle,
    caller_masked?, guard_id, shift_id, at}`. The PIN itself never leaves the phone.
  - A wrong try texts the home, so send `pin_checks` from the rider's house-code check too
    (`context: shuttle`).
- **PIN-verified entries.** Guest here now: entry `method: pin_confirmed`, no `visit_id`; the server
  makes the visit. Coming later: a `visits` record with `trust: pin_verified`; letting them in from
  the confirmed list keeps that trust.
- **Caller number.** When the phone saw the announcing call's number, send it masked on the entry
  and the PIN check: `caller_masked: "0803•••1234"`. At most the first 4 and last 4 digits; a full
  number is rejected (422).
- **Unverified entries** (`walk_in_admitted`, `phone_announced`) text every registered number of the
  home at once: "Not you? Reply NO". A NO shows in the CSO view under `needs.disputed_today` and goes
  to the security head by SMS. Nothing changes on the gate phone's side.

**A resident's new number.** When a resident rang the gate from a number not on file and then
confirmed on the callback to their registered number, offer "Add this number for Mrs Adeyemi?"
(Yes/No). Yes is a `number_offers` record: `{id, resident_id, number, guard_id, shift_id, at}`,
where `number` is the full number the call came from. It is the only record that carries one;
never log it. The home's registered number is asked to reply YES, and nothing else happens on
the phone. Once the home says YES, the number appears in `/state` at the next pull. Rejected
offers come back with the reason (already registered, three numbers already, nobody to ask).

**`phone_announced`** (entry method) means admitted on the resident's inbound call alone, with no
callback. The spec keeps it so the committee can see how often that happens; the app does not
offer it, because an inbound caller ID is a hint, not proof.

## The CSO view

Everything in the guard view, plus four tabs: **Now**, **People**, **Shifts**, **Numbers**.

```
GET /v1/device/cso      X-Shift-Id: <the CSO's open shift on this phone>
-> 200 {server_time,
        needs: {overdue[{visit_id, guest_name, home_id, address, expected_until, resident_id}],
                refused_today[{entry_id, guest_name, address, gate, by, reason, at}],
                walk_ins_today[{entry_id, guest_name, address, gate, decided_by, reason, at}],
                quiet_phones[{device_id, gate, label, last_sync_at, on_duty}],
                night_list_unchecked},
        on_duty[{gate, guard, role, since, phone_last_sync_at}],
        shifts_today[{id, gate, guard, started_at, ended_at, end_reason, handed_to, handover, selfie}]}
-> 403 the shift is not open on this phone, or is not a CSO's
```

Fetch it when the CSO view opens and every minute while it is showing. Show when it was
fetched; with no network show the last copy and say so. **People** (expected and inside at every
gate) and the night list come from `/state`, so they work offline. Calls to residents use the
numbers in `homes[]`. Marking an overdue guest as left from the CSO view is an exit
`method: list_tap`; checking the night list is a `rollup_checks` record.

**Directory.** Grouped list, tap to dial. "This number didn't work" →
`POST /v1/device/directory/report {"entry_id", "guard_id"}` (queue it if offline).

## The estate shuttle

Only where the estate runs one: `/state` then has a `shuttle` object (it is `null` otherwise, and
nothing below shows). The product rules are in `docs/spec.md`, "Estate shuttle".

```
shuttle: {
  shuttles[{id, label, plate}],                 the estate's motorcycles
  places[{id, name, kind, lat, lng}],           estate places a ride can start or end at
  cards[{id, uid_hash, resident_id, home_id, uid_last4}],
  rides[{id, kind: resident|delivery|guest, source: whatsapp|sms|gate|flag|dispatch,
         state: requested|accepted|picked_up, home_id, resident_id, passenger,
         pickup{kind: home|gate|place, ref, label, lat, lng}, dropoff{...},
         wanted_at, note, rider_id, rider, shuttle_id, accepted_at, picked_up_at, created_at}]
}
```

Open rides wanted within the next 24 hours, soonest first. `homes[]` also carry `house_code_hash`
(null until the household asks for a code), and `homes[]` and `gates[]` carry `lat`, `lng` (null
until the admin pins them).

**Riders.** `guards[]` with `role: rider`. Starting a shift is the same (consent, PIN, selfie), plus
one step: pick the motorcycle from `shuttle.shuttles` (send it as the shift's `shuttle_id`). A rider
gets the rider view.

**Rider view.** The queue: `rides` with `state: requested`, then the rider's own (`rider_id` = them).
Refresh `/state` every 15 seconds while the rider view is showing (it is a 304 when nothing changed).
Each ride shows kind, from, to, how long it has waited, passenger or parcel, and the note.

- **Take it** → event `accept`. If someone else got there first the sync rejects it with
  "taken by <name>": show that and drop the ride from the list.
- **Hand back** → `release` (back to the queue). **No-show** → `no_show`.
- **Picked up** → `pick_up`, with who rode (below). **Dropped off** → `drop_off`. For a delivery,
  record who received the parcel at drop-off instead of at pickup.
- **New ride (flagged down)** → a `rides` record with `source: flag`, then `pick_up` in the same
  batch. The home comes from the card or house code, or the rider picks it.

**Who rode.** `confirmed_by` on the `pick_up` (or a delivery's `drop_off`) event:

- `card`: the rider taps the resident's estate card on the phone (NFC). Read the tag's UID as hex,
  then `uid_hash = sha256("gatelog-card-v1|<estate_id>|<UID hex, upper case, no separators>")`, hex.
  Look it up in `shuttle.cards`: send `card_id` and `resident_id`. An unknown card says so; the rider
  can use the house code instead. Works offline.
- `house_code`: the resident says their home PIN (4 digits, the same PIN as for phone calls to the
  gate); check offline against the home's `house_code_hash` exactly like a guard PIN (same format,
  same PBKDF2). Send `resident_id` if the rider picked who it is. Send a `pin_checks` record
  (`context: shuttle`) for every try. Three wrong tries on one home: stop and use the card or vouch.
- `guard` (a gate booking the guard handed over) or `rider` (the rider vouches): no check.

**Position.** While a rider's shift is open, and only then, send the phone's position every 15
seconds (foreground service with its notification, so Android keeps it going):

```
POST /v1/device/positions   {"shift_id", "points": [{lat, lng, accuracy_m?, heading?, speed?, at}]}   at most 200 points
-> 200 {"stored": n}   -> 409 the shift is not open on this phone   -> 403 not a rider's shift
```

Queue points while offline and send them in batches when the network returns (oldest first, keep
the last 2 hours at most). Stop the moment the shift ends.

**Booking at the gate (guard view).** From the menu, and on the home screen in No code after a guest
is let in: **Shuttle to the home**. A `rides` record, `source: gate`, `kind: delivery` (with what the
parcel is in `passenger`) or `guest` (the guest's name), pickup the phone's gate, dropoff the home.

**CSO view.** A **Shuttle** tab: open rides with their rider, rides waiting over 10 minutes (also
in `needs.rides_waiting` of `/v1/device/cso`), and **Book a ride** for a resident who rang the CSO
(`source: dispatch`, `kind: resident`, the resident picked from the home). **Issue a card**: tap a
new card, pick the resident, send a `cards` record. Only the CSO may issue; a card already issued
comes back rejected with whose it is.

```
POST /v1/device/sync   (added to the batch)
  "cards":       [{id, resident_id, uid_hash, uid_last4, guard_id, shift_id, at}]
  "rides":       [{id, kind, source: gate|flag|dispatch, home_id, resident_id?, passenger?, pickup{kind, ref},
                   dropoff{kind, ref}, wanted_at?, note?, guard_id, shift_id, at}]
  "ride_events": [{id, ride_id, event: accept|release|pick_up|drop_off|cancel|no_show, guard_id, shift_id,
                   confirmed_by?: card|house_code|guard|rider, resident_id?, card_id?, lat?, lng?, at}]
  "shifts":      [{..., shuttle_id?}]
```

The server applies events in time order. A pickup or drop-off is always applied (the passenger
really was carried); only `accept` can lose to another rider. Ending a rider's shift hands their
untaken rides back to the queue.

## What the phone must never do

- Log or send to crash reporting a full phone number, a key, a PIN, a PIN hash, a selfie or the device token.
- Show more than the last 4 digits of a resident's number outside the dial action.
- Show a selfie, or keep one after it has uploaded.
- Record or send a position outside an open rider shift. Show or log a house code or a card's raw UID.
- Treat an inbound caller ID as proof. Only the callback is.
