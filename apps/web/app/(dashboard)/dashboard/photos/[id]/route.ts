import type { NextRequest } from "next/server";
import { passMedia } from "@/app/(dashboard)/_lib/media";

// A visitor or plate photo taken at the gate. Every view is audited by the API; no-store here.
export async function GET(req: NextRequest, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  return passMedia(req, id, { path: (x) => `/v1/admin/photos/${x}`, what: "gate photo", allowed: /^image\/jpeg$/, fallbackType: "image/jpeg" });
}
