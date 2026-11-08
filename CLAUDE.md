# Gatelog, notes for agents

- Monorepo: `apps/web` (Next.js 16, App Router: landing page and the Exco dashboard under `app/(dashboard)`), `apps/api` (FastAPI, Postgres with row-level security, Alembic), `apps/guard` (Flutter, Android only, the gate phone).
- Product rules: `docs/spec.md` (working copy, change it in the same commit as the behaviour). Design handoff: `docs/gatelog-handoff/` (HANDOFF.md, design/ for UI). Gate phone and API contract: `docs/guard-app-contract.md`.

## Landing page

- Landing page copy lives only in `apps/web/content/copy.ts`.
- The product claims four things: WhatsApp for residents, six-digit codes signed per visit, offline verification at the gate, a four-level estate address model. Never add a claim beyond these. Update this list in the same commit that ships a feature to a live estate.
- Dashboard numbers on the landing page are sample data and must stay labelled "Sample data".
- Do not regenerate or edit the images in `apps/web/public/images`; the screens were checked string by string.
- Animation uses Motion via `m.*` inside `MotionProvider` (LazyMotion strict). Do not import `motion.*` components.
- The "Try it" demo accepts only the code 482917 and runs entirely in the browser; keep it labelled as a demo.

## Non-negotiables

1. **Tenant isolation is tested, not assumed.** Every tenant table has `estate_id` and RLS. Tests run every role against another estate's rows and must get zero. A failing isolation test blocks merge.
2. **Never log full phone numbers.** Last 4 digits everywhere: logs, Sentry, analytics. Full numbers live only in `PhoneNumber` and `EmergencyContact`, encrypted at rest.
3. **WhatsApp routing is strict.** Route by sender number to a registered home. Unregistered number: the reply names no estate. Number on two homes: ask which home first. Never a default or "last used" estate.
4. **Never gate access on dues.** Dues data is Exco-only: never on the gate phone, in guest codes, rollups or SOS. Gatelog never holds funds.
5. **Offline first at the gate.** Code verification and shift start work with zero network. Records use client-generated IDs and sync idempotently.
6. **SOS escalation is durable.** Timers run on Cloud Tasks, never in-process. Escalation stops only when a person acknowledges.
7. **Guards decide nothing hard.** Judgement calls (description-only admission) go to the supervisor or CSO and are recorded with who decided and why.
8. **Every action is audited or seen by a second person.** Dashboard and ops writes go to `audit_events`; phone actions are append-only records with the person and shift; decisions that affect a home also notify the home. If an action has neither, it is a bug.
9. **Error first, resiliency first.** Every external call has a timeout, a retry policy and a logged failure path. No silent fallbacks that pretend success.
10. **No em dashes in user-facing copy.**

## Gate phone UX (guards may have low literacy)

- One job per screen. Big icons, big words, never paragraphs. Touch targets at least 56px.
- Yes or No decisions, never a list of options.
- No typing: voice clip for visitor names, camera for car plates.
- Every result is read aloud (TTS): English first, Yoruba and Pidgin next.
- Home screen: the same three buttons, always in the same place: Visitor has code, Phone call, Visitor leaving. Emergency numbers below them.
- Start shift: tap your face, then PIN; the selfie is captured automatically (kept 30 days, no face recognition).
- Charcoal `#111111` with the fabric twill at night, `#F2F2F0` by day. Colour only for markers and states. Inter for UI, JetBrains Mono for data. Tokens in `docs/gatelog-handoff/design/README.md`.

## Working in this repo

- The app clock (`apps/api/app/clock.py`) is the only time source for anything logic compares; never mix it with the database's `now()`.
- Migrations: autogenerate misses CHECK constraint changes, RLS policies and grants; add them by hand (see 0002 and 0004).
- Bash heredocs are unreliable here: write helper scripts to a scratch file and run them.
