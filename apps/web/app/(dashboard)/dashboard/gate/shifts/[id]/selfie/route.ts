import { NextResponse, type NextRequest } from "next/server";
import { apiBase } from "@/app/(dashboard)/_lib/api";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// Passes one shift selfie from the API to the browser. The staff token stays on the server,
// the API decides who may see it (estate admin and security head) and audits every view, and
// nothing along the way may keep a copy.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NO_STORE = { "Cache-Control": "no-store, private", Pragma: "no-cache", "X-Content-Type-Options": "nosniff" };

function text(message: string, status: number) {
  return new NextResponse(message, { status, headers: { ...NO_STORE, "Content-Type": "text/plain; charset=utf-8" } });
}

export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return text("Please sign in again.", 401);

  const { id } = await ctx.params;
  if (!UUID_RE.test(id)) return text("No such shift.", 404);

  let res: Response;
  try {
    res = await fetch(`${apiBase()}/v1/admin/shifts/${id}/selfie`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    return text("We could not reach the Gatelog server.", 502);
  }
  if (res.status === 401) return text("Please sign in again.", 401);
  if (res.status === 403) return text("Only an estate admin or the security head can view selfies.", 403);
  if (!res.ok || !res.body) return text("No selfie for this shift.", res.status === 404 ? 404 : 502);

  return new NextResponse(res.body, {
    headers: { ...NO_STORE, "Content-Type": "image/jpeg", "Content-Disposition": "inline" },
  });
}
