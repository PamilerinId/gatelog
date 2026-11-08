import type { Sun } from "@/app/(dashboard)/_lib/types";

// Day and night for the map and the dashboard's colours. The API gives today's sunrise and
// sunset at the estate (from /v1/admin/map and /v1/admin/live). Between polls, and on pages that
// do not poll, the same times are carried forward a day at a time: they drift about a minute a
// day near the equator, which is close enough to switch on the right minute.

export type Theme = "day" | "night";
export type ThemePref = "auto" | Theme;

export const THEME_KEY = "gatelog.dashboard.theme";
const DAY_MS = 86_400_000;

function last(eventMs: number, now: number) {
  return eventMs + Math.floor((now - eventMs) / DAY_MS) * DAY_MS;
}

/** Night between sunset and sunrise. Day when the estate has no location yet. */
export function themeAt(sun: Sun | null | undefined, now: number): Theme {
  if (!sun) return "day";
  if (!sun.sunrise || !sun.sunset) return sun.is_night ? "night" : "day";
  const rise = last(Date.parse(sun.sunrise), now);
  const set = last(Date.parse(sun.sunset), now);
  return set > rise ? "night" : "day";
}

/** When the theme next changes on its own (the next sunrise or sunset), or null. */
export function nextSwitch(sun: Sun | null | undefined, now: number): number | null {
  if (!sun?.sunrise || !sun?.sunset) return null;
  const rise = last(Date.parse(sun.sunrise), now) + DAY_MS;
  const set = last(Date.parse(sun.sunset), now) + DAY_MS;
  return Math.min(rise, set);
}

export function readPref(): ThemePref {
  try {
    const v = window.localStorage.getItem(THEME_KEY);
    return v === "day" || v === "night" ? v : "auto";
  } catch {
    return "auto";
  }
}

export function writePref(p: ThemePref) {
  try {
    if (p === "auto") window.localStorage.removeItem(THEME_KEY);
    else window.localStorage.setItem(THEME_KEY, p);
  } catch {
    // Private windows and blocked storage: the choice lasts until the page is closed.
  }
}
