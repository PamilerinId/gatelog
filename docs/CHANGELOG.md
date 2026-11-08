# Changelog

One short note per build step, newest first. The product rules are in `docs/spec.md`.

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
