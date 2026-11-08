# Changelog

One short note per build step, newest first. The product rules are in `docs/spec.md`.

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
- **Not yet (step 2b):** registering a resident's new number after a confirmed callback.

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
