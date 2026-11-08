import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// Server Components cannot clear cookies, so an expired session is sent here first.
export function GET(req: NextRequest) {
  const expired = req.nextUrl.searchParams.get("expired") === "1";
  const res = NextResponse.redirect(new URL(expired ? "/sign-in?expired=1" : "/sign-in", req.url));
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
