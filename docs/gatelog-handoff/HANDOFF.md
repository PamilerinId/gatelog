# Gatelog: handoff to Claude Code

Read this first, then `docs/PRODUCT_SPEC.md` (the full v1.0 spec) and `design/README.md` (the UI prototype). This file is the brief; the spec is the source of truth when they differ.

Living versions (owner: Pamilerin Idowu, PI Technologies Limited):
- Product spec: https://claude.ai/code/artifact/b414b374-5f65-41d5-85bf-5f9718b02e83
- Estate terms draft: https://claude.ai/artifact/NMLjoe8YFpueDMiHZm8doh
- UI prototype canvas: https://claude.ai/artifact/F9ZxBq9Ne8hp4FXkbuPixH
- SKA Exco pitch note: https://claude.ai/artifact/7u8vBCBzb2frEjA3SUZgeA

## What Gatelog is

Visitor access and estate safety for Nigerian gated estates and residents' associations. Residents never install an app: they use WhatsApp, SMS or a phone call. Guards use a Flutter Android app that works offline. The Exco (estate committee) and associations use a Next.js dashboard. First target estate: SKA residents' association, Ibadan, which resolved "No Call, No Entry" on 31 Oct 2026.

## Repo layout (monorepo, already started)

- `apps/web`: Next.js 16 App Router. Landing page exists. Add the Exco/association dashboard here.
- `apps/api`: FastAPI skeleton. All business logic lives here.
- `apps/guard`: NEW. Flutter, Android only (estate gate phones, Redmi-class devices, leased by Gatelog, locked down with Android Management API in dedicated-device mode).

## Stack (decided)

| Concern | Choice |
| --- | --- |
| API | FastAPI on Cloud Run (alert service as its own Cloud Run service, min 1 instance) |
| DB | Cloud SQL Postgres, one shared schema, `estate_id` on every tenant table, Row-Level Security (not schema-per-tenant) |
| Web | Next.js on Vercel |
| Guard app | Flutter, Android only, drift (SQLite) for offline store |
| SMS and voice | Termii (verify inbound missed-call caller ID early; Africa's Talking is the fallback) |
| WhatsApp | WhatsApp Cloud API direct with Meta, ONE number for the whole platform |
| Email | Postmark |
| Push | Firebase Cloud Messaging |
| Timers and jobs | Cloud Tasks (SOS escalation, retries), Cloud Scheduler (nightly rollup) |
| Secrets | Secret Manager (per-estate HMAC keys, provider credentials) |
| Errors | Sentry |
| Map | MapLibre with a licensed satellite tile source (Mapbox Satellite likely), max bounds locked to the estate polygon |

## Non-negotiables

1. **Tenant isolation is tested, not assumed.** CI runs every role against another estate's rows and must get zero. A failing isolation test blocks merge.
2. **Never log full phone numbers.** Mask to last 4 digits everywhere: logs, Sentry, analytics. Full numbers live only in `PhoneNumber` and `EmergencyContact`, encrypted at rest.
3. **WhatsApp routing is strict.** Inbound messages route by sender number to a registered home. Unregistered number: reply names no estate. Number on two homes: ask which home first. No default or "last used" estate, ever.
4. **Never gate access on dues.** Dues data is Exco-only. It never appears on the guard app, in guest codes, rollups or SOS. Gatelog never holds funds (payment links pay the association's own account).
5. **Offline first at the gate.** Code verification works with zero network. Entries and exits use client-generated IDs and sync idempotently (unique constraint).
6. **SOS escalation is durable.** Timers run on Cloud Tasks, never in-process. Escalation stops only when a person acknowledges.
7. **Guards decide nothing hard.** Judgement calls (description-only admission) go to the supervisor/CSO and are recorded with who decided.
8. **Claims discipline.** The landing page claims only what is live. Update the claims list in the same commit that ships a feature.
9. **Error first, resiliency first.** Every external call has a timeout, a retry policy and a logged failure path. No silent fallbacks that pretend success.
10. **No em dashes in user-facing copy.**

## Guard app UX rules (critical; guards may have low literacy)

- One job per screen. Big icons, big words, never paragraphs.
- Yes or No decisions, never a list of options.
- No typing: voice clip for visitor names, camera for car plates.
- Every result is read aloud (TTS): English first, Yoruba and Pidgin next.
- Home screen has the same three buttons, always in the same place: Visitor has code, Phone call, Visitor leaving.
- Start shift: tap your face, 4-digit PIN; selfie captured automatically (kept 30 days, no face recognition).
- Charcoal fabric background at night, sterile white by day. See `design/`.

## Build order (Phase 1, target 10 to 13 build-weeks)

Work in this order. Each step ends with tests passing and a short note in `docs/CHANGELOG.md`.

1. **Foundations**: Postgres schema for Organisation, Estate, Zone/Street/Home, Resident, PhoneNumber, Guard, Device, Gate (see spec "Data model"); RLS policies; isolation test harness in CI; Alembic migrations.
2. **Auth and tenancy**: Exco/admin web auth; guard device enrolment and per-guard PIN; org-level roles (association dashboard comes later but the `organisation_id` column and policies land now).
3. **Address register import**: CSV/Excel upload, staged review, commit; residents with up to 3 numbers; landlord-added occupants with SMS YES consent.
4. **Codes**: HMAC-derived six-digit codes per visit (validity window), verified offline on the device; key distribution and rotation on device revoke.
5. **Messaging core**: WhatsApp Cloud API webhook + Termii SMS, strict router, announce flow ("Tunde, today around 4, for 2 hours"), stay-length parsing with quick-reply fallback.
6. **Guard app v1**: start shift, home, code result (let in / no), visitor leaving, offline queue and sync.
7. **Call-the-gate**: callback to registered number, gate PIN (hashed, 3 tries), description-only via supervisor, "Not you? Reply NO" SMS on every unverified entry.
8. **Exits and nightly rollup**: overstay nudge to resident, 10pm rollup to security lead, morning close-out.
9. **Emergency directory**: estate tier (Exco-owned) and state tier (Gatelog ops, test-called before going live).
10. **Exco dashboard**: satellite map with gate, guard, SOS and entry markers; live log; status panel; trust levels; messaging usage tally; dues ledger (no custody, no gating).

Phase 1.5: event passes, recurring worker passes, shared-gate linking. Phase 2: SOS (after drills pass), IVR gate line, walkie-talkie TTS bridge (experiment).

## Open items you will hit

- Termii: confirm inbound missed-call caller ID on a local number before building SOS.
- WABA approval and template submission (utility category for dues statements).
- Satellite tile provider and licence for production.
- SKA's real coordinates and boundary polygon (prototype uses a sample Ibadan location).
- Counsel review of SOS terms and NDPA cross-border transfer basis.

## First task for Claude Code

1. Read this file, `docs/PRODUCT_SPEC.md`, `design/README.md`.
2. Merge the non-negotiables and guard UX rules into the repo's `CLAUDE.md`.
3. Propose a plan for build step 1 (schema, RLS, isolation tests) and wait for approval before writing code.
