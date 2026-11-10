import { NextResponse, type NextRequest } from "next/server";
import { apiBase } from "@/app/(dashboard)/_lib/api";
import { TZ_OFFSET, todayLagos } from "@/app/(dashboard)/_lib/format";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// The live map polls this every 10 seconds. It passes /v1/admin/live through with the staff
// token from the httpOnly cookie, so the browser never holds the token, and adds today's
// entries (for the live log and the trust bar), today's summary (exits confirmed) and the guests
// inside now (for overdue guests). The API
// decides what each role sees: rider positions are null for roles that may not see them.
// A single combined endpoint in the API would save two calls per poll.
const NO_STORE = { "Cache-Control": "no-store, private", Pragma: "no-cache", "X-Content-Type-Options": "nosniff" };
const LOG_LIMIT = 500;

function fail(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

export async function GET(req: NextRequest) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return fail("Please sign in again.", 401);
  const base = apiBase();
  if (!base) return fail("The dashboard is not connected to the Gatelog server yet.", 503);

  const since = `${todayLagos()}T00:00:00${TZ_OFFSET}`;
  const get = (path: string) =>
    fetch(`${base}${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });

  const [live, log, today, inside] = await Promise.allSettled([
    get("/v1/admin/live"),
    get(`/v1/admin/entries?${new URLSearchParams({ since, limit: String(LOG_LIMIT) })}`),
    get(`/v1/reports/summary?${new URLSearchParams({ since })}`),
    get("/v1/admin/visits?state=inside"),
  ]);
  if (live.status === "rejected") return fail("We could not reach the Gatelog server.", 502);
  if (live.value.status === 401) return fail("Please sign in again.", 401);
  if (!live.value.ok) return fail("The live map could not be updated.", live.value.status === 403 ? 403 : 502);

  const extra = async (r: PromiseSettledResult<Response>) => {
    if (r.status === "rejected" || !r.value.ok) return null;
    return r.value.json().catch(() => null);
  };
  const body = { ...(await live.value.json()), log: await extra(log), today: await extra(today), inside: await extra(inside) };
  return NextResponse.json(body, { headers: NO_STORE });
}
