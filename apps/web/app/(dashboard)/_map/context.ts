"use client";

import { createContext, useContext } from "react";
import type { Map as MapLibre } from "maplibre-gl";
import type { EstateMapData, Live } from "@/app/(dashboard)/_lib/types";
import type { Theme, ThemePref } from "./theme";

/**
 * live   the overview: the map is interactive and refreshed every 10 seconds
 * edit   the map editor (admin): interactive, the editor draws its own pins
 * still  every other page: a dimmed, fixed background behind the page
 * none   no boundary yet: no map
 */
export type MapMode = "live" | "edit" | "still" | "none";

export type MapLib = typeof import("maplibre-gl");

export type MapContextValue = {
  mode: MapMode;
  data: EstateMapData | null;
  live: Live | null;
  liveError: string | null;
  liveAt: number | null;
  theme: Theme;
  pref: ThemePref;
  setPref: (p: ThemePref) => void;
  /** The one MapLibre instance, once it has loaded (client only). */
  map: MapLibre | null;
  lib: MapLib | null;
  setEngine: (map: MapLibre | null, lib: MapLib | null) => void;
  /** The imagery credit for what is on screen (Google's changes with the view). */
  credit: string | null;
  setCredit: (c: string | null) => void;
  canSeePositions: boolean;
  admin: boolean;
  /** Move the map to a point (used by "Show on map" in the panels). */
  flyTo: (lng: number, lat: number) => void;
};

export const MapContext = createContext<MapContextValue | null>(null);

export function useEstateMap(): MapContextValue {
  const v = useContext(MapContext);
  if (!v) throw new Error("useEstateMap outside MapShell");
  return v;
}
