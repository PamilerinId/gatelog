import "server-only";

import { redirect } from "next/navigation";
import { cache } from "react";
import { getToken } from "./session";
import type { Estate, EstateMapData, Me } from "./types";

// Every dashboard call to the Gatelog API goes through here, on the server, with the
// staff token from the httpOnly cookie. The browser never sees the token.

export type ApiResult<T> = { ok: true; status: number; data: T } | { ok: false; status: number; error: string };

export function apiBase(): string {
  const base = process.env.API_BASE_URL ?? (process.env.NODE_ENV === "production" ? "" : "http://localhost:8000");
  return base.replace(/\/$/, "");
}

type Init = { method?: string; json?: unknown; form?: FormData; token?: string | null; timeoutMs?: number };

export async function apiRequest<T>(path: string, init: Init = {}): Promise<ApiResult<T>> {
  const base = apiBase();
  if (!base) return { ok: false, status: 503, error: "The dashboard is not connected to the Gatelog server yet." };
  const headers: Record<string, string> = { Accept: "application/json" };
  if (init.token) headers.Authorization = `Bearer ${init.token}`;
  let body: BodyInit | undefined;
  if (init.form) body = init.form;
  else if (init.json !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(init.json);
  }
  const method = init.method ?? "GET";
  const send = () =>
    fetch(`${base}${path}`, { method, headers, body, cache: "no-store", signal: AbortSignal.timeout(init.timeoutMs ?? 15000) });
  const causeOf = (err: unknown) => (err instanceof Error ? ((err.cause as { code?: string } | undefined)?.code ?? err.name) : "unknown");
  let res: Response;
  try {
    try {
      res = await send();
    } catch (err) {
      // A kept-alive connection the API closed a moment ago fails at once with ECONNRESET.
      // A GET is safe to send again, once; a change is never repeated behind the user's back.
      if (method !== "GET" || !["ECONNRESET", "UND_ERR_SOCKET", "EPIPE"].includes(causeOf(err))) throw err;
      res = await send();
    }
  } catch (err) {
    // Logged with the path and the cause only: no token, no body.
    console.error(`api ${method} ${path.split("?")[0]} failed: ${causeOf(err)}`);
    return { ok: false, status: 0, error: "We could not reach the Gatelog server. Check your connection and try again." };
  }
  if (res.status === 204) return { ok: true, status: 204, data: null as T };
  let payload: unknown = null;
  try {
    payload = await res.json();
  } catch {
    payload = null;
  }
  if (res.ok) return { ok: true, status: res.status, data: payload as T };
  return { ok: false, status: res.status, error: errorMessage(res.status, payload) };
}

function sentence(s: string) {
  const t = s.trim().replace(/^Value error, /, "");
  return t ? t[0].toUpperCase() + t.slice(1) : t;
}

const FIELD_NAMES: Record<string, string> = {
  name: "Name",
  label: "Label",
  email: "Email",
  number: "Number",
  numbers: "Numbers",
  code: "Code",
  rank: "Order",
  daily_sms_budget: "Daily SMS budget",
  max_visits_per_home_per_day: "Visits per home per day",
  walk_in_policy: "Walk-in rule",
  plate: "Plate",
  description: "Description",
  short_name: "Message name",
  max_rides_per_home_per_day: "Rides per home per day",
  ring: "Boundary",
  kind: "Kind",
  lat: "Position",
  lng: "Position",
};

export function errorMessage(status: number, payload: unknown): string {
  const detail = (payload as { detail?: unknown } | null)?.detail;
  if (typeof detail === "string") {
    if (detail === "not allowed for your role") return "Your role can view this but not change it. Ask an estate admin.";
    if (detail === "unauthorised") return "Please sign in again.";
    return sentence(detail);
  }
  if (Array.isArray(detail)) {
    const parts = detail.map((d: { loc?: unknown[]; msg?: string }) => {
      const field = Array.isArray(d.loc) ? String(d.loc[d.loc.length - 1] ?? "") : "";
      const label = FIELD_NAMES[field] ?? "";
      return `${label ? `${label}: ` : ""}${sentence(d.msg ?? "is not valid")}`;
    });
    return parts.join(". ");
  }
  if (status === 403) return "Your role can view this but not change it.";
  if (status === 404) return "That item no longer exists. It may have been removed.";
  if (status === 429) return "Too many attempts. Wait a while and try again.";
  if (status >= 500) return "Something went wrong on the Gatelog server. Try again in a moment.";
  return "That did not work. Check the details and try again.";
}

/** For Server Components: sends signed-out or expired sessions back to sign-in. */
export async function load<T>(path: string): Promise<ApiResult<T>> {
  const token = await getToken();
  if (!token) redirect("/sign-in");
  const r = await apiRequest<T>(path, { token });
  // Cookies can only be cleared in a Route Handler or Server Action, so hand over to one.
  if (!r.ok && r.status === 401) redirect("/sign-out?expired=1");
  return r;
}

/** The signed-in staff member, once per request. */
export const getMe = cache(async (): Promise<Me> => {
  const r = await load<Me>("/v1/auth/me");
  if (!r.ok) throw new Error(r.error);
  return r.data;
});

/** The estate map (boundary, gates, places, pinned homes), once per request. */
export const getMap = cache(() => load<EstateMapData>("/v1/admin/map"));

/** The estate and its settings, once per request. */
export const getEstate = cache(() => load<Estate>("/v1/admin/estate"));
