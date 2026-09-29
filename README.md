# Gatelog

Visitor access for Nigerian estates. Residents clear guests on WhatsApp, guards verify a
six-digit signed code at the gate (offline if need be), and the estate keeps a record of
every entry.

```
apps/
  web/   Next.js 16 (App Router, TypeScript). Landing page now; estate dashboard next.
  api/   FastAPI. Demo-request intake now; the domain model next.
```

## Run it

```bash
# web
cd apps/web
npm install
npm run dev            # http://localhost:3000

# api
cd apps/api
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8000
pytest
```

The landing page's form posts to `/api/demo` in the web app, which validates, drops bots
(honeypot), rate-limits, and forwards to `POST {API_BASE_URL}/v1/demo-requests`. With
`API_BASE_URL` unset it logs and accepts, so the page works standalone in development.

| Variable | Where | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SITE_URL` | web | canonical URL for Open Graph images |
| `API_BASE_URL` | web | where demo requests are forwarded |
| `API_INTERNAL_TOKEN` | web + api | shared bearer token for server-to-server calls |
| `CORS_ORIGINS` | api | comma-separated allowed origins |
| `ENV` | api | `production` hides `/docs` |

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

**Motion: CSS only.** Scroll reveals use `animation-timeline: view()` behind
`@supports`, so browsers without it show everything static. All motion is off under
`prefers-reduced-motion`.

## Before launch

- [ ] **The API persists demo requests.** It currently logs and returns 202, so a lead that
      reaches production is only in the logs. First backend task: a `demo_requests` table
      plus a notification to the founders.
- [ ] Fill the placeholders in `apps/web/content/copy.ts`: contact email, WhatsApp number,
      response time, privacy link.
- [ ] Privacy notice (NDPA 2023): the form collects a name and phone number.
- [ ] Replace the dashboard's sample numbers once a pilot estate produces real ones. The
      "Sample data" label stays until then.

## Claims

The page claims exactly four things: residents use WhatsApp, codes are six-digit and signed
per visit, guards verify offline, entries are logged against a four-level estate address.
Do not add a capability to the copy that the product does not have.
