# Changelog

One short note per build step, newest first. The product rules are in `docs/spec.md`.

## 22 November 2026: the estate admin corrects the estate's name and area

- **Settings, "Estate name, area and message name":** the estate admin can change the estate's name, state and LGA (`PATCH /v1/admin/estate` takes `name`, `state`, `lga`), audited. Emergency numbers follow the new area. Other staff see the values read-only.
- **One spelling per state:** the state must be one of the 36 states or the FCT (`app/ng.py`), for the admin and for ops, because state and LGA numbers reach an estate by an exact match.
- **Map setup opens on the estate's LGA** instead of a fixed default place, until a boundary is drawn.
- **Card view (v2):** the earlier, fuller dashboard (the live map with its status, live log and shuttle cards, and the last 30 days as stat cards) is back at `/dashboard/v2`, side by side with the simple one, to compare. Linked from Today and back.

## 21 November 2026: finding the estate on the map without coordinates

- **Map setup:** "Find the estate" takes an estate name, street or area instead of latitude and longitude. The dashboard asks OpenStreetMap (Nominatim, Nigeria only) from its own server, at `/dashboard/geocode`, signed-in staff only, with a timeout, one retry and cached answers; several matches show as a list to pick from.
- **Use my location:** for an admin standing in the estate. Pasted coordinates and Google Maps links still work.
- **Outlining the estate:** three numbered steps (find, outline, save). "Start with a box" puts four corners over the visible map, at most about 500 m wide, to drag onto the walls. A click adds a corner on the nearest edge, so the click order no longer matters. The outline's size shows ("About 500 m by 400 m") with a warning when it is far too big or small. Undo covers drags too. After the first save the editor moves on to the gates.
- **Today, for a new estate:** a "Set up your estate" checklist (map, gate pins, homes, phone numbers, guards, CSO, gate phone pairing), the next step highlighted, until every step is done. It replaces the matching to-do items meanwhile.

## 14 November 2026: step 3, the gate phone redesigned to the handoff

- **Home:** the same three big buttons, always in the same place (Visitor has code, Phone call, Visitor leaving), Emergency numbers below, a network chip that says the phone still works offline.
- **Start shift:** tap your face, then the 6-digit PIN; the selfie is taken by itself. Riders and the CSO start the same way.
- **Phone call:** caller ID suggests the home; call the home back, say the visitor's name (voice clip), "Did they say yes?". The home PIN, number offers, and the CSO's decision (CSOs on shift first, "decided alone" when the CSO is also at the gate) are all Yes or No.
- **After a let-in:** the visitor photo by the estate's rule, and the car plate by camera, read on the phone (ML Kit, offline) and confirmed.
- **Words:** every shown or spoken line is in `lib/ui/words.dart`, read aloud; nothing speaks a PIN, code or phone number. Pairing restyled to the kit.
- Clips and photos wait encrypted on the phone (drift schema 4) and upload after sync. Android call screening keeps the caller's number in memory only.
- 173 phone tests; the live API integration test covers clips, photos, number offers, PIN entries and walk-ins.

## 14 November 2026: PIN resets by the security head; who is on shift, for every gate phone

- **PIN reset:** `POST /v1/admin/guards/{id}/reset-pin` is now open to the security head as well as the estate admin. It is audited with who did it. On the dashboard, the security head's guard cards have a Change menu holding only Reset PIN.
- **Who is on shift:** `/v1/device/state` carries `on_duty` (guard id, gate id, since) for every open shift. The gate phone uses it to offer the CSOs on shift first for a walk-in decision.
- **"Not you?" texts:** a guest named only by a voice clip is now "A guest", and a dispute reply says "the guest", instead of quoting "Voice clip".
- **Emergency numbers:** the Exco can tap "This number didn't work" again. It takes two reports from different people to mark a number.

## 10 November 2026: visitor and plate photos; the CSO on the gate

- **Uploading photos:** `PUT /v1/device/photos/{id}?kind=visitor|plate` takes a JPEG under 400 KB, encrypted before storage and deleted after 30 days. Entries name their photos (`visitor_photo_id`, `plate_photo_id`) or record why there is none (`photo_skipped: no_camera | refused`).
- **When to take one:** new estate setting `visitor_photos` (`all`, `phone_entries` by default, `off`), sent to the gate phone in `/state`.
- **Viewing:** the admin and the CSO only, at `GET /v1/admin/photos/{id}`. Each view is audited.
- **Decided alone:** a walk-in that the CSO decided while also being the one on the gate is flagged in the gate log, the CSO view and the Excel export. The spec now says the CSO is usually on the gate, so the CSO view is built gate-first.
- Migration 0008. The isolation test covers the new table and route.

## 8 November 2026: voice clips for visitor names (API for step 3)

- **Upload:** `PUT /v1/device/clips/{id}` takes a short audio clip of the visitor's name. It is encrypted before storage and deleted after 7 days.
- **Links:** entries and visits point at the clip (`name_clip_id`), and the two can arrive in either order.
- **Playback:** the admin and the CSO can play a clip (`GET /v1/admin/clips/{id}`, audited, no-store).
- **Typing the name:** `PATCH /v1/admin/entries/{id}` types the name in (audited) and renames the visit, so the gate's Leaving list shows it.
- Migration 0007. The isolation test covers the new table and routes.

## 8 November 2026: step 2b, a resident's new number, with the home's YES

- **Offer from the gate:** after a callback confirms a resident who rang from an unknown number, the gate phone can offer to register it (`number_offers` sync record).
- **Pending until the home agrees:** the number waits in `phone_numbers` with `pending_until` (full numbers still live only there), and the home's registered number is asked to reply YES or NO.
- **While pending it is invisible:**
  - inbound messages don't route to the home (migration 0006 changes `gatelog_lookup_phone`);
  - callbacks can't use it;
  - it isn't on the gate phone or in home alerts.
- **YES** activates it (audited as the resident's action) and welcomes the new number. **NO** deletes it. **No answer within 48 hours** expires it.
- **Limits:** the 3-numbers-per-home limit and the duplicate check apply, with a pending number counting towards the 3. The consent messages are never billed.

## 8 November 2026: step 2a, trust levels and the second pair of eyes

- **Trust on every admitted entry:** `verified` (code, callback), `pin_verified` (the new entry method `pin_confirmed`, or a visit announced with the home PIN), `unverified` (walk-in on the CSO's decision, or an inbound call alone). Migration 0005 backfills trust on existing entries.
- **Unverified entries are never silent.** Every registered number of the home gets an SMS: "A guest (Tunde) for 14B was admitted at Main Gate, 16:06, after a call from 0803•••1234. Not you? Reply NO." It goes by SMS whatever the resident's preference and is never billed.
- **A NO reply** marks the entry disputed, texts the security head and shows in the CSO view and the committee report.
- **One home PIN** for phone calls and the shuttle:
  - PIN (or HOUSE CODE) sends it to the number that asked.
  - NEW PIN sends a fresh random PIN to every number in the home, so a forged request learns nothing.
  - The admin can set one for a printed card.
  - The hash reaches every gate phone, shuttle or not.
- **Home PIN checks:** every check from a phone is an append-only `pin_checks` record, and a wrong try texts the home (at most 5 alerts an hour per home).
- **Committee report:** trust split for admitted and phone entries, by gate and by guard, plus disputes. The gate log and the Excel export show trust, the caller's masked number and disputes.
- **Fixed:** the usage report now decides "billed" per message kind, the same rule the allowance uses, instead of a fixed list of purposes.


## 8 November 2026: step 1 closed, tenant isolation enforced in CI

- `apps/api/tests/test_isolation.py` fills two estates through the real API until the second has rows in all 28 tenant tables, then checks three layers as the first estate:
  - **Catalogue:** every table with `estate_id` has RLS and a tenant policy, and the app role cannot bypass RLS. Any table without `estate_id` must be on a named platform list, so a new table cannot slip through.
  - **Database:** the app role sees none of the other estate's rows, cannot update them, and sees nothing when no estate is set.
  - **HTTP:** every GET route, called by every staff role, by an association user and by the gate phone, shows nothing of the other estate. Every route that takes an id answers 403 or 404 for the other estate's ids. The other estate's data is unchanged afterwards. New routes are picked up from the OpenAPI schema; new path parameters must be mapped or the test fails.
- One recorded exception: `staff_users` has `estate_id` but no RLS, because sign-in looks people up by email before any estate is known. Every request re-checks the account's estate.
- Fixed: a missing import batch now answers 404, not 409.
- `.github/workflows/ci.yml` runs on every push and pull request. It runs the isolation tests as their own step (a failure blocks merge), then the rest of the API tests, the gate phone's `flutter analyze` and `flutter test`, and the dashboard's type check and build.
- `CLAUDE.md` now carries the handoff's non-negotiables and gate phone UX rules.

## Before 8 November 2026 (commit a738d08)

API, gate phone app and dashboard for Phase 1:
- address register and import;
- signed codes, WhatsApp and SMS;
- offline sync, callbacks and walk-ins;
- guard, CSO and rider shifts with PIN and selfie;
- exits, nudges, the nightly rollup and the directory;
- messaging usage and organisations;
- the estate shuttle and the estate map.
