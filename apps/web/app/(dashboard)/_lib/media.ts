import "server-only";

import { NextResponse, type NextRequest } from "next/server";
import { apiBase } from "./api";
import { SESSION_COOKIE } from "./session";

// Passes one audited media file (a voice clip or a gate photo) from the API to the browser. The
// staff token stays on the server, the API decides who may have it (estate admin and security
// head) and records every play or view, and nothing along the way may keep a copy.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NO_STORE = { "Cache-Control": "no-store, private", Pragma: "no-cache", "X-Content-Type-Options": "nosniff" };

function text(message: string, status: number) {
  return new NextResponse(message, { status, headers: { ...NO_STORE, "Content-Type": "text/plain; charset=utf-8" } });
}

export async function passMedia(
  req: NextRequest,
  id: string,
  opts: { path: (id: string) => string; what: string; allowed: RegExp; fallbackType: string },
) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return text("Please sign in again.", 401);
  if (!UUID_RE.test(id)) return text(`No such ${opts.what}.`, 404);

  let res: Response;
  try {
    res = await fetch(`${apiBase()}${opts.path(id)}`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    return text("We could not reach the Gatelog server.", 502);
  }
  if (res.status === 401) return text("Please sign in again.", 401);
  if (res.status === 403) return text(`Only an estate admin or the security head can open a ${opts.what}.`, 403);
  if (!res.ok || !res.body) return text(`This ${opts.what} is not available.`, res.status === 404 ? 404 : 502);

  const type = res.headers.get("content-type") ?? "";
  return new NextResponse(res.body, {
    headers: { ...NO_STORE, "Content-Type": opts.allowed.test(type) ? type : opts.fallbackType, "Content-Disposition": "inline" },
  });
}
