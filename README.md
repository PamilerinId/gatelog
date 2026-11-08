# Gatelog

Visitor access for Nigerian estates. Residents clear guests on WhatsApp, guards verify a
six-digit signed code at the gate (offline if need be), and the estate keeps a record of
every entry.

```
apps/
  web/    Next.js 16 (App Router, TypeScript). Landing page and the estate dashboard.
  api/    FastAPI on Postgres. Codes, visits, the gate log, messaging, rollups, directory.
  guard/  Flutter (Android). The gate phone app; works offline.
docs/
  guard-app-contract.md   what the gate phone and the API agree on
  code-test-vectors.json  pins the six-digit code algorithm for Python and Dart
  whatsapp-templates.md   templates to submit to Meta
```

Spec: Gatelog Product Spec v1.0 (Oct 2026). Phase 1 is built here: core gate flow with
offline sync, visit length with exits and the nightly rollup, call-the-gate (callback flows A
and B), the emergency directory, and the admin dashboard. SOS (Phase 2) is not.

## Run it

```bash
# web
cd apps/web
npm install
npm run dev            # http://localhost:3000

# api (Postgres in Docker on port 54329)
docker compose up -d
cd apps/api
python -m venv .venv && .venv/Scripts/pip install -r requirements-dev.txt   # bin/ on macOS/Linux
.venv/Scripts/alembic upgrade head
.venv/Scripts/uvicorn app.main:app --reload --port 8000                      # /docs for the API
.venv/Scripts/python -m pytest                                               # uses the gatelog_test database
```

## How the API fits together

- **Tenancy.** Every tenant table has `estate_id` and a Row-Level Security policy. The API
  connects as `gatelog_app`, which owns nothing, so the policies always apply; migrations run
  as the owner. Each request sets `app.estate_id` for its transaction. Two narrow
  `SECURITY DEFINER` functions answer the only cross-tenant questions: which resident owns
  this phone number (inbound messages), and which device has this pairing code.
- **Codes.** `HMAC-SHA256(estate key, home|visit|window)`, truncated to six digits
  (`app/codes.py`). The gate phone holds the key and the expected visits and recomputes codes
  offline. Revoking a lost phone moves the estate to a new key version.
- **Offline sync.** Entries, exits, callbacks and phone-announced visits carry client UUIDs;
  the server inserts `ON CONFLICT DO NOTHING` and runs side effects only for new rows.
- **Messages.** Queued in an outbox in the same transaction as the change, sent after commit,
  retried by the scheduler. Full numbers live only in `phone_numbers`, encrypted, with a keyed
  blind index for lookups; logs and every other table carry the last four digits.
- **Scheduled work.** Cloud Scheduler calls `POST /internal/jobs/tick` every 5 minutes:
  overstay nudges, the nightly rollup, the morning handover, message retries. Each step is
  idempotent, so a missed or doubled tick is harmless.

## Abuse controls (WhatsApp, SMS, public endpoints)

`app/abuse.py` holds the limits; counters live in Postgres because Cloud Run runs several
instances.

| Threat | Control |
|---|---|
| SMS pumping | Outbound only to numbers an admin registered. No SMS reply to unregistered senders; WhatsApp gets one reply a day each, with a global ceiling. Per-estate daily SMS budget (default 500): over it, messages are held and ops are emailed. Ops release or drop them at `/v1/ops/messages/held` |
| Spoofed or flooding senders | Inbound capped per sender (20 per 10 minutes, 100 a day), dropped silently. Visits capped per home per day (default 30). Outbound capped at 60 a day per number |
| Webhook replays | WhatsApp signature checked; provider message IDs remembered for a week; SMS webhook behind a path secret; payloads capped at 256 KB |
| Brute force | Sign-in codes: 5 per email and 30 per IP an hour, 5 tries per code. Pairing: 10 per IP an hour |
| Directory griefing | A number is flagged only after two different people report it |

The landing page's form posts to `/api/demo` in the web app, which validates, drops bots
(honeypot), rate-limits, then delivers the lead: to `POST {API_BASE_URL}/v1/demo-requests`
if set, otherwise by email through Postmark. In production with neither configured it
refuses the request (503) rather than accept a lead it would lose. In development it logs.

## Deploy the landing page (Vercel)

Import the GitHub repo in Vercel with:

- **Root Directory:** `apps/web` (framework detected as Next.js; build and output defaults are fine)
- **Environment variables (Production):** `NEXT_PUBLIC_SITE_URL` = the production URL,
  plus either `POSTMARK_SERVER_TOKEN`, `LEADS_EMAIL_FROM`, `LEADS_EMAIL_TO` (a Postmark
  sender signature must exist for the From address) or `API_BASE_URL` once the API is up.
- Region: an EU region, next to the API in `europe-west1`.

Without lead delivery configured the form shows an error in production. That is deliberate.

| Variable | Where | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SITE_URL` | web | canonical URL for Open Graph images |
| `API_BASE_URL` | web | where demo requests are forwarded |
| `API_INTERNAL_TOKEN` | web + api | shared bearer token for server-to-server calls |
| `POSTMARK_SERVER_TOKEN`, `LEADS_EMAIL_FROM`, `LEADS_EMAIL_TO` | web | email delivery of demo requests until the API stores them |
| `CORS_ORIGINS` | api | comma-separated allowed origins |
| `ENV` | api | `production` hides `/docs` and refuses development secrets |
| others | api | see `apps/api/.env.example` |

## Decisions

**Database: Postgres, not Mongo.** The data is relational by nature: estate, then block,
street and home (the four-level address), residents who belong to homes, visits raised by
residents, codes tied to visits, entries tied to codes and gates. The questions the
committee asks are joins ("every entry for 14B last month, and who approved it"). Offline
sync needs idempotent inserts keyed on a client-generated entry ID, which is a unique
constraint, not application code. Multi-estate isolation uses the same Row-Level Security
pattern as System A, so one set of habits covers both products. Mongo would save nothing at
this size and would move integrity into code.

On cost: the smallest shared-core Cloud SQL Postgres instance is a small fixed monthly
charge; confirm the current figure in the GCP pricing calculator for `europe-west1`. If
that is too much before the first paying estate, start on a serverless Postgres free tier
and move to Cloud SQL at launch; the schema does not change.

**Styling: one stylesheet, CSS custom properties as tokens.** The page is a handful of
bespoke glass components; a utility framework would add a build dependency without
reducing code. Revisit when the dashboard brings real component reuse.

**Motion: Motion (formerly Framer Motion), loaded through `LazyMotion`.** Every animated
component uses `m.*` inside `components/motion/MotionProvider.tsx`, which also sets
`reducedMotion="user"` so the OS setting turns transforms off. Keep new animation inside
that provider; importing `motion.*` directly breaks the strict lazy-loading.

## Before launch

- [ ] **Lead delivery configured on Vercel** (Postmark variables above), and one real test
      submission received.
- [ ] The API persists demo requests. It logs and returns 202 today.
- [ ] Termii: sender ID registered (weeks of lead time); inbound SMS webhook pointed at
      `/v1/webhooks/sms/<SMS_WEBHOOK_SECRET>`; confirm its payload field names match
      `routers/webhooks.py`.
- [ ] WhatsApp: templates in `docs/whatsapp-templates.md` approved; webhook verified.
- [ ] Cloud Scheduler job: `POST /internal/jobs/tick` every 5 minutes with the internal token.
- [ ] Secrets in Secret Manager: token secret, phone encryption and index keys, estate keys.
- [ ] Fill the placeholders in `apps/web/content/copy.ts`: contact email, WhatsApp number,
      response time, privacy link.
- [ ] Privacy notice (NDPA 2023): the form collects a name and phone number.
- [ ] Replace the dashboard's sample numbers once a pilot estate produces real ones. The
      "Sample data" label stays until then.

## Claims

The page claims exactly four things: residents use WhatsApp, codes are six-digit and signed
per visit, guards verify offline, entries are logged against a four-level estate address.
Do not add a capability to the copy that the product does not have.
