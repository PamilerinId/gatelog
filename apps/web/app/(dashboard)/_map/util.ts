import type { GateEntry } from "@/app/(dashboard)/_lib/types";

/** Where the editor opens before an estate has a boundary. Set per deployment; the admin can
 * also type the estate's coordinates in the editor. */
export const DEFAULT_CENTER: [number, number] = (() => {
  const raw = (process.env.NEXT_PUBLIC_MAP_DEFAULT_CENTER ?? "3.385,6.615").split(",").map(Number);
  return raw.length === 2 && raw.every(Number.isFinite) ? [raw[0], raw[1]] : [3.385, 6.615];
})();

export function absolute(url: string) {
  return new URL(url, window.location.origin).href;
}

/** "Musa Ibrahim" as "MUSA I.", the way the design labels people on the map. */
export function shortName(name: string) {
  const parts = name.trim().split(/\s+/);
  if (parts.length < 2) return name.toUpperCase();
  return `${parts[0]} ${parts[parts.length - 1][0]}.`.toUpperCase();
}

/** "4 MIN", "3 H", "2 D" since a time. */
export function minutesSince(iso: string, now = Date.now()) {
  const m = Math.max(0, Math.floor((now - Date.parse(iso)) / 60000));
  if (m < 60) return `${m} MIN`;
  if (m < 48 * 60) return `${Math.floor(m / 60)} H`;
  return `${Math.floor(m / 1440)} D`;
}

/** Minutes waited as "14 MIN", "3 H" or "2 D". */
export function waitLabel(minutes: number) {
  if (minutes < 60) return `${minutes} MIN`;
  if (minutes < 48 * 60) return `${Math.floor(minutes / 60)} H`;
  return `${Math.floor(minutes / 1440)} D`;
}

// --- trust -----------------------------------------------------------------------------------

export type Trust = "verified" | "pin" | "unverified";

/** The API's trust level for an admitted entry, in the design's three buckets. Null for refusals. */
export function trustOf(e: Pick<GateEntry, "trust">): Trust | null {
  if (!e.trust) return null;
  return e.trust === "pin_verified" ? "pin" : e.trust;
}
