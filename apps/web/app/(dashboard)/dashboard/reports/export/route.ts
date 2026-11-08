import { NextResponse, type NextRequest } from "next/server";
import { apiBase } from "@/app/(dashboard)/_lib/api";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// Streams the API's Excel export to the browser so the staff token stays on the server.
export async function GET(req: NextRequest) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return NextResponse.redirect(new URL("/sign-in", req.url));

  const view = req.nextUrl.searchParams.get("view") === "summary" ? "summary" : "entries";
  const days = Math.min(Math.max(Number(req.nextUrl.searchParams.get("days")) || 30, 1), 366);
  const since = new Date(Date.now() - days * 86_400_000).toISOString();
  const q = new URLSearchParams({ view, since });

  let res: Response;
  try {
    res = await fetch(`${apiBase()}/v1/reports/export.xlsx?${q}`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store",
      signal: AbortSignal.timeout(60000),
    });
  } catch {
    return new NextResponse("We could not reach the Gatelog server. Go back and try again.", { status: 502, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  if (res.status === 401) return NextResponse.redirect(new URL("/sign-out?expired=1", req.url));
  if (!res.ok || !res.body) {
    return new NextResponse("The export did not work. Go back and try again.", { status: res.status || 502, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  return new NextResponse(res.body, {
    headers: {
      "Content-Type": res.headers.get("Content-Type") ?? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": res.headers.get("Content-Disposition") ?? `attachment; filename="gatelog-${view}.xlsx"`,
      "Cache-Control": "no-store",
    },
  });
}
