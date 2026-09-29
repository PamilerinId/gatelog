import { NextResponse } from "next/server";

// Demo requests: validate, drop bots, rate-limit, then hand off to the API.
// If API_BASE_URL is unset (local dev), the request is logged and accepted.

type Body = { name?: unknown; estate?: unknown; phone?: unknown; website?: unknown };

const WINDOW_MS = 10 * 60 * 1000;
const MAX_PER_WINDOW = 5;
const hits = new Map<string, number[]>(); // per-instance; good enough in front of the API's own limit

function limited(ip: string) {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > MAX_PER_WINDOW;
}

function clean(v: unknown, max: number) {
  return typeof v === "string" ? v.trim().slice(0, max) : "";
}

export async function POST(req: Request) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  if (limited(ip)) {
    return NextResponse.json({ error: "Too many requests. Please try again in a few minutes." }, { status: 429 });
  }

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: "Invalid request." }, { status: 400 });
  }

  // Honeypot: real people never fill this. Pretend success.
  if (clean(body.website, 200)) return NextResponse.json({ ok: true });

  const name = clean(body.name, 120);
  const estate = clean(body.estate, 160);
  const phone = clean(body.phone, 32).replace(/[\s-]/g, "");

  if (name.length < 2 || estate.length < 2 || !/^(\+?234|0)\d{10}$/.test(phone)) {
    return NextResponse.json({ error: "Please check the form and try again." }, { status: 422 });
  }

  const api = process.env.API_BASE_URL;
  if (!api) {
    console.info("[demo-request]", { estate, phone: `***${phone.slice(-4)}` });
    return NextResponse.json({ ok: true });
  }

  try {
    const res = await fetch(`${api.replace(/\/$/, "")}/v1/demo-requests`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(process.env.API_INTERNAL_TOKEN ? { Authorization: `Bearer ${process.env.API_INTERNAL_TOKEN}` } : {}),
      },
      body: JSON.stringify({ name, estate, phone, source: "landing" }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`API ${res.status}`);
    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("[demo-request] forward failed", err);
    return NextResponse.json({ error: "We couldn’t send that just now. Please try again, or message us on WhatsApp." }, { status: 502 });
  }
}
