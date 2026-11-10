import { NextResponse, type NextRequest } from "next/server";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// Google Map Tiles API: creates the satellite tile session on the server, with a key the browser
// never sees (GOOGLE_MAPS_SERVER_KEY). The browser then fetches tiles with the session and its
// own referrer-restricted key, because Google requires a key on every tile request.
// Only signed-in dashboard users can ask for a session. One session is shared until shortly
// before Google expires it (sessions last about two weeks).

const NO_STORE = { "Cache-Control": "no-store, private", "X-Content-Type-Options": "nosniff" };
const RENEW_BEFORE_MS = 24 * 3_600_000;

type Created = { session: string; expiry: string; tileWidth: number; tileHeight: number; imageFormat: string };
let cached: { session: string; expiry: number; tileWidth: number; imageFormat: string } | null = null;

function fail(message: string, status: number) {
  return NextResponse.json({ error: message }, { status, headers: NO_STORE });
}

export async function GET(req: NextRequest) {
  if (!req.cookies.get(SESSION_COOKIE)?.value) return fail("Please sign in again.", 401);
  if (process.env.NEXT_PUBLIC_MAP_PROVIDER !== "google") return fail("The map does not use Google imagery.", 404);
  const key = process.env.GOOGLE_MAPS_SERVER_KEY;
  if (!key) return fail("Satellite imagery is not set up on this server.", 503);

  if (cached && cached.expiry - Date.now() > RENEW_BEFORE_MS) return NextResponse.json(cached, { headers: NO_STORE });

  let res: Response;
  try {
    res = await fetch(`https://tile.googleapis.com/v1/createSession?key=${encodeURIComponent(key)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mapType: "satellite", language: "en-GB", region: "NG", scale: "scaleFactor2x", highDpi: true }),
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    return fail("We could not reach Google for the satellite imagery.", 502);
  }
  if (!res.ok) {
    // Logged without the key: the status and Google's reason are enough to fix the setup.
    const reason = await res.text().catch(() => "");
    console.error(`map-session: Google createSession failed ${res.status} ${reason.slice(0, 300)}`);
    return fail("Satellite imagery is not available right now.", 502);
  }
  const s = (await res.json()) as Created;
  // Google sends the expiry as seconds since the epoch, as a string.
  cached = { session: s.session, expiry: Number(s.expiry) * 1000, tileWidth: s.tileWidth, imageFormat: s.imageFormat };
  return NextResponse.json(cached, { headers: NO_STORE });
}
