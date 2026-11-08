"use server";

import { refresh } from "next/cache";
import { redirect } from "next/navigation";
import { apiRequest, type ApiResult } from "@/app/(dashboard)/_lib/api";
import { clearToken, getToken } from "@/app/(dashboard)/_lib/session";
import type { ActionState } from "@/app/(dashboard)/_lib/types";

// Every change made in the dashboard. Each action calls the API with the signed-in staff
// member's token, so the API decides who may do what (read-only roles get a 403).

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function str(fd: FormData, key: string) {
  const v = fd.get(key);
  return typeof v === "string" ? v.trim() : "";
}

function id(fd: FormData, key = "id") {
  const v = str(fd, key);
  if (!UUID_RE.test(v)) throw new Error(`bad ${key}`);
  return v;
}

function on(fd: FormData, key: string) {
  const v = fd.get(key);
  return v === "on" || v === "true";
}

function oneOf<T extends string>(fd: FormData, key: string, options: readonly T[], fallback: T): T {
  const v = str(fd, key);
  return (options as readonly string[]).includes(v) ? (v as T) : fallback;
}

const RELATIONS = ["landlord", "occupant"] as const;
const GUARD_ROLES = ["guard", "cso"] as const;

async function call<T>(method: string, path: string, json?: unknown): Promise<ApiResult<T>> {
  const token = await getToken();
  if (!token) redirect("/sign-in");
  const r = await apiRequest<T>(path, { method, json, token });
  if (!r.ok && r.status === 401) {
    await clearToken();
    redirect("/sign-in?expired=1");
  }
  return r;
}

async function act(method: string, path: string, json?: unknown, message?: string): Promise<ActionState> {
  const r = await call(method, path, json);
  if (!r.ok) return { ok: false, error: r.error };
  refresh();
  return { ok: true, message, data: r.data };
}

export async function signOut() {
  await clearToken();
  redirect("/sign-in");
}

// --- register ---------------------------------------------------------------------------

export async function createZone(fd: FormData) {
  return act("POST", "/v1/admin/zones", { name: str(fd, "name") }, "Zone added.");
}
export async function renameZone(fd: FormData) {
  return act("PATCH", `/v1/admin/zones/${id(fd)}`, { name: str(fd, "name") }, "Zone renamed.");
}
export async function deleteZone(fd: FormData) {
  return act("DELETE", `/v1/admin/zones/${id(fd)}`, undefined, "Zone deleted.");
}

export async function createStreet(fd: FormData) {
  return act("POST", "/v1/admin/streets", { zone_id: id(fd, "zone_id"), name: str(fd, "name") }, "Street added.");
}
export async function renameStreet(fd: FormData) {
  return act("PATCH", `/v1/admin/streets/${id(fd)}`, { name: str(fd, "name") }, "Street renamed.");
}
export async function deleteStreet(fd: FormData) {
  return act("DELETE", `/v1/admin/streets/${id(fd)}`, undefined, "Street deleted.");
}

export async function createHome(fd: FormData) {
  return act("POST", "/v1/admin/homes", { street_id: id(fd, "street_id"), label: str(fd, "label") }, "Home added.");
}
export async function renameHome(fd: FormData) {
  return act("PATCH", `/v1/admin/homes/${id(fd)}`, { label: str(fd, "label") }, "Home renamed.");
}
export async function setLevyPayer(fd: FormData) {
  return act("PATCH", `/v1/admin/homes/${id(fd)}`, { levy_payer: oneOf(fd, "levy_payer", RELATIONS, "occupant") }, "Saved.");
}

// --- vehicles ---------------------------------------------------------------------------

export async function createVehicle(fd: FormData) {
  const description = str(fd, "description");
  return act(
    "POST",
    `/v1/admin/homes/${id(fd, "home_id")}/vehicles`,
    { plate: str(fd, "plate"), description: description || null },
    "Vehicle added.",
  );
}
export async function deleteVehicle(fd: FormData) {
  return act("DELETE", `/v1/admin/vehicles/${id(fd)}`, undefined, "Vehicle removed.");
}
export async function deleteHome(fd: FormData) {
  const r = await call("DELETE", `/v1/admin/homes/${id(fd)}`);
  if (!r.ok) return { ok: false, error: r.error } satisfies ActionState;
  if (str(fd, "then") === "register") redirect("/dashboard/register");
  refresh();
  return { ok: true, message: "Home deleted." } satisfies ActionState;
}

// --- residents and numbers --------------------------------------------------------------

export async function createResident(fd: FormData) {
  const number = str(fd, "number");
  return act(
    "POST",
    "/v1/admin/residents",
    {
      home_id: id(fd, "home_id"),
      name: str(fd, "name"),
      relation: oneOf(fd, "relation", RELATIONS, "occupant"),
      contact_pref: str(fd, "contact_pref") || "whatsapp",
      callback_required: on(fd, "callback_required"),
      exit_notices: on(fd, "exit_notices"),
      numbers: number ? [number] : [],
    },
    "Resident added.",
  );
}

export async function updateResident(fd: FormData) {
  return act(
    "PATCH",
    `/v1/admin/residents/${id(fd)}`,
    {
      name: str(fd, "name"),
      relation: oneOf(fd, "relation", RELATIONS, "occupant"),
      contact_pref: str(fd, "contact_pref"),
      callback_required: on(fd, "callback_required"),
      exit_notices: on(fd, "exit_notices"),
      active: on(fd, "active"),
    },
    "Resident saved.",
  );
}

export async function addNumber(fd: FormData) {
  return act(
    "POST",
    `/v1/admin/residents/${id(fd, "resident_id")}/numbers`,
    { number: str(fd, "number"), is_primary: on(fd, "is_primary") },
    "Number added.",
  );
}

export async function deleteNumber(fd: FormData) {
  return act("DELETE", `/v1/admin/numbers/${id(fd)}`, undefined, "Number removed.");
}

// --- guards, gates, gate phones ---------------------------------------------------------

export async function createGuard(fd: FormData) {
  const role = oneOf(fd, "role", GUARD_ROLES, "guard");
  return act(
    "POST",
    "/v1/admin/guards",
    { name: str(fd, "name"), role, consent_recorded: on(fd, "consent_recorded") },
    role === "cso" ? "CSO added." : "Guard added.",
  );
}
export async function updateGuard(fd: FormData) {
  return act(
    "PATCH",
    `/v1/admin/guards/${id(fd)}`,
    { role: oneOf(fd, "role", GUARD_ROLES, "guard"), consent_recorded: on(fd, "consent_recorded") },
    "Saved.",
  );
}
export async function resetGuardPin(fd: FormData) {
  return act("POST", `/v1/admin/guards/${id(fd)}/reset-pin`, undefined, "PIN reset. They choose a new one at their next shift.");
}
export async function setGuardActive(fd: FormData) {
  const active = on(fd, "active");
  return act("PATCH", `/v1/admin/guards/${id(fd)}`, { active }, active ? "Guard reactivated." : "Guard deactivated.");
}
export async function createGate(fd: FormData) {
  return act("POST", "/v1/admin/gates", { name: str(fd, "name") }, "Gate added.");
}
export async function createDevice(fd: FormData) {
  return act("POST", "/v1/admin/devices", { gate_id: id(fd, "gate_id"), label: str(fd, "label") });
}
export async function newPairingCode(fd: FormData) {
  return act("POST", `/v1/admin/devices/${id(fd)}/pairing-code`);
}
export async function revokeDevice(fd: FormData) {
  return act("POST", `/v1/admin/devices/${id(fd)}/revoke`, undefined, "Phone revoked. It can no longer open the gate app.");
}

// --- emergency numbers ------------------------------------------------------------------

function directoryBody(fd: FormData) {
  const rank = Number(str(fd, "rank") || "100");
  return { category: str(fd, "category"), name: str(fd, "name"), number: str(fd, "number"), rank: Number.isFinite(rank) ? rank : 100 };
}
export async function createDirectoryEntry(fd: FormData) {
  return act("POST", "/v1/admin/directory", directoryBody(fd), "Number added.");
}
export async function updateDirectoryEntry(fd: FormData) {
  return act("PATCH", `/v1/admin/directory/${id(fd)}`, directoryBody(fd), "Number saved.");
}
export async function deleteDirectoryEntry(fd: FormData) {
  return act("DELETE", `/v1/admin/directory/${id(fd)}`, undefined, "Number deleted.");
}
export async function verifyDirectoryEntry(fd: FormData) {
  return act("POST", `/v1/admin/directory/${id(fd)}/verify`, { note: str(fd, "note") || null }, "Marked as verified today.");
}
export async function reportDirectoryEntry(fd: FormData): Promise<ActionState> {
  const r = await call<{ flagged: boolean }>("POST", `/v1/admin/directory/${id(fd)}/report`);
  if (!r.ok) return { ok: false, error: r.error };
  refresh();
  return {
    ok: true,
    message: r.data.flagged
      ? "Thanks. The number is now marked as not working and whoever looks after it has been asked to test it."
      : "Thanks, your report is saved. A second report from someone else marks the number as not working.",
  };
}

// --- imports ----------------------------------------------------------------------------

export async function commitImport(fd: FormData) {
  return act("POST", `/v1/admin/imports/${id(fd)}/commit`);
}
export async function discardImport(fd: FormData) {
  return act("POST", `/v1/admin/imports/${id(fd)}/discard`);
}

// --- staff and settings -----------------------------------------------------------------

export async function createStaff(fd: FormData) {
  const phone = str(fd, "phone");
  return act(
    "POST",
    "/v1/admin/staff",
    { email: str(fd, "email"), name: str(fd, "name"), role: str(fd, "role"), ...(phone ? { phone } : {}) },
    "Staff member added. They can sign in with their email.",
  );
}

export async function setStaffActive(fd: FormData) {
  const active = on(fd, "active");
  return act("PATCH", `/v1/admin/staff/${id(fd)}?active=${active}`, undefined, active ? "Access restored." : "Access removed.");
}

export async function updateMessageName(fd: FormData) {
  const name = str(fd, "short_name");
  return act("PATCH", "/v1/admin/estate", { short_name: name || null }, name ? "Message name saved." : "Message name cleared. Messages use the estate's full name.");
}

export async function updateSettings(fd: FormData) {
  const n = (k: string) => Number(str(fd, k));
  return act(
    "PATCH",
    "/v1/admin/estate/settings",
    {
      rollup_time: str(fd, "rollup_time"),
      handover_time: str(fd, "handover_time"),
      default_stay_until: str(fd, "default_stay_until"),
      code_valid_until: str(fd, "code_valid_until"),
      walk_in_policy: str(fd, "walk_in_policy"),
      daily_sms_budget: n("daily_sms_budget"),
      max_visits_per_home_per_day: n("max_visits_per_home_per_day"),
    },
    "Settings saved.",
  );
}
