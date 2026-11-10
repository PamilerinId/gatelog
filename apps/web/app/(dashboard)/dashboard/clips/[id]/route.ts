import type { NextRequest } from "next/server";
import { passMedia } from "@/app/(dashboard)/_lib/media";

// A visitor's name as the guard said it. Every play is audited by the API; no-store here.
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  return passMedia(req, id, { path: (x) => `/v1/admin/clips/${x}`, what: "voice clip", allowed: /^audio\//, fallbackType: "audio/mp4" });
}
