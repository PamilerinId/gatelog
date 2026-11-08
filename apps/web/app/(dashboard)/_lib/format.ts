import type {
  ContactPref,
  DirectoryCategory,
  EntryMethod,
  ExitMethod,
  GuardRole,
  PlaceKind,
  Relation,
  RideConfirm,
  RideEventName,
  RideKind,
  RideSource,
  RideState,
  Role,
  SelfieState,
  ShiftEnd,
} from "./types";

// Plain-word labels and formatting shared by the dashboard pages. Estates are in Nigeria,
// so times are shown in Lagos time whatever the viewer's device says.

export const TZ = "Africa/Lagos";
export const TZ_OFFSET = "+01:00";

export const ENTRY_METHOD: Record<EntryMethod, string> = {
  code: "Code",
  phone_announced: "Phone announced",
  callback_confirmed: "Callback confirmed",
  walk_in_admitted: "Walk-in admitted",
  refused: "Refused",
};

export const EXIT_METHOD: Record<ExitMethod, string> = {
  code: "Code at the gate",
  list_tap: "Ticked off at the gate",
  resident_confirmed: "Resident confirmed",
  rollup_closed: "Missed, closed next morning",
};

export const ROLE: Record<Role, string> = {
  admin: "Estate admin",
  committee: "Committee",
  security_head: "Security head",
  treasurer: "Treasurer",
  org_admin: "Association admin",
  org_viewer: "Association",
  ops: "Gatelog ops",
};

export const GUARD_ROLE: Record<GuardRole, string> = { guard: "Guard", cso: "CSO", rider: "Shuttle rider" };

/** Roles that may see where the shuttle riders are (the API sends null to everyone else). */
export const POSITION_ROLES: readonly Role[] = ["admin", "committee", "security_head", "ops"];

export const PLACE_KIND: Record<PlaceKind, string> = { amenity: "Estate place", pickup: "Shuttle stop", post: "Security post" };

export const RIDE_KIND: Record<RideKind, string> = { resident: "Resident", delivery: "Delivery", guest: "Guest" };

export const RIDE_SOURCE: Record<RideSource, string> = {
  whatsapp: "WhatsApp",
  sms: "SMS",
  gate: "Booked at the gate",
  flag: "Flagged down",
  dispatch: "Booked by the CSO",
};

export const RIDE_STATE: Record<RideState, { label: string; tone: "ok" | "warn" | "bad" | "plain" | "info" }> = {
  requested: { label: "Waiting for a rider", tone: "warn" },
  accepted: { label: "Rider on the way", tone: "info" },
  picked_up: { label: "On board", tone: "info" },
  done: { label: "Done", tone: "ok" },
  cancelled: { label: "Cancelled", tone: "plain" },
  no_show: { label: "No show", tone: "bad" },
};

export const RIDE_CONFIRM: Record<RideConfirm | "not recorded", string> = {
  card: "Estate card",
  house_code: "House code",
  guard: "Vouched by the guard",
  rider: "Vouched by the rider",
  "not recorded": "Not recorded",
};

export const RIDE_EVENT: Record<RideEventName, string> = {
  accept: "Took the ride",
  release: "Handed it back to the queue",
  pick_up: "Picked up",
  drop_off: "Dropped off",
  cancel: "Cancelled",
  no_show: "Marked as a no show",
};

export const RELATION: Record<Relation, string> = { landlord: "Landlord", occupant: "Occupant" };

export const SHIFT_END: Record<ShiftEnd, string> = {
  handover: "Handed over",
  ended: "Ended, nobody took over",
  auto: "Closed after 14 hours",
};

export const SELFIE: Record<SelfieState, { label: string; tone: "ok" | "warn" | "plain" }> = {
  available: { label: "Available", tone: "ok" },
  pending: { label: "Pending upload", tone: "warn" },
  none: { label: "None taken", tone: "plain" },
  deleted: { label: "Deleted after 30 days", tone: "plain" },
};

export const CONTACT: Record<ContactPref, string> = { whatsapp: "WhatsApp", sms: "SMS", call: "Phone call" };

export const CATEGORY: Record<DirectoryCategory, string> = {
  estate: "Estate",
  crime: "Police and security",
  fire: "Fire",
  medical: "Medical",
  utilities: "Utilities",
};

const dateTime = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const dateOnly = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, day: "numeric", month: "short", year: "numeric" });
const timeOnly = new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit" });
const dayName = new Intl.DateTimeFormat("en-GB", { timeZone: "UTC", weekday: "short", day: "numeric", month: "short" });

export function fmtDateTime(iso: string | null | undefined) {
  return iso ? dateTime.format(new Date(iso)) : "";
}
export function fmtDate(iso: string | null | undefined) {
  return iso ? dateOnly.format(new Date(iso)) : "";
}
export function fmtTime(iso: string | null | undefined) {
  return iso ? timeOnly.format(new Date(iso)) : "";
}
/** A calendar date from the API ("2026-10-21") as "Wed 21 Oct". */
export function fmtDay(ymd: string) {
  return dayName.format(new Date(`${ymd}T12:00:00Z`));
}

const naira = new Intl.NumberFormat("en-NG", { style: "currency", currency: "NGN", maximumFractionDigits: 2 });
const count = new Intl.NumberFormat("en-GB");

export function fmtNaira(v: number) {
  return naira.format(v);
}
export function fmtCount(v: number) {
  return count.format(v);
}

/** "just now", "4 min ago", "2 h ago", or the date and time when older than a day. */
export function ago(iso: string | null | undefined, now = Date.now()) {
  if (!iso) return "";
  const mins = Math.floor((now - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  if (mins < 24 * 60) return `${Math.floor(mins / 60)} h ago`;
  return fmtDateTime(iso);
}

export function pct(v: number | null | undefined) {
  return v == null ? "No data yet" : `${Math.round(v * 100)}%`;
}

/** Today in Lagos as YYYY-MM-DD. */
export function todayLagos() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
}

/** This month in Lagos as YYYY-MM. */
export function thisMonthLagos() {
  return todayLagos().slice(0, 7);
}

/** "2026-11" as "November 2026". */
export function fmtMonth(ym: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: "UTC", month: "long", year: "numeric" }).format(new Date(`${ym}-15T12:00:00Z`));
}

export function addMonths(ym: string, months: number) {
  const d = new Date(`${ym}-15T12:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() + months);
  return d.toISOString().slice(0, 7);
}

export function addDays(ymd: string, days: number) {
  const d = new Date(`${ymd}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** "21:00:00" from the API as "21:00" for a time input. */
export function hhmm(t: string) {
  return t.slice(0, 5);
}

/** "21:00" as "9:00 pm". */
export function clock12(t: string) {
  const [h, m] = t.split(":").map(Number);
  const suffix = h >= 12 ? "pm" : "am";
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, "0")} ${suffix}`;
}
