# Gatelog, notes for agents

- Monorepo: `apps/web` (Next.js 16, App Router) and `apps/api` (FastAPI). Postgres when persistence lands.
- Landing page copy lives only in `apps/web/content/copy.ts`.
- The product claims four things: WhatsApp for residents, six-digit codes signed per visit, offline verification at the gate, a four-level estate address model. Never add a claim beyond these.
- Dashboard numbers on the landing page are sample data and must stay labelled "Sample data".
- Do not regenerate or edit the images in `apps/web/public/images`; the screens were checked string by string.
- No em dashes in user-facing copy.
- Never log full phone numbers.
