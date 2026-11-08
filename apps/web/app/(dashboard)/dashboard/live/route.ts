import { NextResponse, type NextRequest } from "next/server";
import { apiBase } from "@/app/(dashboard)/_lib/api";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// The live map polls this every 10 seconds. It passes /v1/admin/live through with the staff
// token from the httpOnly cookie, so the browser never holds the token. The API decides what
// each role sees (rider positions are null for roles that may not see them).
const NO_STORE = { "Cache-Control": "no-store, private", Pragma: "no-cache", "X-Content-Type-Options": "nosniff" };

function fail(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

export async function GET(req: NextRequest) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return fail("Please sign in again.", 401);
  const base = apiBase();
  if (!base) return fail("The dashboard is not connected to the Gatelog server yet.", 503);

  let res: Response;
  try {
    res = await fetch(`${base}/v1/admin/live`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    return fail("We could not reach the Gatelog server.", 502);
  }
  if (res.status === 401) return fail("Please sign in again.", 401);
  if (!res.ok) return fail("The live map could not be updated.", res.status === 403 ? 403 : 502);
  return NextResponse.json(await res.json(), { headers: NO_STORE });
}
